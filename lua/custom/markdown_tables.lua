-- Inline math tables: native-text virtual rows with Snacks equation grids.
-- Source text stays in the buffer; entering a table reveals it for editing.
local M = {}
local states = {}
local find_images
local function supported(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'markdown' then return false end
  if not Snacks.image.supports_terminal() or not Snacks.image.terminal.env().placeholders then return false end
  return require('render-markdown.state').get(buf).enabled
end

local function release(state)
  if not state then return end
  for _, item in pairs(state.grids or {}) do
    item.img:del(item.listener.id)
  end
  for _, item in pairs(state.images or {}) do
    item.img:del(item.listener.id)
  end
end

local function refresh(buf, state)
  if state.queued then return end
  state.queued = true
  vim.schedule(function()
    state.queued = false
    if states[buf] == state and vim.api.nvim_buf_is_valid(buf) then require('render-markdown').render { buf = buf } end
  end)
end

local function scan(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if states[buf] and states[buf].tick == tick then return states[buf] end
  release(states[buf])
  local state = { tick = tick, tables = {}, images = {}, grids = {} }
  states[buf] = state
  find_images(buf, function(equations)
    if states[buf] ~= state or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then return end
    local parser = vim.treesitter.get_parser(buf, 'markdown')
    local query = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
    for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
      local first, _, last, end_col = node:range()
      if end_col > 0 then last = last + 1 end
      local selected = vim.tbl_filter(function(image) return image.type == 'math' and image.range[1] > first and image.range[3] <= last end, equations)
      if #selected > 0 then
        local entry = { first = first, last = last - 1, model = require('custom.markdown_table_preview').model(buf, node, selected) }
        state.tables[#state.tables + 1] = entry
        for _, image in ipairs(selected) do
          if not state.images[image.src] then
            local img = Snacks.image.image.new(image.src)
            local listener = {
              update = function() refresh(buf, state) end,
              error = function()
                if not state.warned then
                  state.warned = true
                  vim.notify('A table equation could not be rendered; keeping the source table visible.', vim.log.levels.WARN)
                end
                refresh(buf, state)
              end,
            }
            -- Register one lifecycle listener/grid placement per equation.
            img:place(listener)
            state.images[image.src] = { img = img, listener = listener }
          end
        end
      end
    end
    state.loaded = true
    refresh(buf, state)
  end)
  return state
end

local function ready(entry, state)
  for _, row in ipairs(entry.model.rows) do
    for _, cell in ipairs(row) do
      for _, token in ipairs(cell) do
        if token.src and not state.images[token.src].img:ready() then return false end
      end
    end
  end
  return true
end

local function editing(buf, entry)
  if vim.api.nvim_get_current_buf() ~= buf then return false end
  local reading = require 'custom.markdown_reading'
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
  local layout = require('custom.markdown_table_preview').layout(entry.model, width, function(token, limit)
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

function M.parse(language, ctx)
  local original = require('render-markdown.handler.' .. language).parse(ctx)
  if not supported(ctx.buf) then return original end
  local state = scan(ctx.buf)
  local active = vim.tbl_filter(function(entry) return ready(entry, state) end, state.tables)
  -- Native borders/replacement rows and injected inline/HTML decorations must
  -- not coexist with the cell layout, including while revealing source.
  original = vim.tbl_filter(function(mark)
    for _, entry in ipairs(active) do
      if mark.start_row >= entry.first and mark.start_row <= entry.last then return false end
      if mark.conceal == 'table_border' and (mark.start_row == entry.first - 1 or mark.start_row == entry.last + 1) then return false end
    end
    return true
  end, original)
  if language ~= 'markdown' then return original end
  local width = vim.o.columns
  for _, win in ipairs(vim.fn.win_findbuf(ctx.buf)) do
    local info = vim.fn.getwininfo(win)[1]
    width = math.min(width, info.width - info.textoff)
  end
  for _, entry in ipairs(active) do
    if not editing(ctx.buf, entry) then
      local rows, groups, padding = compose(ctx.buf, entry, state, width)
      -- Fixed source-row anchors keep native motions, jumps and editing intact.
      for _, group in ipairs(groups) do
        local selected = group.anchor
        local above, below = {}, {}
        for index = group.first, group.last do
          if index < selected then above[#above + 1] = rows[index] end
          if index > selected then below[#below + 1] = rows[index] end
        end
        local line = vim.api.nvim_buf_get_lines(ctx.buf, group.source, group.source + 1, false)[1]
        original[#original + 1] = {
          conceal = false,
          start_row = group.source,
          start_col = 0,
          opts = {
            end_row = group.source,
            end_col = #line,
            conceal = '',
            virt_text = rows[selected],
            virt_text_pos = 'overlay',
            priority = 101,
            virt_lines = above,
            virt_lines_above = true,
          },
        }
        original[#original + 1] = {
          conceal = false,
          start_row = group.source,
          start_col = 0,
          -- Conceal hides characters but does not remove native wrap rows.
          -- Paint those continuations as cell padding, underneath the anchor
          -- row. Repeating the anchor row would duplicate labels/equations.
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
  return original
end

function M.setup()
  if find_images then return end
  local doc = Snacks.image.doc
  find_images = doc.find
  local visible = doc.find_visible
  doc.find_visible = function(buf, cb)
    visible(buf, function(images)
      if supported(buf) then
        scan(buf)
        local parser = vim.treesitter.get_parser(buf, 'markdown')
        local query = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
        local ranges = {}
        for _, node in query:iter_captures(parser:parse()[1]:root(), buf) do
          local first, _, last, col = node:range()
          ranges[#ranges + 1] = { first, col == 0 and last or last + 1 }
        end
        images = vim.tbl_filter(function(image)
          for _, range in ipairs(ranges) do
            if image.type == 'math' and image.range[1] > range[1] and image.range[3] <= range[2] then return false end
          end
          return true
        end, images)
      end
      cb(images)
    end)
  end
  vim.api.nvim_set_hl(0, 'MarkdownTablePreviewBold', { bold = true, default = true })
  vim.api.nvim_set_hl(0, 'MarkdownTablePreviewHeader', { link = 'Title', default = true })
  local group = vim.api.nvim_create_augroup('markdown-math-tables', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'ModeChanged', 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function(event)
      local state = states[event.buf]
      if not state or not supported(event.buf) then return end
      local inside = 0
      for index, entry in ipairs(state.tables) do
        if editing(event.buf, entry) then inside = index end
      end
      if state.editing ~= inside then
        state.editing = inside
        refresh(event.buf, state)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      local state = states[event.buf]
      release(state)
      states[event.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      for buf, state in pairs(states) do
        release(state)
        state.tick = nil
        refresh(buf, state)
      end
    end,
  })
end

return M
