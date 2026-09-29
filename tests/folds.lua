-- Run with: nvim --headless -n -u NONE -i NONE -l tests/folds.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.swapfile = false
local folds = require 'custom.navigation.folds'
local lines = {
  'def outer(flag):',
  '    total = 0',
  '    if flag:',
  '        total += 1',
  '        total += 2',
  '        total += 3',
  '        total += 4',
  '        total += 5',
  '        total += 6',
  '    total *= 2',
  '    print(total)',
  '    return total',
  '',
  'def other():',
  '    value = 1',
  '    value += 2',
  '    return value',
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.bo.filetype = 'python'
vim.wo.foldmethod = 'manual'
vim.cmd '3,9fold'
vim.cmd '1,12fold'
vim.cmd '14,17fold'
vim.cmd 'normal! zR'

-- Focus keeps the exact cursor while hiding unrelated code.
vim.api.nvim_win_set_cursor(0, { 5, 8 })
folds.focus()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 5, 8 }))
assert(vim.fn.foldclosed(5) == -1)
assert(vim.fn.foldclosed(14) == 14)

-- Preview copies the whole region without opening or editing the source fold.
vim.cmd 'normal! zM'
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local source, editor = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
folds.preview()
local popup = vim.b[source].lsp_floating_preview
assert(popup and vim.api.nvim_win_is_valid(popup))
local scratch = vim.api.nvim_win_get_buf(popup)
assert(not vim.bo[scratch].modifiable and not vim.wo[popup].foldenable)
assert(vim.api.nvim_buf_line_count(scratch) == 12)
assert(vim.api.nvim_get_current_win() == editor and vim.fn.foldclosed(1) == 1)
folds.preview()
assert(vim.api.nvim_get_current_win() == popup)
vim.cmd 'bdelete'
assert(vim.api.nvim_get_current_win() == editor)
assert(vim.fn.foldclosed(1) == 1)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), lines))

-- Suffix spacing remains safe when there is no room for the summary.
assert(folds.padding(editor, 1, 10000) == 2)

-- Focus is harmless on plain text and does not enable folds in output panes.
vim.cmd 'enew!'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'plain text' })
folds.focus()
assert(vim.api.nvim_get_current_line() == 'plain text')
vim.bo.buftype = 'nofile'
vim.wo.foldenable = false
folds.focus()
assert(not vim.wo.foldenable)
print 'Fold focus and preview checks passed'
