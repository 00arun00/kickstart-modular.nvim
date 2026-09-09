local M = {}
local windows = {}

local function controls(win, source)
  local buf = vim.api.nvim_win_get_buf(win)
  vim.wo[win].foldenable = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].linebreak = true
  local function close()
    vim.api.nvim_win_close(0, true)
    if vim.api.nvim_win_is_valid(source) then vim.api.nvim_set_current_win(source) end
  end
  vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'Close output and return to code' })
  vim.keymap.set('n', '<leader>jh', close, { buffer = buf, desc = 'Close output and return to code' })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, desc = 'Close output and return to code' })
  vim.keymap.set('n', '<leader>jO', function() M.inspect(vim.api.nvim_get_current_win(), source) end, { buffer = buf, desc = 'Inspect full output in split' })
  vim.keymap.set('n', 'gw', function() vim.wo.wrap = not vim.wo.wrap end, { buffer = buf, desc = 'Toggle output wrapping' })
end

function M.enter()
  if #vim.fn.MoltenRunningKernels(true) == 0 then return vim.notify('Run a cell or import saved outputs first', vim.log.levels.INFO) end
  local source = vim.api.nvim_get_current_win()
  vim.cmd 'noautocmd MoltenEnterOutput'
  local win = vim.api.nvim_get_current_win()
  if win == source or vim.api.nvim_win_get_config(win).relative == '' then return end
  controls(win, source)
  windows[source] = win
  return win, source
end

-- MoltenShowOutput/HideOutput currently skip completed cells in their redraw
-- path. Use the public enter API to preview and close the owned window directly.
function M.preview()
  if #vim.fn.MoltenRunningKernels(true) == 0 then return vim.notify('Run a cell or import saved outputs first', vim.log.levels.INFO) end
  local source = vim.api.nvim_get_current_win()
  if windows[source] and vim.api.nvim_win_is_valid(windows[source]) then return end
  local existing = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    existing[win] = true
  end
  vim.fn.MoltenUpdateOption('enter_output_behavior', 'open_then_enter')
  local ok, err = pcall(vim.cmd, 'noautocmd MoltenEnterOutput')
  vim.fn.MoltenUpdateOption('enter_output_behavior', 'open_and_enter')
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not existing[win] and vim.api.nvim_win_get_config(win).relative == 'win' then windows[source] = win end
  end
  if vim.api.nvim_get_current_win() ~= source then vim.cmd('noautocmd call win_gotoid(' .. source .. ')') end
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

function M.hide()
  local source = vim.api.nvim_get_current_win()
  local win = windows[source]
  if win and vim.api.nvim_win_is_valid(win) then
    -- Leave the output buffer normally so Molten clears its window reference.
    -- Closing a non-current preview directly leaves a stale handle upstream.
    vim.cmd('noautocmd call win_gotoid(' .. win .. ')')
    vim.api.nvim_win_close(win, true)
    if vim.api.nvim_win_is_valid(source) then vim.api.nvim_set_current_win(source) end
  end
  windows[source] = nil
end

-- Copy the complete output buffer, not the truncated inline preview. A snapshot
-- stays available while switching cells and cannot accidentally edit notebook code.
function M.inspect(win, source)
  if not win then
    win, source = M.enter()
  end
  if not win then return end
  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  vim.api.nvim_win_close(win, true)
  if not vim.api.nvim_win_is_valid(source) then return end
  vim.api.nvim_set_current_win(source)
  vim.cmd 'botright 18new'
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = 'molten_output'
  vim.api.nvim_buf_set_name(buf, 'molten-output://snapshot/' .. buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.wo.wrap = false -- Preserve columns in tables; gw switches to wrapped prose.
  controls(vim.api.nvim_get_current_win(), source)
end

return M
