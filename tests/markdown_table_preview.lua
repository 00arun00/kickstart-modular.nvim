-- Preview command behavior with the real parser and controlled image transport.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/snacks.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local cache = vim.fn.tempname()
require('snacks').setup { image = { enabled = false, cache = cache } }
local terminal = Snacks.image.terminal
terminal.env = function() return { supported = true, placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local transport = assert(loadfile(vim.fn.getcwd() .. '/tests/support/markdown_document.lua'))().transport()
vim.o.columns = 160
local source = {
  '# Transport',
  '',
  '| Branch | Quantity | Governing equation |',
  '| --- | --- | --- |',
  '| **Mass Transport** | Density $\\rho$ | **Continuity**<br>$$a=b$$ |',
  '| **Momentum Transport** | Momentum $p$ | **Navier–Stokes**<br>$$p=f$$ |',
  '',
  'Source prose stays here.',
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
vim.bo.filetype = 'markdown'
vim.bo.modified = false
local buf = vim.api.nvim_get_current_buf()
local tick = vim.api.nvim_buf_get_changedtick(buf)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
require('custom.plugins.render-markdown')[1].init()
vim.cmd 'MarkdownMathTable'
assert(vim.wait(5000, function() return vim.api.nvim_get_current_buf() ~= buf end), 'preview did not open')
local target, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()

local function check(width)
  local lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  local text = table.concat(lines, '\n')
  for _, word in ipairs { 'Mass', 'Momentum', 'Continuity', 'Navier' } do
    assert(text:find(word, 1, true), 'native label was lost: ' .. word)
  end
  assert(not text:find('<br>', 1, true) and not text:find('$', 1, true), 'source markup leaked into the preview')
  local row_width = vim.fn.strdisplaywidth(lines[1])
  assert(row_width > 0 and row_width <= width, 'preview overflowed the window')
  for _, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == row_width, 'table borders are misaligned')
  end
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo[buf].modified, 'source note was modified')
end

check(vim.api.nvim_win_get_width(win))
vim.cmd 'vsplit'
local other = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(other, buf)
vim.api.nvim_win_set_width(win, 72)
vim.api.nvim_exec_autocmds('WinResized', {})
assert(
  vim.wait(5000, function()
    local first = vim.api.nvim_buf_get_lines(target, 0, 1, false)[1]
    return vim.fn.strdisplaywidth(first) <= vim.api.nvim_win_get_width(win)
  end),
  'preview did not reflow after resizing'
)
check(vim.api.nvim_win_get_width(win))
vim.api.nvim_win_close(other, true)
vim.api.nvim_win_close(win, true)
assert(not vim.api.nvim_buf_is_valid(target), 'preview buffer was not cleaned up')
for _, img in pairs(transport.images) do
  assert(vim.tbl_isempty(img.placements), 'image placement leaked after closing preview')
end
assert(vim.api.nvim_get_current_buf() == buf and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
vim.fn.delete(cache, 'rf')
print 'Table preview: open, native labels, resize, source preservation and cleanup passed'
