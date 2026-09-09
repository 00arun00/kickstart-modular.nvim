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

-- Ask Molten to create the float without focusing it. Its open_and_enter
-- implementation passes None to nvim_set_current_win when the anchor is below
-- the viewport or there is no space beneath it.
function M.preview()
  if #vim.fn.MoltenRunningKernels(true) == 0 then return vim.notify('Run a cell or import saved outputs first', vim.log.levels.INFO) end
  local source = vim.api.nvim_get_current_win()
  local function open()
    local existing = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      existing[win] = true
    end
    vim.fn.MoltenUpdateOption('enter_output_behavior', 'open_then_enter')
    local ok, err = pcall(vim.cmd, 'noautocmd MoltenEnterOutput')
    -- Keep the safe behavior for raw commands too. Our enter helper focuses only
    -- after confirming that an output window actually exists.
    local win = vim.api.nvim_get_current_win()
    if win ~= source and vim.api.nvim_win_get_config(win).relative == 'win' then windows[source] = win end
    for _, candidate in ipairs(vim.api.nvim_list_wins()) do
      if not existing[candidate] and vim.api.nvim_win_get_config(candidate).relative == 'win' then windows[source] = candidate end
    end
    if vim.api.nvim_get_current_win() ~= source then vim.cmd('noautocmd call win_gotoid(' .. source .. ')') end
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
    local output = windows[source]
    return output and vim.api.nvim_win_is_valid(output) and output or nil
  end
  local win = windows[source]
  if win and vim.api.nvim_win_is_valid(win) then return win, source end
  win = open()
  if not win then
    -- First make room around the current execution region without moving the
    -- cursor. For a long percent cell, reveal its end if it is still off screen.
    vim.cmd 'normal! zz'
    vim.cmd.redraw()
    win = open()
  end
  if not win and vim.bo.filetype == 'python' then
    local row = vim.api.nvim_win_get_cursor(source)[1]
    for _, cell in ipairs(require('custom.python.notebook').cells()) do
      if row >= cell.marker and row <= cell.limit then
        vim.api.nvim_win_set_cursor(source, { cell[2], 0 })
        vim.cmd 'normal! zz'
        vim.cmd.redraw()
        win = open()
        break
      end
    end
  end
  if not win then
    vim.notify('No visible output window. Enlarge this split or move to an executed cell and retry.', vim.log.levels.INFO)
    return
  end
  return win, source
end

function M.enter()
  local win, source = M.preview()
  if not win then return end
  vim.cmd('noautocmd call win_gotoid(' .. win .. ')')
  -- Preview footers describe clipping; while focused, normal scrolling exposes
  -- the complete buffer and the footer is no longer useful.
  vim.api.nvim_win_set_config(win, { footer = '' })
  controls(win, source)
  return win, source
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
