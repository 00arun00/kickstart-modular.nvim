-- Real parser/placement integration; image conversion and terminal I/O are
-- deterministic stand-ins so this test needs no external TeX installation.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/snacks.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local cache = vim.fn.tempname()
require('snacks').setup { image = { enabled = false, cache = cache } }
local terminal = Snacks.image.terminal
terminal.env = function() return { supported = true, placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local images, next_id = {}, 100
local placement_id = 200
Snacks.image.image.new = function(src)
  if not images[src] then
    next_id = next_id + 1
    images[src] = {
      id = next_id,
      file = src,
      info = { size = { width = 280, height = 80 }, dpi = { width = 96, height = 96 } },
      placements = {},
      ready = function() return true end,
      place = function(self, p)
        if not p.id then
          placement_id = placement_id + 1
          p.id = placement_id
        end
        self.placements[p.id] = p
      end,
      del = function(self, id) self.placements[id] = nil end,
    }
  end
  return images[src]
end
vim.o.columns = 160
local source = {
  '# Transport',
  '',
  '| Branch | Quantity $\\psi$ | Governing equation |',
  '| --- | --- | --- |',
  '| **Mass Transport** | Density $\\rho$ | **Continuity**<br>$$\\frac{\\partial\\rho}{\\partial t}=0$$ |',
  '| **Momentum Transport** | Momentum $\\rho\\mathbf{v}$ | **Navier–Stokes**<br>$$\\rho\\mathbf{v}=\\mathbf{f}$$ |',
  '| **Energy Transport** | Energy $\\rho e$ | **Energy equation**<br>$$e=q+s$$ |',
  '',
  'Source prose stays here.',
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
vim.bo.filetype = 'markdown'
vim.bo.modified = false
local buf = vim.api.nvim_get_current_buf()
local tick = vim.api.nvim_buf_get_changedtick(buf)
local preview = require 'custom.markdown.table_preview'
assert(not preview.table_at(buf, 0), 'prose was mistaken for a table')
vim.api.nvim_win_set_cursor(0, { 5, 0 })
require('custom.plugins.render-markdown')[1].init()
vim.cmd 'MarkdownMathTable'
assert(vim.wait(5000, function() return vim.api.nvim_get_current_buf() ~= buf end), 'preview did not open')
local target = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()
local ns = Snacks.image.placement.ns
local function grids()
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(target, ns, 0, -1, { details = true })) do
    if mark[4].virt_text then result[#result + 1] = mark end
  end
  return result
end
assert(vim.wait(5000, function() return #grids() >= 16 end), 'equation grids were not drawn')
assert(vim.tbl_count(images) == 7, 'header/inline/display equation was lost')
local function check(width)
  local lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  local text = table.concat(lines, '\n')
  assert(text:find('Mass Transport', 1, true) and text:find('Continuity', 1, true), 'native labels were lost')
  assert(not text:find('<br>', 1, true) and not text:find('$', 1, true), 'source markup leaked into the preview')
  for _, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == width, 'table borders are misaligned')
  end
  local image_ids = {}
  for _, mark in ipairs(grids()) do
    local row, d = mark[2] + 1, mark[4]
    assert(not d.conceal and not d.virt_lines, 'cell image changed row geometry')
    assert((d.virt_text_pos == 'overlay' or d.virt_text_pos == 'win_col') and d.virt_text_win_col > 0)
    local image_width = 0
    for _, chunk in ipairs(d.virt_text) do
      image_width = image_width + vim.fn.strdisplaywidth(chunk[1])
      image_ids[chunk[2]] = true
    end
    local under = vim.fn.strcharpart(lines[row], d.virt_text_win_col, image_width)
    assert(under:match '^ +$', 'equation overlapped native text or a border')
  end
  assert(vim.tbl_count(image_ids) == 7, 'missing per-cell equation placement')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo[buf].modified, 'source note was modified')
  return #lines
end
local initial = check(vim.api.nvim_win_get_width(win))
vim.cmd 'vsplit'
local other = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(other, buf)
vim.api.nvim_win_set_width(win, 72)
vim.api.nvim_exec_autocmds('WinResized', {})
assert(
  vim.wait(
    5000,
    function() return vim.fn.strdisplaywidth(vim.api.nvim_buf_get_lines(target, 0, 1, false)[1]) == vim.api.nvim_win_get_width(win) and #grids() >= 16 end
  ),
  'preview did not reflow after resizing'
)
assert(check(vim.api.nvim_win_get_width(win)) >= initial, 'narrow layout did not wrap')
vim.api.nvim_win_close(other, true)
vim.api.nvim_win_close(win, true)
assert(not vim.api.nvim_buf_is_valid(target), 'preview buffer was not cleaned up')
for _, img in pairs(images) do
  assert(vim.tbl_isempty(img.placements), 'image placement leaked after closing preview')
end
assert(vim.api.nvim_get_current_buf() == buf and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
vim.fn.delete(cache, 'rf')
print 'Cell-by-cell table preview: native text, seven math images, borders, resize, source preservation and cleanup passed'
