-- Run with: nvim --headless -n -u NONE -i NONE -l tests/markdown_math.lua
-- Uses real Snacks placement/extmarks, with terminal transport stubbed.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/snacks.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local cache = vim.fn.tempname()
require('snacks').setup { image = { enabled = false, cache = cache } }
local terminal = Snacks.image.terminal
terminal.env = function() return { placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local Placement = require 'snacks.image.placement'
local prepare = require('custom.markdown_math').prepare
vim.o.columns = 120
vim.wo.number = true
vim.wo.signcolumn = 'yes:2'
vim.bo.filetype = 'markdown'
local buf = vim.api.nvim_get_current_buf()
local next_id = 0

local function placement(lines, range, pixels)
  vim.api.nvim_buf_clear_namespace(buf, Placement.ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo.modified = false
  next_id = next_id + 1
  return setmetatable({
    id = next_id,
    buf = buf,
    eids = {},
    img = {
      id = 42,
      info = { size = pixels or { width = 200, height = 120 }, dpi = { width = 96, height = 96 } },
      ready = function() return true end,
      place = function() end,
    },
    opts = { type = 'math', inline = true, conceal = true, range = range, pos = { range[1], range[2] }, max_width = 80, on_update_pre = prepare },
  }, Placement)
end

local function verify_center(p, source)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  p:update()
  local width = math.huge
  for _, win in ipairs(p:wins()) do
    local info = vim.fn.getwininfo(win)[1]
    width = math.min(width, info.width - info.textoff)
  end
  local offset = math.max(0, math.floor((width - p._state.loc.width) / 2))
  assert(p._state.loc[2] == offset)
  assert(p._state.loc.width <= width, 'equation overflowed text area')
  local overlay, virtual = 0, 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, Placement.ns, 0, -1, { details = true })) do
    local details = mark[4]
    if details.virt_text then
      assert(details.virt_text_win_col == offset, 'overlay was not centered')
      overlay = overlay + 1
    end
    for _, line in ipairs(details.virt_lines or {}) do
      assert(line[1][1] == string.rep(' ', offset), 'virtual line was not centered')
      assert(line[2] and line[2][1] ~= '', 'image placeholders were lost')
      virtual = virtual + 1
    end
  end
  assert(overlay + virtual > 0, 'equation was not drawn')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source), 'Markdown source changed')
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo.modified, 'rendering modified buffer')
end

local source = { '$$', '\frac{a}{b} = c', '$$', '', 'prose' }
local p = placement(source, { 1, 0, 3, 2 })
-- Exercise the installed parser and configured hook, not just hand-built ranges.
local image_config = require('custom.plugins.snacks')[1].opts.image
local parsed
require('snacks.image.doc').find(buf, function(images) parsed = images end)
assert(vim.wait(5000, function() return parsed ~= nil end), 'math parsing timed out')
assert(#parsed == 1 and parsed[1].type == 'math', 'display equation was not recognized')
p.opts.range, p.opts.pos = parsed[1].range, parsed[1].pos
p.opts.on_update_pre = image_config.doc.on_update_pre
assert(image_config.doc.auto_resize, 'document placements must update on resize')
verify_center(p, source)
local before = p._state.loc[2]
vim.cmd 'vsplit'
local split = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(split, 35)
verify_center(p, source)
assert(p._state.loc[2] ~= before, 'split resize did not update centering')
vim.api.nvim_win_close(split, true)
verify_center(p, source)

-- Single-line display math and wrapped-source fallback retain their image.
source = { '$$a=b$$' }
p = placement(source, { 1, 0, 1, #source[1] }, { width = 200, height = 20 })
verify_center(p, source)
source = { '$$' .. string.rep('a+', 100) .. 'b$$' }
p = placement(source, { 1, 0, 1, #source[1] })
vim.wo.wrap = true
verify_center(p, source)

-- A very wide equation scales to fit a narrow text area without negative padding.
source = { '$$', 'a=b', '$$' }
p = placement(source, { 1, 0, 3, 2 }, { width = 4000, height = 200 })
verify_center(p, source)

-- Inline math retains the exact upstream state and rendering.
source = { 'before $x$ after' }
p = placement(source, { 1, 7, 1, 10 }, { width = 20, height = 20 })
local original_state = p:state()
p:update()
assert(vim.deep_equal(p._state, original_state), 'inline math placement changed')
local marks = vim.api.nvim_buf_get_extmarks(buf, Placement.ns, 0, -1, { details = true })
assert(marks[1][4].virt_text_pos == 'inline', 'inline math became a block')
assert(p.opts.max_width == 80 and not p._markdown_math.width)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))

-- Reusing a placement after editing display math to inline clears centering.
source = { '$$', 'x', '$$' }
p = placement(source, { 1, 0, 3, 2 })
verify_center(p, source)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '$x$' })
p.opts.range = { 1, 0, 1, 3 }
p:update()
assert(not p._markdown_math.width and p.opts.max_width == 80)
assert(p._state.loc[2] == 0)
vim.fn.delete(cache, 'rf')
print 'Markdown display math centering, resize, split, source preservation and inline isolation checks passed'
