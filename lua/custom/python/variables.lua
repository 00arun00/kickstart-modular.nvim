local M = {}
local api = vim.api
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))))
local state
local ns = api.nvim_create_namespace 'python-variables'
local selection_ns = api.nvim_create_namespace 'python-variable-selection'
local artifacts = {}
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('variable-artifacts', { clear = true }),
  callback = function()
    for _, file in ipairs(artifacts) do
      vim.fn.delete(file)
    end
  end,
})

local function clean(value) return tostring(value or ''):gsub('[\r\n\t]', ' ') end
local function fit(value, width)
  local s = clean(value)
  if vim.fn.strdisplaywidth(s) > width then
    while vim.fn.strdisplaywidth(s) > width - 1 do
      s = vim.fn.strcharpart(s, 0, vim.fn.strchars(s) - 1)
    end
    s = s .. '…'
  end
  return s .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(s)))
end
local function write(s, content)
  if not api.nvim_buf_is_valid(s.buf) then return end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, vim.tbl_map(clean, content))
  vim.bo[s.buf].modifiable = false
end
local function connection(source, kernel)
  if not api.nvim_buf_is_valid(source) then return nil, 'Notebook buffer closed' end
  local attached = api.nvim_buf_call(source, function() return vim.fn.MoltenRunningKernels(true) end)
  if not vim.tbl_contains(attached, kernel) then return nil, 'Kernel stopped · reopen from the notebook' end
  local path = require('custom.python.notebook').connections[kernel]
  if not path then return nil, 'Start a fresh kernel with Space j i' end
  local ok, value = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  if not ok or not value.generation then return nil, 'Kernel starting or unavailable · refresh when ready' end
  return { path = path, generation = value.generation }
end
local function metadata(item)
  local parts = { item.type }
  if item.shape then table.insert(parts, #item.shape == 0 and 'scalar' or table.concat(item.shape, ' × ')) end
  for _, key in ipairs { 'dtype', 'device' } do
    if item[key] then table.insert(parts, item[key]) end
  end
  if item.requires_grad then table.insert(parts, 'grad') end
  return table.concat(parts, ' · ')
end
local function popup(title, content, tall)
  local buf = api.nvim_create_buf(false, true)
  local width, height = math.min(100, vim.o.columns - 6), math.min(#content + 2, vim.o.lines - 8)
  if tall then height = math.max(3, math.min(32, vim.o.lines - 8)) end
  api.nvim_buf_set_lines(buf, 0, -1, false, content)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = math.max(3, height),
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
    footer = ' q close ',
    footer_pos = 'right',
    style = 'minimal',
  })
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.wo[win].wrap = true
  vim.wo[win].list = false
  for _, key in ipairs { 'q', '<Esc>' } do
    vim.keymap.set('n', key, function() api.nvim_win_close(win, true) end, { buffer = buf })
  end
  return buf, win
end
local function render(s, data)
  if not api.nvim_buf_is_valid(s.buf) or not api.nvim_win_is_valid(s.win) then return end
  if not data.error then s.schema = data end
  local schema = s.schema or data
  local actions = 'r refresh   u back   ? help   q close'
  if not s.view.name then
    actions = 'Enter inspect   f filter   s sort   ' .. actions
  elseif schema.rows then
    actions = 'p plot   ' .. actions
    if not s.view.renderer and (schema.kind == 'dataframe' or schema.kind == 'series') then actions = 'f filter   s sort   ' .. actions end
    if schema.shape and #schema.shape > 2 then actions = 't slice   ' .. actions end
  end
  if api.nvim_win_get_width(s.win) < 60 then
    actions = not s.view.name and 'Enter inspect · f/s · r · u · ? · q' or 'Enter value · r · u · ? · q'
    if schema.rows then
      actions = 'p plot · r · u · ? · q'
      if not s.view.renderer and (schema.kind == 'dataframe' or schema.kind == 'series') then actions = 'f/s · ' .. actions end
      if schema.shape and #schema.shape > 2 then actions = 't slice · ' .. actions end
    end
  end
  vim.wo[s.win].winbar = '%#Comment#  ' .. actions .. '%*'
  local width = math.max(20, api.nvim_win_get_width(s.win) - 4)
  local source = api.nvim_buf_is_valid(s.source) and vim.fs.basename(api.nvim_buf_get_name(s.source)) or 'closed notebook'
  local title = not s.view.name and 'VARIABLES' or 'INSPECT'
  local name = data.name or (data.error and schema.name) or s.view.name or 'Namespace'
  local content = { '  ' .. title .. '   ' .. fit(source, math.max(8, width - 12)), '  ' .. fit(name, width) }
  local subtitle = data.entries and string.format('%d variables · snapshot %s', data.total or #data.entries, os.date '%H:%M:%S') or metadata(data)
  if s.view.renderer then subtitle = 'Renderer: ' .. s.view.renderer .. ' · source ' .. metadata(schema) end
  if data.error then subtitle = 'Unable to refresh' end
  table.insert(content, '  ' .. fit(subtitle, width))
  if s.message then table.insert(content, '  ' .. fit(s.message, width)) end
  s.entries, s.cells = {}, {}
  local highlights = { { 0, 'Title' }, { 1, 'Special' }, { 2, 'Comment' } }
  local function add(line, hl)
    table.insert(content, line)
    if hl then table.insert(highlights, { #content - 1, hl }) end
    return #content
  end
  if data.error then
    add ''
    add('  ' .. clean(data.error), 'DiagnosticWarn')
    add('  r retry · u back · q close', 'Comment')
    if s.view.filter then add('  f correct filter (blank clears)', 'Comment') end
    if s.view.slice then add('  t correct leading indices', 'Comment') end
  elseif data.entries or data.children then
    local items = data.entries or data.children
    if s.view.query and s.view.query ~= '' then add('  Filter: ' .. s.view.query, 'DiagnosticInfo') end
    add ''
    local namewidth = math.max(10, math.floor(width * 0.25))
    local typewidth = math.max(12, math.floor(width * 0.43))
    local previewwidth = math.max(4, width - namewidth - typewidth - 4)
    add('  ' .. fit('NAME', namewidth) .. '  ' .. fit('TYPE / SHAPE', typewidth) .. '  ' .. fit('VALUE', previewwidth), 'Comment')
    add('  ' .. string.rep('─', width), 'FloatBorder')
    for _, item in ipairs(items) do
      local row = add('  ' .. fit(item.name, namewidth) .. '  ' .. fit(metadata(item), typewidth) .. '  ' .. fit(item.summary, previewwidth))
      s.entries[row] = item
    end
    if #items == 0 then add('  No matching variables. f clears/changes the filter.', 'Comment') end
    local total = data.total or data.total_rows or #items
    add ''
    add(string.format('  %d–%d of %d   [p previous · ]p next', math.min((data.row or 0) + 1, total), (data.row or 0) + #items, total), 'Comment')
    if data.entries then add('  f filter · s sort · H hidden names', 'Comment') end
  elseif data.rows then
    s.row, s.col, s.total_rows, s.total_cols = data.row, data.col, data.total_rows, data.total_cols
    if data.note then add('  ' .. data.note, 'DiagnosticInfo') end
    if s.view.filter then add('  Filter: col ' .. s.view.filter.column .. ' ' .. s.view.filter.op .. ' ' .. tostring(s.view.filter.value), 'DiagnosticInfo') end
    if s.view.sort_col then add('  Sorted: col ' .. s.view.sort_col .. (s.view.descending and ' ↓' or ' ↑'), 'DiagnosticInfo') end
    add(
      string.format(
        '  Rows %d–%d / %d · columns %d–%d / %d',
        math.min(s.row + 1, s.total_rows),
        s.row + #data.rows,
        s.total_rows,
        math.min(s.col + 1, s.total_cols),
        math.min(s.col + #(data.columns or {}), s.total_cols),
        s.total_cols
      ),
      'Comment'
    )
    add ''
    local columns = data.columns or {}
    local count = math.max(#columns, data.rows[1] and #data.rows[1] or 0)
    local cellwidth = math.max(5, math.min(22, math.floor((width - 11) / math.max(1, count)) - 3))
    s.selected_col = math.max(1, math.min(s.selected_col or 1, math.max(1, count)))
    local header = '  ' .. fit('index', 6) .. ' │ '
    local offsets = {}
    for i = 1, count do
      offsets[i] = #header
      header = header .. fit(columns[i] or tostring(s.col + i - 1), cellwidth) .. ' │ '
    end
    add(header, 'Special')
    add('  ' .. string.rep('─', math.min(#header - 2, width)), 'FloatBorder')
    for i, row in ipairs(data.rows) do
      local line = '  ' .. fit(data.index and data.index[i] or tostring(s.row + i - 1), 6) .. ' │ '
      local cells = {}
      for j, value in ipairs(row) do
        local display = data.display_rows and data.display_rows[i] and data.display_rows[i][j] or value
        cells[j] = { byte = #line, finish = #line + #fit(display, cellwidth), value = value, row = i, col = j }
        line = line .. fit(display, cellwidth) .. ' │ '
      end
      s.cells[add(line)] = cells
    end
    if #data.rows == 0 then add('  Empty view · f clears filter', 'Comment') end
    add ''
    add('  h/l select column · Enter value text · y copy', 'Comment')
    add('  [p/]p rows · [c/]c columns · g jump', 'Comment')
    local controls = '  p plot · R render'
    if (data.kind == 'dataframe' or data.kind == 'series') and not s.view.renderer then controls = controls .. ' · f filter · s sort' end
    if data.shape and #data.shape > 2 and (data.kind == 'tensor' or data.kind == 'array') then controls = controls .. ' · t slice' end
    add(controls, 'Comment')
  else
    add ''
    add('  ' .. (data.note or data.summary or 'No preview'))
    add ''
    add('  Enter value text · R custom renderer', 'Comment')
  end
  write(s, content)
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_set_extmark(s.buf, ns, hl[1], 0, { end_row = hl[1] + 1, hl_group = hl[2] })
  end
  s.data = data
  vim.b[s.buf].variable_snapshot = data
  local selectable = vim.tbl_keys(next(s.entries) and s.entries or s.cells)
  table.sort(selectable)
  if #selectable > 0 then
    local current = api.nvim_win_get_cursor(s.win)[1]
    local preferred
    for row, item in pairs(s.entries) do
      if item.name == s.focus then
        preferred = row
        break
      end
    end
    if preferred then
      api.nvim_win_set_cursor(s.win, { preferred, 0 })
    elseif not s.entries[current] and not s.cells[current] then
      api.nvim_win_set_cursor(s.win, { selectable[1], 0 })
    end
  end
  api.nvim_win_call(s.win, function() vim.fn.winrestview { leftcol = 0 } end)
end
local function choose_cell(s)
  if not api.nvim_win_is_valid(s.win) then return end
  local row = api.nvim_win_get_cursor(s.win)[1]
  local cell = s.cells[row] and s.cells[row][s.selected_col or 1]
  api.nvim_buf_clear_namespace(s.buf, selection_ns, 0, -1)
  if cell then
    api.nvim_buf_set_extmark(s.buf, selection_ns, row - 1, cell.byte, { end_col = cell.finish, hl_group = 'Visual', priority = 200 })
    if api.nvim_win_get_cursor(s.win)[2] ~= cell.byte then api.nvim_win_set_cursor(s.win, { row, cell.byte }) end
  end
  return cell
end
local function show_plot(s, data, style)
  local file = vim.fn.tempname() .. '.svg'
  vim.fn.writefile({ data.plot }, file)
  table.insert(artifacts, file)
  vim.b[s.buf].variable_plot = file
  local info = {
    'Plot of the current page: ' .. data.name,
    '',
    'SVG: ' .. file,
    '',
    'o open externally · q close',
    '',
    'This preview uses only the visible page, not the full dataset.',
  }
  local buf = popup(style .. ' · current page', info, true)
  vim.keymap.set('n', 'o', function() vim.ui.open(file) end, { buffer = buf })
  if vim.fn.executable 'magick' == 1 then
    local png = file:gsub('%.svg$', '.png')
    table.insert(artifacts, png)
    local command = { 'magick' }
    for _, font in ipairs {
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      (vim.env.WINDIR or 'C:/Windows') .. '/Fonts/arial.ttf',
    } do
      if vim.fn.filereadable(font) == 1 then
        vim.list_extend(command, { '-font', font })
        break
      end
    end
    vim.list_extend(command, { file, png })
    vim.system(
      command,
      { text = true, timeout = 10000 },
      vim.schedule_wrap(function(result)
        if result.code == 0 then
          if api.nvim_buf_is_valid(s.buf) then vim.b[s.buf].variable_plot_image = png end
          if api.nvim_buf_is_valid(buf) and require('custom.python.images').enabled() then require('snacks').image.buf.attach(buf, { src = png }) end
        elseif api.nvim_buf_is_valid(buf) then
          vim.notify('Inline plot conversion failed; o still opens the SVG externally', vim.log.levels.WARN)
        end
      end)
    )
  end
  -- Keep the file for reopening/export during this Neovim session.
end
local function fetch(s, action, plot)
  local conn, err = connection(s.source, s.kernel)
  if not conn then return render(s, { error = err }) end
  if s.job then s.job:kill(15) end
  local serial = (s.serial or 0) + 1
  s.serial = serial
  local request = vim.deepcopy(s.view)
  s.page_cols = math.max(1, math.min(8, math.floor((api.nvim_win_get_width(s.win) - 14) / 14)))
  request.cols = s.page_cols
  request.action, request.plot, request.selected_col = action, plot, (s.selected_col or 1) - 1
  s.message = 'Refreshing…'
  render(s, s.data or { entries = {}, total = 0 })
  vim.b[s.buf].variable_snapshot = nil
  s.job = vim.system(
    { require('custom.python.host').executable 'python', root .. '/scripts/inspect-kernel.py', conn.path, conn.generation, vim.json.encode(request) },
    { text = true, timeout = 6500 },
    vim.schedule_wrap(function(result)
      if state ~= s or s.serial ~= serial or not api.nvim_buf_is_valid(s.buf) then return end
      s.job = nil
      s.message = nil
      local current, reason = connection(s.source, s.kernel)
      if not current or current.generation ~= conn.generation then return render(s, { error = reason or 'Kernel restarted · refresh for new values' }) end
      local ok, reply = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok then return render(s, { error = 'Inspection timed out · refresh when kernel is idle' }) end
      local data = reply.ok and reply.data or { error = reply.error }
      if not data.error then
        s.view.row = data.row or 0
        s.view.col = data.col or 0
      end
      if action == 'plot' and data.plot then
        render(s, data)
        show_plot(s, data, plot)
      else
        render(s, data)
      end
      choose_cell(s)
    end)
  )
end
function M.refresh()
  if state then fetch(state) end
end
function M.view(changes)
  local s = state
  if not s then return end
  for k, v in pairs(changes) do
    s.view[k] = v ~= false and v or nil
  end
  fetch(s)
end
function M.back()
  local s = state
  if not s then return end
  local previous = table.remove(s.history)
  s.view = previous and previous.view or { row = 0, col = 0 }
  s.focus = previous and previous.focus or nil
  s.selected_col = 1
  fetch(s)
end
function M.filter(input)
  local s = state
  if not s then return end
  if not s.view.name then return M.view { query = input, row = 0 } end
  if s.view.renderer or not s.schema or not vim.tbl_contains({ 'dataframe', 'series' }, s.schema.kind) then
    return vim.notify('Filtering is available in DataFrame and Series views', vim.log.levels.INFO)
  end
  if input == '' then return M.view { filter = false, row = 0 } end
  local op, value = input:match '^(%S+)%s+(.+)$'
  if not op or not vim.tbl_contains({ 'contains', '==', '!=', '>', '<', '>=', '<=' }, op) then
    return vim.notify('Use: contains text, > 3, == "label"; blank clears', vim.log.levels.WARN)
  end
  local ok, decoded = pcall(vim.json.decode, value)
  return M.view { filter = { column = (s.view.col or 0) + (s.selected_col or 1) - 1, op = op, value = ok and decoded or value }, row = 0 }
end
function M.sort()
  local s = state
  if not s then return end
  if not s.view.name then return M.view { sort = s.view.sort == 'type' and 'name' or 'type', row = 0 } end
  if s.view.renderer or not s.schema or not vim.tbl_contains({ 'dataframe', 'series' }, s.schema.kind) then
    return vim.notify('Sorting is available in DataFrame and Series views', vim.log.levels.INFO)
  end
  local col = (s.view.col or 0) + (s.selected_col or 1) - 1
  if s.view.sort_col ~= col then
    M.view { sort_col = col, descending = false, row = 0 }
  elseif not s.view.descending then
    M.view { descending = true, row = 0 }
  else
    M.view { sort_col = false, descending = false, row = 0 }
  end
end
function M.slice(input)
  if not state or not state.schema or not state.schema.shape or #state.schema.shape <= 2 then
    return vim.notify('Slicing applies to arrays/tensors with leading dimensions', vim.log.levels.INFO)
  end
  local indices = {}
  if input ~= '' then
    for index in input:gmatch '[^,%s]+' do
      local value = tonumber(index)
      if not value or value % 1 ~= 0 then return vim.notify('Enter integer indices separated by commas', vim.log.levels.WARN) end
      table.insert(indices, value)
    end
  end
  M.view { slice = indices, row = 0, col = 0 }
end
function M.plot(style)
  if state and state.data and state.data.rows then
    fetch(state, 'plot', style)
  else
    vim.notify('Open a numeric table or tensor before plotting', vim.log.levels.INFO)
  end
end
function M.enter()
  local s = state
  if not s or s.job then return end
  local row = api.nvim_win_get_cursor(s.win)[1]
  local item = s.entries[row]
  if item then
    if s.data.children and (not item.path or item.path == vim.NIL) then
      return vim.notify('This key cannot be addressed safely; inspect it in Python', vim.log.levels.INFO)
    end
    table.insert(s.history, { view = vim.deepcopy(s.view), focus = item.name })
    s.view = { name = s.view.name or item.name, path = item.path or {}, row = 0, col = 0 }
    s.focus = nil
    s.selected_col = 1
    return fetch(s)
  end
  local cell = choose_cell(s)
  local value = cell and cell.value or s.data.note or s.data.summary or ''
  local buf, win = popup('Value · ' .. (s.data.name or ''), vim.split(value, '\n', { plain = true }))
  api.nvim_win_set_config(win, { footer = ' y copy · q close ' })
  vim.keymap.set('n', 'y', function()
    vim.fn.setreg('"', value)
    pcall(vim.fn.setreg, '+', value)
    vim.notify 'Value copied'
  end, { buffer = buf })
end
function M.close()
  local s = state
  state = nil
  if not s then return end
  if s.job then s.job:kill(15) end
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
end
function M.open(name)
  if name == vim.NIL then name = nil end
  local source = api.nvim_get_current_buf()
  if state and source == state.buf then
    api.nvim_set_current_win(state.win)
    return
  end
  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then return vim.notify('Attach exactly one kernel with Space j i first', vim.log.levels.WARN) end
  local conn, err = connection(source, kernels[1])
  if not conn then return vim.notify(err, vim.log.levels.WARN) end
  M.close()
  if vim.o.columns < 110 then
    vim.cmd 'botright new'
    api.nvim_win_set_height(0, math.max(12, math.floor(vim.o.lines * 0.65)))
  else
    vim.cmd 'botright vnew'
    api.nvim_win_set_width(0, math.min(96, math.floor(vim.o.columns * 0.55)))
  end
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  state = {
    source = source,
    kernel = kernels[1],
    buf = buf,
    win = win,
    view = { name = name, path = {}, row = 0, col = 0 },
    history = {},
    selected_col = 1,
    entries = {},
    cells = {},
  }
  local s = state
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'molten-variables'
  api.nvim_buf_set_name(buf, 'molten://variables/' .. source)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].cursorline = true
  vim.wo[win].winbar = ''
  vim.wo[win].fillchars = 'eob: '
  vim.wo[win].list = false
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].winbar = '%#Comment#  r refresh   u back   ? help   q close%*'
  local function map(key, fn, desc) vim.keymap.set('n', key, fn, { buffer = buf, silent = true, desc = desc }) end
  map('q', M.close, 'Close inspector')
  map('<Esc>', M.close, 'Close inspector')
  map('r', M.refresh, 'Refresh')
  map('u', M.back, 'Parent view')
  map('<BS>', M.back, 'Parent view')
  map('<CR>', M.enter, 'Inspect')
  map('f', function()
    vim.ui.input(
      { prompt = s.view.name and 'Filter selected column (e.g. > 3 / contains text; blank clears): ' or 'Filter name/type: ', default = s.view.query },
      function(value)
        if value ~= nil and state == s then M.filter(value) end
      end
    )
  end, 'Filter')
  map('s', M.sort, 'Sort')
  map('H', function() M.view { hidden = not s.view.hidden, row = 0 } end, 'Include hidden variables')
  map('t', function()
    vim.ui.input({ prompt = 'Leading dimension indices (e.g. 0, 2): ', default = table.concat(s.view.slice or {}, ', ') }, function(value)
      if value ~= nil and state == s then M.slice(value) end
    end)
  end, 'Tensor slice')
  map('R', function()
    vim.ui.input({ prompt = 'Custom renderer (blank resets): ' }, function(value)
      if value ~= nil and state == s then M.view { renderer = value ~= '' and value or false, row = 0, col = 0, filter = false, sort_col = false } end
    end)
  end, 'Custom renderer')
  map('p', function()
    vim.ui.select({ 'line', 'histogram', 'heatmap' }, { prompt = 'Plot current page (line/histogram use selected column)' }, function(value)
      if value and state == s then M.plot(value) end
    end)
  end, 'Plot page')
  map('g', function()
    vim.ui.input({ prompt = 'Go to row, column (zero-based): ' }, function(value)
      if not value or state ~= s then return end
      local r, c = value:match '^(%d+)%s*,?%s*(%d*)$'
      if not r then return vim.notify('Enter row or row, column', vim.log.levels.WARN) end
      M.view { row = tonumber(r), col = tonumber(c) or 0 }
    end)
  end, 'Jump to position')
  local function page(dr, dc)
    local limit = s.data and (s.data.total or s.data.total_rows) or 1
    M.view { row = math.max(0, math.min((s.view.row or 0) + dr, math.max(0, limit - 1))), col = math.max(0, (s.view.col or 0) + dc) }
  end
  map(']p', function() page(s.view.name and 20 or 100, 0) end, 'Next page')
  map('[p', function() page(s.view.name and -20 or -100, 0) end, 'Previous page')
  map(']c', function() page(0, s.page_cols or 8) end, 'Next columns')
  map('[c', function() page(0, -(s.page_cols or 8)) end, 'Previous columns')
  for key, delta in pairs { h = -1, l = 1, ['<Tab>'] = 1, ['<S-Tab>'] = -1 } do
    map(key, function()
      local row = api.nvim_win_get_cursor(win)[1]
      local cells = s.cells[row]
      if cells then
        s.selected_col = math.max(1, math.min(#cells, s.selected_col + delta))
        choose_cell(s)
      end
    end, 'Select column')
  end
  map('y', function()
    local cell = choose_cell(s)
    local value = cell and cell.value or s.data and (s.data.note or s.data.summary)
    if value then
      vim.fn.setreg('"', value)
      pcall(vim.fn.setreg, '+', value)
      vim.notify 'Value copied'
    end
  end, 'Copy value')
  map(
    '?',
    function()
      popup('Inspector controls', {
        'NAVIGATE   j/k rows · h/l or Tab columns · Enter inspect/value text',
        '           u / Backspace parent · / search this page · q close',
        'VIEWS      f filter · s sort (asc/desc/reset) · H hidden names',
        '           [p/]p row pages · [c/]c column pages · g jump to row,column',
        'TENSORS    t leading indices · last two axes remain the table',
        'EXPLORE    p line/histogram/heatmap of this page · y copy selected value',
        'RENDERERS  R named Python renderer · blank restores standard view',
        'REFRESH    r refresh snapshot · no automatic value/GPU reads',
        '',
        'Filters and sorting change this view only. They do not modify your variable.',
        'GPU values are fetched only on explicit inspection. Plots use this page only.',
      })
    end,
    'Help'
  )
  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if state == s then
        state = nil
        if s.job then s.job:kill(15) end
      end
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = api.nvim_create_augroup('python-variables-resize', { clear = true }),
    callback = function()
      if state ~= s or not api.nvim_win_is_valid(s.win) then return end
      api.nvim_win_call(s.win, function()
        if vim.o.columns < 110 then
          vim.cmd 'wincmd J'
          api.nvim_win_set_height(s.win, math.max(12, math.floor(vim.o.lines * 0.65)))
        else
          vim.cmd 'wincmd L'
          api.nvim_win_set_width(s.win, math.min(96, math.floor(vim.o.columns * 0.55)))
        end
      end)
      fetch(s)
    end,
  })
  api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      if state == s and api.nvim_get_current_win() == win then
        local item = s.entries[api.nvim_win_get_cursor(win)[1]]
        if item then s.focus = item.name end
        choose_cell(s)
      end
    end,
  })
  local function poll_source()
    if state ~= s or not api.nvim_buf_is_valid(s.buf) or not api.nvim_buf_is_valid(s.source) then return end
    if api.nvim_get_current_buf() == s.buf then pcall(api.nvim_buf_call, s.source, function() vim.fn.MoltenTick(0) end) end
    vim.defer_fn(poll_source, 200)
  end
  vim.defer_fn(poll_source, 200)
  M.refresh()
end
return M
