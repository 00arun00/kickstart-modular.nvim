-- Render comment cells through isolated Markdown buffers. Python parsers, source
-- text, undo history and Molten's execution ranges are never modified.
local M = {}
local ns = vim.api.nvim_create_namespace 'python-notebook-markdown'
local states = {}

local function dispose(cell)
  for _, image in ipairs(cell.images or {}) do
    image:close()
  end
  if cell.shadow and vim.api.nvim_buf_is_valid(cell.shadow) then vim.api.nvim_buf_delete(cell.shadow, { force = true }) end
end

local function scan(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'python')
  local tree = ok and parser:parse()[1]
  local cells, current = {}, nil
  for i, line in ipairs(lines) do
    local marker = line == '# %%' or line:match '^# %%%% '
    if marker and tree then marker = tree:root():named_descendant_for_range(i - 1, 0, i - 1, #line):type() == 'comment' end
    if marker then
      if current then current.last = i - 2 end
      current = nil
      if line:find('[markdown]', 1, true) then
        current = { first = i - 1, last = #lines - 1, text = {}, prefixes = {}, images = {} }
        table.insert(cells, current)
      end
    elseif current then
      local prefix = line:match '^# ?' or ''
      -- A non-comment line is Python, even if the preceding marker was malformed.
      if prefix == '' and line:find '%S' then
        current.last = i - 2
        current = nil
      else
        table.insert(current.text, line:sub(#prefix + 1))
        table.insert(current.prefixes, #prefix)
      end
    end
  end
  return cells
end

local function project(cell, row, col) return cell.first + 1 + row, col + (cell.prefixes[row + 1] or 0) end

local function mark(buf, cell, row, col, opts)
  local r, c = project(cell, row, col)
  if r > cell.last then return end
  opts = vim.deepcopy(opts)
  if opts.end_row then
    local ending = opts.end_row
    opts.end_row = math.min(cell.first + 1 + ending, cell.last + 1)
    if opts.end_col and opts.end_col > 0 then opts.end_col = opts.end_col + (cell.prefixes[ending + 1] or 0) end
  end
  opts.priority = opts.priority or 200
  opts.strict = false
  vim.api.nvim_buf_set_extmark(buf, ns, r, c, opts)
end

-- Jupytext keeps pasted-image attachments in notebook JSON, not percent text.
local function attachment(buf, cell, src)
  local name = src:match '^attachment:(.+)$'
  if not name then return src end
  local ok, notebook = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(vim.api.nvim_buf_get_name(buf)), '\n')) end)
  if not ok or type(notebook) ~= 'table' then return nil end
  local markdown, selected = {}, nil
  for _, item in ipairs(notebook.cells or {}) do
    if item.cell_type == 'markdown' then
      table.insert(markdown, item)
      local source = type(item.source) == 'table' and table.concat(item.source) or item.source
      if vim.trim(source or '') == vim.trim(table.concat(cell.text, '\n')) then selected = item end
    end
  end
  selected = selected or markdown[cell.ordinal]
  local data = selected and (selected.attachments or {})[name]
  if not data then return nil end
  for _, format in ipairs { { 'image/png', 'png' }, { 'image/jpeg', 'jpg' }, { 'image/gif', 'gif' } } do
    local encoded = data[format[1]]
    if encoded then
      if type(encoded) == 'table' then encoded = table.concat(encoded) end
      local valid, decoded = pcall(vim.base64.decode, encoded)
      if not valid then return nil end
      local dir = vim.fn.stdpath 'cache' .. '/notebook-markdown'
      vim.fn.mkdir(dir, 'p')
      local path = dir .. '/' .. vim.fn.sha256(encoded) .. '.' .. format[2]
      if vim.fn.filereadable(path) == 0 then
        local file = assert(io.open(path, 'wb'))
        file:write(decoded)
        file:close()
      end
      return path
    end
  end
end

local function build(buf, cell, win)
  if #cell.text == 0 then return end
  local shadow = vim.api.nvim_create_buf(false, true)
  cell.shadow = shadow
  vim.api.nvim_buf_set_name(shadow, vim.api.nvim_buf_get_name(buf) .. '.markdown-cell-' .. shadow .. '.md')
  vim.api.nvim_buf_set_lines(shadow, 0, -1, false, cell.text)
  -- No FileType event: this is a parser input, not another editor/LSP document.
  local parser = vim.treesitter.get_parser(shadow, 'markdown')
  parser:parse(true)
  local config = require('render-markdown.state').get(shadow, { anti_conceal = { enabled = false }, render_modes = true })
  local context = require('render-markdown.request.context').new(shadow, win, config)
  -- Pinned render-markdown adapter: include the full cell even though the
  -- parser input is hidden. No shared parser or renderer functions are patched.
  context.view.ranges = { { 0, #cell.text } }
  cell.marks = require('render-markdown.core.handlers').run(context, parser)
  cell.highlights = {}
  parser:for_each_tree(function(tree, language)
    local query = vim.treesitter.query.get(language:lang(), 'highlights')
    if not query then return end
    for id, node, metadata in query:iter_captures(tree:root(), shadow, 0, -1) do
      local capture = query.captures[id]
      if capture:sub(1, 1) ~= '_' and capture ~= 'spell' and capture ~= 'nospell' then
        local sr, sc, er, ec = node:range()
        local opts = { end_row = er, end_col = ec, hl_group = '@' .. capture .. '.' .. language:lang(), priority = 130 }
        local conceal = (metadata[id] or {}).conceal or metadata.conceal
        if conceal then opts.conceal = conceal end
        table.insert(cell.highlights, { sr, sc, opts })
      end
    end
  end)
  -- Legacy notebook answer prompts often use a whole-line <font> wrapper.
  -- Render only this conservative paired form, never literal code examples.
  for i, text in ipairs(cell.text) do
    local opening, body = text:match '^(<font%s+[^>]+>)(.-)</font>$'
    if opening then
      local node = parser:parse()[1]:root():named_descendant_for_range(i - 1, 0, i - 1, #text)
      local literal = false
      while node do
        if node:type() == 'fenced_code_block' or node:type() == 'indented_code_block' then literal = true end
        node = node:parent()
      end
      if not literal then
        table.insert(cell.highlights, { i - 1, 0, { end_row = i - 1, end_col = #opening, conceal = '', priority = 260 } })
        table.insert(cell.highlights, { i - 1, #opening + #body, { end_row = i - 1, end_col = #text, conceal = '', priority = 260 } })
      end
    end
  end
  if require('custom.python.images').enabled() then
    -- Snacks asks for a parser without a language; register Markdown only for
    -- this scratch buffer, without attaching its document autocmds.
    vim.b[shadow].snacks_image_attached = true
    vim.bo[shadow].filetype = 'markdown'
    Snacks.image.doc.find(shadow, function(matches)
      if not vim.api.nvim_buf_is_valid(shadow) then return end
      cell.media = {}
      for _, media in ipairs(matches) do
        media.src = attachment(buf, cell, media.src)
        if media.src then table.insert(cell.media, media) end
      end
      vim.schedule(function()
        if states[buf] then
          states[buf].active = nil
          M.update(buf)
        end
      end)
    end)
  end
end

local function refresh(buf, force)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = states[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  if win == -1 then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local width = vim.api.nvim_win_get_width(win)
  local changed = tick ~= state.tick or width ~= state.width or force
  if changed then
    local previous = state.cells
    state.cells = scan(buf)
    for i, cell in ipairs(state.cells) do
      local old = previous[i]
      if
        old
        and not force
        and width == state.width
        and old.first == cell.first
        and old.last == cell.last
        and vim.deep_equal(old.text, cell.text)
        and vim.deep_equal(old.prefixes, cell.prefixes)
      then
        state.cells[i] = old
      else
        if old then dispose(old) end
        cell.ordinal = i
        build(buf, cell, win)
      end
    end
    for i = #state.cells + 1, #previous do
      dispose(previous[i])
    end
    state.tick, state.width = tick, width
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local active_key = 'none'
  for i, cell in ipairs(state.cells) do
    if row >= cell.first and row <= cell.last then active_key = tostring(i) end
  end
  active_key = active_key .. tostring(state.enabled)
  if not changed and active_key == state.active then return end
  state.active = active_key
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, cell in ipairs(state.cells) do
    local active = row >= cell.first and row <= cell.last
    if active or not state.enabled then
      for _, image in ipairs(cell.images) do
        image:close()
      end
      cell.images = {}
    else
      for i, prefix in ipairs(cell.prefixes) do
        local r = cell.first + i
        vim.api.nvim_buf_set_extmark(buf, ns, r, 0, { end_row = r + 1, hl_group = 'Normal', hl_eol = true, priority = 110 })
        if prefix > 0 then vim.api.nvim_buf_set_extmark(buf, ns, r, 0, { end_col = prefix, conceal = '', priority = 250 }) end
      end
      for _, hl in ipairs(cell.highlights or {}) do
        mark(buf, cell, hl[1], hl[2], hl[3])
      end
      for _, m in ipairs(cell.marks or {}) do
        mark(buf, cell, m.start_row, m.start_col, m.opts)
      end
      if #cell.images == 0 then
        for _, media in ipairs(cell.media or {}) do
          local r, c = project(cell, media.pos[1] - 1, media.pos[2])
          local range = media.range and vim.deepcopy(media.range)
          if range then
            local r1, c1 = project(cell, range[1] - 1, range[2])
            local r2, c2 = project(cell, range[3] - 1, range[4])
            range = { r1 + 1, c1, r2 + 1, c2 }
          end
          local opts = vim.tbl_deep_extend('force', {}, Snacks.image.config.doc, {
            inline = true,
            pos = { r + 1, c },
            range = range,
            conceal = media.type == 'math' or media.type == 'chart',
            on_update = function()
              if package.loaded['custom.python.cells_ui'] then require('custom.python.cells_ui').update(buf, true) end
            end,
          })
          table.insert(cell.images, Snacks.image.placement.new(buf, media.src, opts))
        end
      end
    end
  end
  for _, window in ipairs(vim.fn.win_findbuf(buf)) do
    if not state.windows[window] then state.windows[window] = { vim.wo[window].conceallevel, vim.wo[window].concealcursor, vim.wo[window].linebreak } end
    local original = state.windows[window]
    vim.wo[window].conceallevel = state.enabled and #state.cells > 0 and 2 or original[1]
    vim.wo[window].concealcursor = state.enabled and #state.cells > 0 and 'nvic' or original[2]
    vim.wo[window].linebreak = state.enabled and #state.cells > 0 or original[3]
  end
  return true
end

-- Snacks may process events while detecting the terminal/converting images.
-- Serialize updates so a nested cursor event cannot duplicate placements.
function M.update(buf, force)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = states[buf]
  if not state then return end
  if state.updating then
    state.retry = true
    return
  end
  state.updating = true
  local ok, err = xpcall(function() return refresh(buf, force) end, debug.traceback)
  state.updating = false
  if state.retry then
    state.retry = false
    state.active = nil
    vim.schedule(function() M.update(buf) end)
  end
  if not ok then error(err) end
  if err and package.loaded['custom.python.cells_ui'] then require('custom.python.cells_ui').update(buf, true) end
end

function M.toggle()
  local state = states[vim.api.nvim_get_current_buf()]
  if not state then return end
  state.enabled = not state.enabled
  M.update()
end

function M.attach(buf)
  if states[buf] or vim.bo[buf].filetype ~= 'python' or vim.bo[buf].buftype ~= '' then return end
  if not vim.api.nvim_buf_get_name(buf):match '%.ipynb$' and #scan(buf) == 0 then return end
  require 'render-markdown'
  states[buf] = { enabled = true, cells = {}, windows = {} }
  local pending = false
  local function update(event)
    if states[buf] and event and (event.event == 'BufWinEnter' or event.event == 'WinEnter') then states[buf].active = nil end
    if pending then return end
    pending = true
    vim.defer_fn(function()
      pending = false
      if states[buf] then
        local ok, err = pcall(M.update, buf)
        if not ok then vim.notify('Notebook Markdown: ' .. tostring(err), vim.log.levels.ERROR) end
      end
    end, 40)
  end
  local group = vim.api.nvim_create_augroup('python-markdown-' .. buf, { clear = true })
  vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'BufWinEnter', 'WinEnter', 'InsertLeave' },
    { buffer = buf, group = group, callback = update }
  )
  vim.api.nvim_create_autocmd('BufWinLeave', {
    buffer = buf,
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local original = states[buf] and states[buf].windows[win]
      if original then
        vim.wo[win].conceallevel, vim.wo[win].concealcursor, vim.wo[win].linebreak = original[1], original[2], original[3]
        states[buf].windows[win] = nil
        states[buf].active = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    group = group,
    once = true,
    callback = function()
      for _, cell in ipairs(states[buf].cells) do
        dispose(cell)
      end
      states[buf] = nil
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, { group = group, callback = update })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      if states[buf] then
        states[buf].tick = nil
        update()
      end
    end,
  })
  update()
end

function M.setup()
  local group = vim.api.nvim_create_augroup('python-notebook-markdown', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'python',
    callback = function(ev)
      vim.schedule(function() M.attach(ev.buf) end)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end

return M
