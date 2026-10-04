-- Run with: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_cleanup.lua
-- Requires Chainsaw, the Python parser, Python 3, and Ruff (PATH or Mason).
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
require('custom.chainsaw').rich = false -- Phase 1 / native baseline
local chainsaw = require 'chainsaw'
local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function reset(text, filetype)
  vim.cmd.normal { '\27', bang = true }
  vim.cmd.enew { bang = true }
  vim.bo.filetype = filetype or 'python'
  vim.bo.undolevels = -1
  vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
  vim.bo.undolevels = 1000
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end
local function execute()
  local result = vim.system({ 'python3', '-c', table.concat(lines(), '\n') }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
local ruff = vim.fn.exepath 'ruff'
if ruff == '' then ruff = vim.fn.stdpath 'data' .. '/mason/bin/ruff' end
local original = { 'train_episodes_subset = {"items": list(range(30))}' }
reset(original)
chainsaw.objectLog()
local formatted = vim
  .system({ ruff, 'format', '--stdin-filename', 'demo.py', '-' }, {
    stdin = table.concat(lines(), '\n'),
    text = true,
  })
  :wait()
assert(formatted.code == 0, formatted.stderr)
local formatted_lines = vim.split(formatted.stdout:gsub('\n$', ''), '\n')
assert(#formatted_lines > 2, 'Fixture must exercise a wrapped statement')
reset(formatted_lines)
execute()
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), original), vim.inspect(lines()))
execute()
vim.cmd.undo()
assert(vim.deep_equal(lines(), formatted_lines), 'Undo must restore the complete statement')

-- Remove multiple statements, including trailing comments, in a single undo.
local multiple = { 'value = 1', 'print(', '    "⟦nvim:dbg⟧ value",', '    value,', ')', 'assert value == 1  # ⟦nvim:dbg⟧', 'print("untouched")' }
reset(multiple)
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), { 'value = 1', 'print("untouched")' }))
vim.cmd.undo()
assert(vim.deep_equal(lines(), multiple), 'All deletions must undo together')

-- Selecting only a marker inside a wrapped statement must leave it untouched.
reset(multiple)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd.normal { 'V', bang = true }
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), multiple))
-- A reverse linewise selection of the whole statement removes only that log.
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.cmd.normal { 'V3k', bang = true }
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), { 'value = 1', 'assert value == 1  # ⟦nvim:dbg⟧', 'print("untouched")' }))

-- Reject blockwise selection without crashing, editing, or changing timer state.
reset { 'value = 1', 'print("⟦nvim:dbg⟧ value")' }
vim.b.timeLogStart = false
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd.normal { '\22l', bang = true }
local before = lines()
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), before) and vim.b.timeLogStart == false)
vim.cmd.normal { '\27', bang = true }

-- The cleanup shortcut and public API both use the fixed handler.
reset { 'import time', 'value = 1' }
vim.api.nvim_win_set_cursor(0, { 2, 0 })
chainsaw.timeLog()
for _, key in ipairs(spec.keys) do
  if key[1] == '<leader>lx' then key[2]() end
end
assert(vim.b.timeLogStart == nil)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
chainsaw.timeLog()
assert(lines()[3]:find('= __import__("time").perf_counter()', 1, true), 'Timer should restart, not stop')
chainsaw.timeLog()
execute()

-- Partial deletion must not reuse an index still used by retained timer logs.
reset { 'import time', 'value = 1' }
vim.api.nvim_win_set_cursor(0, { 2, 0 })
chainsaw.timeLog()
chainsaw.timeLog()
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd.normal { 'V', bang = true }
chainsaw.removeLogs()
chainsaw.timeLog()
assert(lines()[4]:find('nvim_dbg_start_3', 1, true), vim.inspect(lines()))

-- Do not remove neighboring code or treat a marker comment as a whole function.
local shared =
  { 'value = 1; print("⟦nvim:dbg⟧ value")', '# ⟦nvim:dbg⟧ explanatory comment', 'def example():', '    return 1  # ⟦nvim:dbg⟧ explanation' }
reset(shared)
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), shared))

-- Preserve the existing line-based behavior in other languages.
reset({ 'local value = 1', 'print("⟦nvim:dbg⟧ value")' }, 'lua')
chainsaw.removeLogs()
assert(vim.deep_equal(lines(), { 'local value = 1' }))
print 'PASS: formatted cleanup, undo, selections, blockwise guard, timer restart, and non-Python cleanup'
