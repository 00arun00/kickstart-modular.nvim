-- Real parser/placement code; conversion metadata is deterministic.
vim.opt.rtp:prepend(vim.fn.getcwd())
for _, name in ipairs { 'snacks.nvim' } do
  vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/' .. name)
end
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local cache = vim.fn.tempname()
local spec = require('custom.plugins.snacks')[1]
spec.config(nil, { image = vim.tbl_deep_extend('force', spec.opts.image, { enabled = false, cache = cache }) })
local terminal = Snacks.image.terminal
terminal.env = function() return { supported = true, placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local buf = vim.api.nvim_get_current_buf()
vim.bo.filetype = 'markdown'
local source = {
  [[Density $\rho$; time $t$; vector $\mathbf{v}$; longer $\rho\to p_t(x)$; fraction $\frac{\partial\psi}{\partial t}$ after.]],
  [[$$\rho$$]],
  '',
  [[| Quantity $\rho$ | Equation |]],
  '| --- | --- |',
  [[| $t$ | $$\frac{a}{b}$$ |]],
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.bo.modified = false
local tick = vim.api.nvim_buf_get_changedtick(buf)
local doc = Snacks.image.doc
local function find()
  local found
  doc.find(buf, function(items) found = items end)
  assert(vim.wait(5000, function() return found ~= nil end))
  return found
end
local items, inline_count = find(), 0
local Placement = Snacks.image.placement
for id, item in ipairs(items) do
  local is_inline = item.range[1] == 1
  assert((item.src:match '%.inline%-math%.tex$' ~= nil) == is_inline, 'display/table conversion policy changed')
  local tex = table.concat(vim.fn.readfile(item.src), '\n')
  if is_inline then
    inline_count = inline_count + 1
    assert(tex:find([[\textstyle]], 1, true) and tex:find([[\vrule]], 1, true), 'missing inline style/shared canvas')
    assert(not tex:find([[\[]], 1, true), 'inline expression still uses display style')
  elseif item.range[1] == 2 then
    assert(tex:find([=[\[\rho\]]=], 1, true), 'display TeX changed')
  end
  -- At 192 DPI the shared 16.2pt canvas is approximately 43px high.
  local columns = id + 1
  local p = setmetatable({
    id = id,
    buf = buf,
    eids = {},
    img = {
      id = 42,
      src = item.src,
      info = { size = { width = columns * 43 / 2, height = 43 }, dpi = { width = 192, height = 192 } },
      ready = function() return true end,
      place = function() end,
      del = function() end,
    },
    opts = {
      type = 'math',
      inline = true,
      conceal = true,
      pos = item.pos,
      range = item.range,
      max_width = 80,
      on_update_pre = require('custom.markdown_math').prepare,
    },
  }, Placement)
  p:update()
  if is_inline then
    assert(p._state.loc.height == 1 and p._state.loc.width == columns, 'inline scale depends on individual expression fit')
    local mark = vim.api.nvim_buf_get_extmarks(buf, Placement.ns, 0, -1, { details = true })[#p.eids]
    assert(mark and mark[4].virt_text_pos == 'inline' and not mark[4].virt_lines, 'inline expression became a block')
    -- A terminal font/cell-size change keeps one-row placement and adjusts the
    -- required columns, rather than using Snacks' per-crop inline heuristic.
    terminal.size = function() return { cell_width = 10, cell_height = 30, scale = 1 } end
    p:update()
    assert(p._state.loc.height == 1 and p._state.loc.width == math.floor(columns * 1.5 + 0.5))
    terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
    -- Unusually tall/wide formulas retain the existing overflow policy rather
    -- than being forced into the compact canvas or losing content.
    p.img.info.size.height = 160
    assert(vim.deep_equal(p:state(), Placement.state(p)), 'tall expression was forced into one row')
    p.img.info.size = { width = 90 * 43 / 2, height = 43 }
    assert(vim.deep_equal(p:state(), Placement.state(p)), 'wide expression lost the existing overflow fallback')
  end
  p:del()
end
assert(inline_count == 5)
assert(vim.deep_equal(source, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo.modified)
-- Other filetypes retain Snacks' converter, even for single-dollar syntax.
vim.bo.filetype = 'tex'
local item = { content = [[$\rho$]], ext = 'math.tex', range = { 1, 0, 1, 6 } }
doc.transforms.latex(item, { buf = buf })
assert(item.ext == 'math.tex' and item.content:find([=[\[\rho\]]=], 1, true))
vim.fn.delete(cache, 'rf')
print 'Inline math: text style, common canvas, one-row placements, longer widths, cell-size changes, display/table isolation and source preservation passed'
