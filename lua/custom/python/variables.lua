local M = {}
local api = vim.api
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))))
local state

local function lines(s, content)
  if not api.nvim_buf_is_valid(s.buf) then return end
  content = vim.tbl_map(function(line) return line:gsub('[\r\n]', ' ') end, content)
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, content)
  vim.bo[s.buf].modifiable = false
end

local function connection(source, kernel)
  if not api.nvim_buf_is_valid(source) then return nil, 'Notebook buffer closed' end
  local attached = api.nvim_buf_call(source, function() return vim.fn.MoltenRunningKernels(true) end)
  if not vim.tbl_contains(attached, kernel) then return nil, 'Kernel stopped; reopen from the notebook' end
  local path = require('custom.python.notebook').connections[kernel]
  if not path then return nil, 'Start this kernel with Space j i (restart older sessions first)' end
  local ok, value = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  if not ok or not value.generation then return nil, 'Kernel starting or unavailable; refresh when ready' end
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

local function render(s, data)
  local source_name = api.nvim_buf_is_valid(s.source) and vim.fs.basename(api.nvim_buf_get_name(s.source)) or 'closed notebook'
  local content = { '  VARIABLES · ' .. source_name, '  ' .. s.kernel }
  s.entries = {}
  if data.error then
    vim.list_extend(content, { '', '  ' .. data.error, '', '  r refresh · u list · q close' })
  elseif data.entries then
    vim.list_extend(content, { '  Snapshot ' .. os.date '%H:%M:%S' .. ' · r refresh · Enter inspect · q close', '' })
    for _, item in ipairs(data.entries) do
      table.insert(content, '  ' .. item.name .. '  ·  ' .. metadata(item))
      s.entries[#content] = item.name
      if item.summary and item.summary ~= '' then
        table.insert(content, '    ' .. item.summary)
        s.entries[#content] = item.name
      end
    end
    if #data.entries == 0 then table.insert(content, '  No user variables. Run a code cell, then refresh.') end
    if data.more then table.insert(content, '  First 200 variables shown; use :MoltenInspect NAME for another variable.') end
  else
    vim.list_extend(content, { '  ' .. data.name, '  ' .. metadata(data), '  u list · r refresh · [p/]p rows · [c/]c columns · q close', '' })
    if data.note then table.insert(content, '  ' .. data.note) end
    if data.rows then
      s.row, s.col = data.row, data.col
      s.total_rows, s.total_cols = data.total_rows, data.total_cols
      table.insert(
        content,
        string.format('  Rows %d–%d / %d · column offset %d / %d', math.min(s.row + 1, s.total_rows), s.row + #data.rows, s.total_rows, s.col, s.total_cols)
      )
      local table_rows, widths = {}, {}
      if data.columns then table.insert(table_rows, vim.list_extend({ 'index' }, vim.deepcopy(data.columns))) end
      for i, row in ipairs(data.rows) do
        table.insert(table_rows, vim.list_extend({ data.index and data.index[i] or tostring(s.row + i - 1) }, vim.deepcopy(row)))
      end
      for _, row in ipairs(table_rows) do
        for i, value in ipairs(row) do
          row[i] = vim.fn.strcharpart(value, 0, 24)
          widths[i] = math.max(widths[i] or 0, vim.fn.strdisplaywidth(row[i]))
        end
      end
      for _, row in ipairs(table_rows) do
        for i, value in ipairs(row) do
          row[i] = value .. string.rep(' ', widths[i] - vim.fn.strdisplaywidth(value))
        end
        table.insert(content, '  ' .. table.concat(row, ' │ '))
      end
    end
  end
  lines(s, content)
  local ns = api.nvim_create_namespace 'python-variables'
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  api.nvim_buf_set_extmark(s.buf, ns, 0, 0, { end_row = 1, hl_group = 'Title' })
  api.nvim_buf_set_extmark(s.buf, ns, 1, 0, { end_row = 2, hl_group = 'Comment' })
  vim.b[s.buf].variable_snapshot = data -- Also useful to inspect/test the structured result.
end

function M.refresh()
  local s = state
  if not s or not api.nvim_buf_is_valid(s.buf) then return end
  if s.job then return vim.notify('Variable inspection pending; it will time out if the kernel is busy', vim.log.levels.INFO) end
  local conn, err = connection(s.source, s.kernel)
  if not conn then return render(s, { error = err }) end
  local request = { row = s.row, col = s.col }
  if s.name then request.name = s.name end
  lines(s, { '  VARIABLES · inspecting…', '  ' .. s.kernel, '', '  Waiting for kernel · q close' })
  vim.b[s.buf].variable_snapshot = nil
  local serial = (s.serial or 0) + 1
  s.serial = serial
  s.job = vim.system(
    { require('custom.python.host').executable 'python', root .. '/scripts/inspect-kernel.py', conn.path, conn.generation, vim.json.encode(request) },
    {
      text = true,
      timeout = 6500,
    },
    vim.schedule_wrap(function(result)
      if state ~= s or s.serial ~= serial or not api.nvim_buf_is_valid(s.buf) then return end
      s.job = nil
      local current, reason = connection(s.source, s.kernel)
      if not current or current.generation ~= conn.generation then return render(s, { error = reason or 'Kernel restarted; refresh for new values' }) end
      local ok, reply = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok then return render(s, { error = 'Inspection timed out or failed; refresh when the kernel is idle' }) end
      render(s, reply.ok and reply.data or { error = reply.error })
    end)
  )
end

function M.close()
  local s = state
  state = nil
  if not s then return end
  if s.job then s.job:kill(15) end
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
end

function M.open(name)
  local source = api.nvim_get_current_buf()
  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then return vim.notify('Attach exactly one kernel with Space j i first', vim.log.levels.WARN) end
  local conn, err = connection(source, kernels[1])
  if not conn then return vim.notify(err, vim.log.levels.WARN) end
  M.close()
  vim.cmd 'botright vnew'
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  api.nvim_win_set_width(win, math.min(78, math.max(40, math.floor(vim.o.columns * 0.45))))
  state = { source = source, kernel = kernels[1], buf = buf, win = win, name = name, row = 0, col = 0 }
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
  local s = state
  local function map(key, callback, desc) vim.keymap.set('n', key, callback, { buffer = buf, silent = true, desc = desc }) end
  map('q', M.close, 'Close variables')
  map('<Esc>', M.close, 'Close variables')
  map('r', M.refresh, 'Refresh variables')
  map('u', function()
    if s.job then return end
    s.name, s.row, s.col = nil, 0, 0
    M.refresh()
  end, 'Variable list')
  map('<CR>', function()
    if s.job then return end
    local selected = s.entries[api.nvim_win_get_cursor(win)[1]]
    if selected then
      s.name, s.row, s.col = selected, 0, 0
      M.refresh()
    end
  end, 'Inspect variable (may copy a small GPU sample)')
  local function page(dr, dc)
    if not s.name or s.job then return end
    s.row = math.max(0, math.min(s.row + dr, math.max(0, (s.total_rows or 1) - 1)))
    s.col = math.max(0, math.min(s.col + dc, math.max(0, (s.total_cols or 1) - 1)))
    M.refresh()
  end
  map(']p', function() page(20, 0) end, 'Next rows')
  map('[p', function() page(-20, 0) end, 'Previous rows')
  map(']c', function() page(0, 8) end, 'Next columns')
  map('[c', function() page(0, -8) end, 'Previous columns')
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
  -- Molten normally polls only the current buffer. Keep the visible source's
  -- output moving while focus is in our scratch pane, using its existing tick.
  local function poll_source()
    if state ~= s or not api.nvim_buf_is_valid(s.buf) or not api.nvim_buf_is_valid(s.source) then return end
    if api.nvim_get_current_buf() == s.buf then pcall(api.nvim_buf_call, s.source, function() vim.fn.MoltenTick(0) end) end
    vim.defer_fn(poll_source, 200)
  end
  vim.defer_fn(poll_source, 200)
  M.refresh()
end

return M
