-- Cell frames are decorations only: no extra lines enter notebook source.
local M = {}
local ns = vim.api.nvim_create_namespace 'python-cell-frames'
local states = {}

local function highlights()
  for name, target in pairs { Code = 'DiagnosticInfo', Markdown = 'Special', Raw = 'DiagnosticWarn', Quiet = 'Comment', Active = 'Title' } do
    vim.api.nvim_set_hl(0, 'PythonCell' .. name, { link = target, default = false })
  end
end

function M.scan(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'python')
  local tree = ok and parser:parse()[1]
  local cells = {}
  for i, line in ipairs(lines) do
    local marker = line == '# %%' or line:match '^# %%%% '
    if marker and tree then marker = tree:root():named_descendant_for_range(i - 1, 0, i - 1, #line):type() == 'comment' end
    if marker then
      if #cells > 0 then cells[#cells].last = i - 2 end
      local kind = line:find('[markdown]', 1, true) and 'Markdown' or line:find('[raw]', 1, true) and 'Raw' or 'Code'
      table.insert(cells, { first = i - 1, last = #lines - 1, kind = kind })
    end
  end
  return cells
end

function M.update(buf, force)
  buf = buf or vim.api.nvim_get_current_buf()
  local state = states[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  if win == -1 then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if tick ~= state.tick then
    state.cells, state.tick = M.scan(buf), tick
  end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local width = math.max(4, math.min(100, vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff - 1))
  local active = 0
  for i, cell in ipairs(state.cells) do
    if row >= cell.first and row <= cell.last then active = i end
  end
  local marker_cursor = active > 0 and row == state.cells[active].first
  local key = table.concat({ tick, width, active, tostring(marker_cursor) }, ':')
  if key == state.key and not force then return end
  state.key = key
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local hidden = {}
  for _, other in pairs(vim.api.nvim_get_namespaces()) do
    if other ~= ns then
      for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(buf, other, 0, -1, { details = true })) do
        local detail = extmark[4]
        if detail.conceal_lines ~= nil then
          for r = extmark[2], detail.end_row or extmark[2] do
            hidden[r] = true
          end
        end
      end
    end
  end
  for i, cell in ipairs(state.cells) do
    local selected = i == active
    local label = (' %02d %s%s '):format(i, cell.kind:upper(), selected and ' · ACTIVE' or '')
    if width < 26 then label = (' %02d %s%s '):format(i, cell.kind:sub(1, 1), selected and '*' or '') end
    label = vim.fn.strcharpart(label, 0, math.max(0, width - 3))
    local hl = 'PythonCell' .. cell.kind
    local border = selected and 'PythonCellActive' or 'PythonCellQuiet'
    local line = { { '╭─', border }, { label, hl }, { string.rep('─', math.max(0, width - vim.fn.strdisplaywidth(label) - 3)) .. '╮', border } }
    if selected and marker_cursor then
      -- The source marker remains editable when the cursor is on that line.
      vim.api.nvim_buf_set_extmark(buf, ns, cell.first, 0, { virt_lines = { line }, virt_lines_above = true, priority = 300 })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, cell.first, 0, { virt_text = line, virt_text_pos = 'overlay', hl_eol = true, hl_group = 'Normal', priority = 300 })
    end
    -- A quiet end rule separates source from the next cell even when a long
    -- Markdown paragraph makes the start disappear above the viewport.
    local ending = { { '╰' .. string.rep('─', width - 2) .. '╯', border } }
    local last = cell.last
    while hidden[last] and last > cell.first do
      last = last - 1
    end
    vim.api.nvim_buf_set_extmark(buf, ns, last, 0, { virt_lines = { ending }, priority = 10 })
  end
end

function M.attach(buf)
  if states[buf] or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= 'python' or vim.bo[buf].buftype ~= '' then return end
  states[buf] = { cells = {} }
  local group = vim.api.nvim_create_augroup('python-cell-frames-' .. buf, { clear = true })
  local pending = false
  local function update()
    if pending then return end
    pending = true
    vim.defer_fn(function()
      pending = false
      if states[buf] then M.update(buf) end
    end, 60)
  end
  vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'BufWinEnter', 'WinEnter', 'InsertLeave' },
    { group = group, buffer = buf, callback = update }
  )
  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, { group = group, callback = update })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      states[buf] = nil
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
  update()
end

function M.setup()
  highlights()
  local group = vim.api.nvim_create_augroup('python-cell-frames', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
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
