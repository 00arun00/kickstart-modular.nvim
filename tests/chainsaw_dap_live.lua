-- Real debugpy session; requires the existing Neovim Python host environment.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-dap')
local dap = require 'dap'
local panel = require 'custom.chainsaw-dap'
panel.setup(dap)
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local file = dir .. '/training.py'
vim.fn.writefile({ 'def training_step():', '    loss = 0.1842', '    result = loss * 2', '    return result', 'training_step()' }, file)
vim.cmd.edit(file)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
dap.set_breakpoint()
dap.adapters.python = { type = 'executable', command = vim.fn.stdpath 'data' .. '/python/bin/python', args = { '-m', 'debugpy.adapter' } }
dap.run { type = 'python', request = 'launch', name = 'panel integration', program = file, console = 'internalConsole', cwd = dir, justMyCode = true }
local stopped = vim.wait(20000, function()
  local state = panel.state()
  return state.window and vim.api.nvim_win_is_valid(state.window)
end, 20)
if not stopped then
  dap.terminate()
  error 'debugpy did not produce a pause panel within 20 seconds'
end
local text = table.concat(vim.api.nvim_buf_get_lines(panel.state().buffer, 0, -1, false), '\n')
assert(text:find('training.py:3', 1, true) and text:find('training_step', 1, true) and text:find('→ 3  ', 1, true), text)
assert(text:find('result = loss * 2', 1, true), text)
dap.continue()
assert(vim.wait(10000, function() return dap.session() == nil end, 20), 'debugpy did not exit')
local state = panel.state()
assert(not state.window or not vim.api.nvim_win_is_valid(state.window), 'Stale pause panel after exit')
vim.fn.delete(dir, 'rf')
print 'PASS: real Python debugger breakpoint, actual frame/source, continue, and panel dismissal'
