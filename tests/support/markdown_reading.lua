-- An attached editor exercises real modes/controllers, with deterministic
-- image conversion and terminal transport (no external LaTeX tools needed).
local root, data, provided_source = ...
vim.opt.rtp:prepend(root)
for _, name in ipairs { 'snacks.nvim', 'render-markdown.nvim', 'lualine.nvim', 'catppuccin' } do
  vim.opt.rtp:append(data .. '/lazy/' .. name)
end
vim.opt.rtp:append(data .. '/site')
vim.g.mapleader = ' '
vim.g.have_nerd_font = true
local spec = require('custom.plugins.snacks')[1]
spec.config(nil, { image = { enabled = false, doc = spec.opts.image.doc } })
local terminal = Snacks.image.terminal
terminal.env = function() return { supported = true, placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local images, image_id, placement_id = {}, 100, 200
Snacks.image.image.new = function(src)
  if not images[src] then
    image_id = image_id + 1
    images[src] = {
      src = src,
      id = image_id,
      file = src,
      pending = hold_reading_images == true,
      info = { size = { width = 280, height = 80 }, dpi = { width = 96, height = 96 } },
      placements = {},
      ready = function(self) return not self.pending end,
      failed = function() return false end,
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
local source = type(provided_source) == 'table' and provided_source
  or {
    '# Reading fixture',
    '',
    'Normal prose.',
    '',
    '| Branch | Equation |',
    '| --- | --- |',
    '| **Mass Transport** | **Continuity**<br>$$a+b=c$$ |',
    '',
    '$$',
    'a/b=c',
    '$$',
    '',
    '```mermaid',
    'graph LR',
    'A --> B',
    '```',
    '',
    'Trailing prose.',
  }
vim.api.nvim_buf_set_lines(0, 0, -1, false, source)
vim.bo.filetype = 'markdown'
vim.bo.modified = false
require 'keymaps'
local renderer = require('custom.plugins.render-markdown')[1]
renderer.config(nil, vim.tbl_deep_extend('force', renderer.opts, { debounce = 0 }))
vim.cmd 'runtime plugin/render-markdown.lua'
require('custom.plugins.lualine')[1].config()
reading_fixture = {
  buf = vim.api.nvim_get_current_buf(),
  win = vim.api.nvim_get_current_win(),
  source = source,
  tick = vim.api.nvim_buf_get_changedtick(0),
  controller = Snacks.image.inline.new(vim.api.nvim_get_current_buf()),
  images = images,
}
function reading_fixture.table_rendered()
  local ns = require('render-markdown.core.ui').ns
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(reading_fixture.buf, ns, 0, -1, { details = true })) do
    if mark[4].conceal == '' and mark[4].virt_lines and mark[4].virt_lines_above then return true end
  end
  return false
end
function reading_fixture.image_hidden(kind)
  for _, img in pairs(reading_fixture.controller.imgs) do
    if img.opts.type == kind then return img.hidden == true end
  end
  return nil
end
function reading_fixture.status() return require('lualine').statusline(true) end
function reading_fixture.source_unchanged()
  return vim.deep_equal(vim.api.nvim_buf_get_lines(reading_fixture.buf, 0, -1, false), source)
    and vim.api.nvim_buf_get_changedtick(reading_fixture.buf) == reading_fixture.tick
    and not vim.bo[reading_fixture.buf].modified
end
require('render-markdown').render { buf = reading_fixture.buf }
