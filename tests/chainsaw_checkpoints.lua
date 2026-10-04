-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_checkpoints.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
vim.cmd.runtime 'plugin/ex-commands.lua'
local chainsaw = require 'chainsaw'
local marker = require('custom.chainsaw').marker
local function reset(ft, lines)
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or { 'value = 1' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end
local function expect(label, action)
  (action or chainsaw.emojiLog)()
  local line = vim.api.nvim_get_current_line()
  assert(line:find(marker .. ' checkpoint │ ' .. label .. '"', 1, true), line)
end
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  reset(ft)
  for index = 1, 26 do
    expect(string.char(64 + index))
  end
  expect 'AA'
  expect 'AB'
end
-- Read persisted labels, including descriptions and the Z -> AA carry.
reset('python', { 'print("' .. marker .. ' checkpoint │ Z · loaded from disk")' })
expect 'AA'
reset('python', { 'print("' .. marker .. ' checkpoint │ AZ")' })
expect 'BA'
reset('python', { 'print("' .. marker .. ' checkpoint │ ZZ")' })
expect 'AAA'
-- A different marker and ordinary notes cannot advance this buffer's sequence.
reset('python', { 'print("[debug] checkpoint │ ZZ")', 'print("' .. marker .. ' note │ checkpoint │ ZZ")' })
expect 'A'
-- Inserting between existing sites uses the highest label, not the nearest one.
reset('python', { 'print("' .. marker .. ' checkpoint │ A")', 'print("' .. marker .. ' checkpoint │ C")' })
expect 'D'
-- Selection cleanup retains the sequence while higher checkpoints survive.
reset 'python'
expect 'A'
expect 'B'
expect 'C'
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd.normal { 'V', bang = true }
chainsaw.removeLogs()
expect 'D'
chainsaw.removeLogs()
expect 'A'
-- Exercise the actual key callback, dot-repeat, and Ex command.
reset 'python'
local key
for _, entry in ipairs(spec.keys) do
  if entry[1] == '<leader>le' then key = entry[2] end
end
assert(key)
expect('A', key)
expect('B', function() vim.cmd.normal { '.', bang = true } end)
-- Force a new undo block so this check specifically exercises undoing C.
vim.cmd 'let &undolevels = &undolevels'
expect('C', function() vim.cmd 'Chainsaw emojiLog' end)
vim.cmd.undo()
local before = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(before:find('checkpoint │ B', 1, true) and not before:find('checkpoint │ C', 1, true), before)
expect 'C'
print 'PASS: sequential checkpoints in four languages, rollover, reopening, cleanup, keymap, Ex command, and dot-repeat'
