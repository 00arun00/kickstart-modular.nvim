-- Retained math-table decorations. The document owner supplies one discovery
-- result; ordinary scrolling never rebuilds or clears this namespace.
local M = { ns = vim.api.nvim_create_namespace 'markdown-math-tables' }
local states = {}
local initialized = false

local function supported(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'markdown' then return false end
  if not Snacks.image.supports_terminal() or not Snacks.image.terminal.env().placeholders then return false end
  local renderer = package.loaded['render-markdown.state']
  if not (renderer and renderer.config) then return false end
  local config = renderer.get(buf)
  return config.enabled and config.resolved:render(vim.fn.mode())
end

local function valid(state)
  return not state.closed
    and states[state.buf] == state
    and vim.api.nvim_buf_is_valid(state.buf)
    and vim.api.nvim_buf_is_loaded(state.buf)
    and vim.api.nvim_buf_get_changedtick(state.buf) == state.tick
end

function M.hide(state)
  if not state then return end
  if vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_clear_namespace(state.buf, M.ns, 0, -1) end
  state.signature, state.awaiting_host = nil, false
end

function M.release(state)
  if not state or state.closed then return end
  state.closed = true
  M.hide(state)
  for _, item in pairs(state.grids) do
    if item.listener.id then item.img:del(item.listener.id) end
  end
  for _, item in pairs(state.images) do
    if item.listener.id then item.img:del(item.listener.id) end
  end
  state.grids, state.images = {}, {}
  if states[state.buf] == state then states[state.buf] = nil end
end

-- Build all table models from the same full-document equation discovery used
-- for ordinary math. This function never discovers or converts images itself.
function M.build(buf, equations)
  M.release(states[buf])
  local state = { buf = buf, tick = vim.api.nvim_buf_get_changedtick(buf), tables = {}, images = {}, grids = {} }
  states[buf] = state
  local parser = vim.treesitter.get_parser(buf, 'markdown')
  local query = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
  for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
    local first, _, last, col = node:range()
    if col > 0 then last = last + 1 end
    local selected = vim.tbl_filter(function(image) return image.type == 'math' and image.range[1] > first and image.range[3] <= last end, equations)
    if #selected > 0 then
      local ok, model = pcall(require('custom.markdown.table_preview').model, buf, node, selected)
      state.tables[#state.tables + 1] = { first = first, last = last - 1, model = ok and model or nil, skipped = not ok }
    end
  end
  return state
end

function M.contains(state, image)
  if not state or image.type ~= 'math' or not image.range then return false end
  for _, entry in ipairs(state.tables) do
    if image.range[1] > entry.first and image.range[3] <= entry.last + 1 then return true end
  end
  return false
end

local function changed(state)
  if state.queued then return end
  state.queued = true
  vim.schedule(function()
    state.queued = false
    if valid(state) then
      if state.on_change then
        state.on_change(state)
      else
        M.publish(state)
      end
    end
  end)
end

local function tokens(entry, callback)
  for _, row in ipairs(entry.model and entry.model.rows or {}) do
    for _, cell in ipairs(row) do
      for _, token in ipairs(cell) do
        if token.src then callback(token.src) end
      end
    end
  end
end

-- Called after cache preparation settles. Failed formula tables stay in the
-- normal Markdown renderer; they do not hold other tables or the note hostage.
function M.prepare(state, failed_sources)
  if not valid(state) or state.prepared then return end
  state.prepared = true
  failed_sources = failed_sources or {}
  for _, entry in ipairs(state.tables) do
    tokens(entry, function(src)
      if failed_sources[src] then entry.skipped = true end
    end)
    if not entry.skipped then
      tokens(entry, function(src)
        if state.images[src] then return end
        local img = Snacks.image.image.new(src)
        local listener = { update = function() changed(state) end, error = function() changed(state) end }
        state.images[src] = { img = img, listener = listener }
        img:place(listener)
      end)
    end
  end
end

local function table_ready(state, entry)
  if entry.skipped then return false end
  local ready = true
  tokens(entry, function(src)
    local item = state.images[src]
    if not item or not item.img:ready() then ready = false end
    if item and item.img:failed() then entry.skipped = true end
  end)
  return ready and not entry.skipped
end

function M.ready(state)
  if not valid(state) or not state.prepared then return false end
  for _, item in pairs(state.images) do
    if not item.img:ready() and not item.img:failed() then return false end
  end
  return M.publish(state) == true
end

local function editing(buf, entry)
  if vim.api.nvim_get_current_buf() ~= buf then return false end
  local reading = require 'custom.markdown.reading'
  if reading.is_enabled() and not reading.is_editing() then return false end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local other = vim.fn.getpos('v')[2] - 1
  local mode = vim.fn.mode():sub(1, 1)
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then other = row end
  return math.min(row, other) <= entry.last and math.max(row, other) >= entry.first
end

local function grid(buf, item, size, first, state, key)
  -- Identical formulas can appear inline and in display cells at different sizes.
  -- Each occurrence needs a separate placement ID to keep those sizes independent.
  if not state.grids[key] then
    local listener = { update = function() end, error = function() end }
    item.img:place(listener)
    state.grids[key] = { img = item.img, listener = listener }
  end
  local img, listener = item.img, state.grids[key].listener
  Snacks.image.terminal.request { a = 'p', U = 1, i = img.id, p = listener.id, C = 1, c = size.width, r = size.height }
  local rows = {}
  -- Reuse Snacks' encoded Unicode placeholders and highlighting, while
  -- collecting its output rather than writing per-equation buffer extmarks.
  local p = setmetatable({
    id = listener.id,
    img = img,
    buf = buf,
    opts = { range = { first + 1, 0, first + 1, 0 }, type = 'math' },
    _render = function(_, marks)
      for _, mark in ipairs(marks) do
        for _, chunk in ipairs(mark.virt_text or {}) do
          if chunk[2] == 'SnacksImage' .. listener.id then rows[#rows + 1] = { chunk } end
        end
        for _, line in ipairs(mark.virt_lines or {}) do
          rows[#rows + 1] = line
        end
      end
    end,
  }, { __index = Snacks.image.placement })
  p:render_grid { first + 1, 0, width = size.width, height = size.height }
  return rows
end

local function byte_at(text, column)
  for index = 0, vim.fn.strchars(text) do
    local prefix = vim.fn.strcharpart(text, 0, index)
    if vim.fn.strdisplaywidth(prefix) >= column then return #prefix end
  end
  return #text
end

local function compose(buf, entry, state, width)
  local layout = require('custom.markdown.table_preview').layout(entry.model, width, function(token, limit)
    local img = state.images[token.src].img
    return Snacks.image.util.fit(img.file, { width = limit, height = token.display and 8 or 1 }, { info = img.info })
  end)
  local spans = {}
  for _, hl in ipairs(layout.highlights) do
    local row = hl[1] + 1
    spans[row] = spans[row] or {}
    spans[row][#spans[row] + 1] = { start = hl[2], finish = hl[3], chunks = { { layout.lines[row]:sub(hl[2] + 1, hl[3]), hl[4] } } }
  end
  for index, image in ipairs(layout.images) do
    local rows = grid(buf, state.images[image.token.src], image, entry.first, state, entry.first .. ':' .. index)
    for y, chunks in ipairs(rows) do
      local row = image.row + y - 1
      spans[row] = spans[row] or {}
      local line = layout.lines[row]
      local first, last = byte_at(line, image.col), byte_at(line, image.col + image.width)
      -- Remove the native blank padding highlights under this image.
      spans[row] = vim.tbl_filter(function(span) return span.finish <= first or span.start >= last end, spans[row])
      spans[row][#spans[row] + 1] = { start = first, finish = last, chunks = chunks }
    end
  end
  local result = {}
  for row, line in ipairs(layout.lines) do
    local chunks, pos = {}, 0
    table.sort(spans[row] or {}, function(a, b) return a.start < b.start end)
    for _, span in ipairs(spans[row] or {}) do
      if span.start > pos then chunks[#chunks + 1] = { line:sub(pos + 1, span.start), 'Normal' } end
      vim.list_extend(chunks, span.chunks)
      pos = span.finish
    end
    if pos < #line then chunks[#chunks + 1] = { line:sub(pos + 1), 'Normal' } end
    result[row] = chunks
  end
  local padding = '│'
  for _, cell_width in ipairs(layout.widths) do
    padding = padding .. string.rep(' ', cell_width + 2) .. '│'
  end
  return result, layout.groups, { { padding, 'Normal' } }
end

-- Publish a complete retained table surface. Repeated scrolling in the same
-- document/width/edit state returns before touching extmarks or image grids.
function M.publish(state, from_host)
  if not state then return end
  if not valid(state) then return M.hide(state) end
  if not supported(state.buf) then
    M.hide(state)
    return true
  end
  local width, wins = vim.o.columns, 0
  for _, win in ipairs(vim.fn.win_findbuf(state.buf)) do
    local info = vim.fn.getwininfo(win)[1]
    width, wins = math.min(width, info.width - info.textoff), wins + 1
  end
  if wins == 0 then return true end
  width = math.max(1, width)
  local signature, active, ownership_changed = { width }, {}, false
  for _, entry in ipairs(state.tables) do
    local owned = table_ready(state, entry)
    ownership_changed = ownership_changed or entry.owned ~= owned
    entry.owned = owned
    local reveal = editing(state.buf, entry)
    signature[#signature + 1] = entry.owned and (reveal and 'source' or 'rendered') or 'pending'
    if entry.owned and not reveal then active[#active + 1] = entry end
  end
  signature = table.concat(signature, ':')
  if signature == state.signature and not state.awaiting_host then return true end
  -- The host may still own standard table borders and inline decorations from
  -- its previous parse. Acquire these ranges through its normal parse/display
  -- transaction, then install retained rows in on_render after it has finished.
  if ownership_changed and not from_host and package.loaded['render-markdown'] then
    state.awaiting_host = true
    if not state.host_queued then
      state.host_queued = true
      vim.schedule(function()
        state.host_queued = false
        if valid(state) then require('render-markdown').render { buf = state.buf } end
      end)
    end
  end
  if state.awaiting_host and not from_host then return false end
  local marks = {}
  for _, entry in ipairs(active) do
    local ok, rows, groups, padding = pcall(compose, state.buf, entry, state, width)
    if not ok then
      entry.skipped, entry.owned = true, false
      for key, item in pairs(state.grids) do
        if vim.startswith(key, entry.first .. ':') then
          if item.listener.id then item.img:del(item.listener.id) end
          state.grids[key] = nil
        end
      end
      if not state.warned then
        state.warned = true
        vim.notify('A math table could not be laid out; keeping its source visible.', vim.log.levels.WARN)
      end
    else
      for _, group in ipairs(groups) do
        local above, below = {}, {}
        for index = group.first, group.last do
          if index < group.anchor then above[#above + 1] = rows[index] end
          if index > group.anchor then below[#below + 1] = rows[index] end
        end
        local line = vim.api.nvim_buf_get_lines(state.buf, group.source, group.source + 1, false)[1]
        marks[#marks + 1] = {
          row = group.source,
          opts = {
            end_row = group.source,
            end_col = #line,
            conceal = '',
            virt_text = rows[group.anchor],
            virt_text_pos = 'overlay',
            priority = 101,
            virt_lines = above,
            virt_lines_above = true,
          },
        }
        marks[#marks + 1] = {
          row = group.source,
          opts = {
            virt_text = padding,
            virt_text_pos = 'overlay',
            virt_text_repeat_linebreak = true,
            priority = 100,
            virt_lines = below,
          },
        }
      end
    end
  end
  vim.api.nvim_buf_clear_namespace(state.buf, M.ns, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(state.buf, M.ns, mark.row, 0, mark.opts)
  end
  local committed = state.awaiting_host
  state.signature, state.awaiting_host = signature, false
  if committed then changed(state) end
  return true
end

function M.parse(language, ctx)
  local original = require('render-markdown.handler.' .. language).parse(ctx)
  local state = states[ctx.buf]
  if not state then return original end
  M.publish(state)
  if not valid(state) or not supported(ctx.buf) then return original end
  -- The retained table namespace owns these ranges even while revealing their
  -- source. Host Markdown/inline/HTML decorations must not compete with it.
  return vim.tbl_filter(function(mark)
    for _, entry in ipairs(state.tables) do
      if entry.owned then
        if mark.start_row >= entry.first and mark.start_row <= entry.last then return false end
        if mark.conceal == 'table_border' and (mark.start_row == entry.first - 1 or mark.start_row == entry.last + 1) then return false end
      end
    end
    return true
  end, original)
end

function M.on_render(ctx) M.publish(states[ctx.buf], true) end
function M.on_clear(ctx)
  if not supported(ctx.buf) then M.hide(states[ctx.buf]) end
end

function M.setup()
  if initialized then return end
  initialized = true
  local function highlights()
    vim.api.nvim_set_hl(0, 'MarkdownTablePreviewBold', { bold = true, default = true })
    vim.api.nvim_set_hl(0, 'MarkdownTablePreviewHeader', { link = 'Title', default = true })
  end
  highlights()
  local group = vim.api.nvim_create_augroup('markdown-math-tables', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'BufEnter', 'WinEnter', 'WinResized' }, {
    group = group,
    callback = function()
      for _, state in pairs(states) do
        M.publish(state)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event) M.release(states[event.buf]) end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
end

return M
