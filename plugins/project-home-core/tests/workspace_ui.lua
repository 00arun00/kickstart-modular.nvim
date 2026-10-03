-- nvim --headless -u NONE -i NONE -l plugins/project-home-core/tests/workspace_ui.lua
local repo = vim.fn.getcwd()
for _, plugin in ipairs { 'core', 'navigator' } do
  vim.opt.rtp:append(repo .. '/plugins/project-home-' .. plugin)
end
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, 'p')
vim.cmd('cd ' .. vim.fn.fnameescape(temp))
local core, ui = require 'project_home', require 'project_home.ui'
require('project_home.state').configure { directory = temp .. '/state' }
core.register('fixture', function() return { lines = { 'ready' }, items = {} } end)
require('project_home_navigator').setup()
core.setup { startup = false, remember_layout = false }
vim.wo.cursorline = false
vim.wo.winhighlight = 'EndOfBuffer:Comment'
local ctx = core.open('fixture', { root = temp, reuse = true })
assert(vim.wait(5000, function() return not ctx.model.git.loading end), 'local provider completed')

local function pad(text, columns) return text .. string.rep(' ', columns - vim.fn.strdisplaywidth(text)) end
-- The preceding column differs in byte width between the two rows. The selected
-- filename is Japanese; its metadata is ASCII. All visual edges must still align.
local first_prefix, second_prefix = pad('  日本語.lua', 20), pad('  docs/', 20)
local lines = { first_prefix .. pad('右側.lua', 16) .. 'neighbor', second_prefix .. pad('ASCII metadata', 16) .. 'neighbor' }
local card = {
  line = 1,
  col = #first_prefix,
  end_col = #first_prefix + #pad('右側.lua', 16),
  end_line = 2,
  label = '右側.lua',
  action = 'selected-card',
}
ctx.generation = ctx.generation + 1
ui.draw(ctx, {
  presentation = 'workspace',
  lines = lines,
  items = { { line = 1, col = 2, end_col = #first_prefix - 2, end_line = 2, label = '日本語.lua', action = 'left-card' }, card },
  highlights = {
    { line = 1, start_col = 0, end_col = #lines[1], group = 'ProjectHomeCanvas' },
    { line = 2, start_col = 0, end_col = #lines[2], group = 'ProjectHomeCanvas' },
  },
})
assert(not vim.wo.cursorline, 'workspace has no full-width cursorline')
assert(vim.wo.winhighlight:find('Normal:ProjectHomeBackdrop', 1, true), 'workspace uses backdrop')
assert(vim.wo.winhighlight:find('EndOfBuffer:Comment', 1, true), 'unrelated window mapping preserved')
vim.api.nvim_win_set_cursor(ctx.win, { 2, #second_prefix + 1 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = ctx.buf })
local namespace = vim.api.nvim_get_namespaces().project_home_selection
local marks = vim.api.nvim_buf_get_extmarks(ctx.buf, namespace, 0, -1, { details = true })
assert(#marks == 2, 'one bounded highlight per selected row')
for _, mark in ipairs(marks) do
  local text = lines[mark[2] + 1]
  assert(vim.fn.strdisplaywidth(text:sub(1, mark[3])) == 20, 'same visual left edge despite different UTF-8 byte offsets')
  assert(vim.fn.strdisplaywidth(text:sub(1, mark[4].end_col)) == 36, 'same visual right edge, before neighboring content')
  assert(mark[4].priority > 100, 'selection stays above canvas highlights')
end
local dispatch, invoked = ctx.dispatch
ctx.dispatch = function(action) invoked = action end
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(invoked == 'selected-card', 'Enter on metadata activates the same card')
ctx.dispatch = dispatch

-- Navigator's shared child views retain their existing cursorline and rail.
local child = ui.page('Checks', '', { { label = 'Check log', action = 'url', value = 'https://example.test/check' } })
local decorated = require('project_home_navigator').decorate(ctx.model, 120, child)
ctx.layout = 'navigator'
ctx.generation = ctx.generation + 1
ui.draw(ctx, decorated)
assert(vim.wo.cursorline, 'other pages keep normal dashboard cursorline behavior')
assert(vim.wo.winhighlight == 'EndOfBuffer:Comment', 'workspace backdrop removed on child page')
assert(#vim.api.nvim_buf_get_extmarks(ctx.buf, namespace, 0, -1, {}) == 0, 'workspace selection does not leak to Navigator')
local pos = vim.api.nvim_win_get_cursor(ctx.win)
assert(pos[1] == decorated.initial_focus.line and pos[2] == decorated.initial_focus.col, 'Navigator still focuses child content')

-- Fixture palettes test actual ColorScheme refreshes, not production RGB values.
local function palette(light)
  vim.api.nvim_set_hl(0, 'Normal', { fg = light and 0x223344 or 0xDDEEFF, bg = light and 0xEEEEEE or 0x112233 })
  vim.api.nvim_set_hl(0, 'NormalFloat', { bg = light and 0xFFFFFF or 0x102030 })
  vim.api.nvim_set_hl(0, 'Title', { fg = light and 0x334488 or 0x99AAFF })
  vim.api.nvim_set_hl(0, 'Special', { fg = light and 0x773366 or 0xFF99CC })
  vim.api.nvim_set_hl(0, 'DiagnosticOk', { fg = light and 0x226633 or 0x88DD99 })
  vim.api.nvim_set_hl(0, 'Comment', { fg = light and 0x778899 or 0x667788 })
  vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'workspace-fixture' })
end
local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
palette(false)
local dark = { canvas = hl('ProjectHomeCanvas').bg, surface = hl('ProjectHomeSurface').bg, resume = hl('ProjectHomeResume').bg }
palette(true)
assert(hl('ProjectHomeCanvas').bg == hl('Normal').bg and hl('ProjectHomeCanvas').bg ~= dark.canvas, 'canvas follows active theme')
assert(hl('ProjectHomeSurface').bg ~= dark.surface and hl('ProjectHomeResume').bg ~= dark.resume, 'surface and resume refresh with ColorScheme')
assert(hl('ProjectHomeResume').fg == hl('Title').fg, 'workspace accent derives from active title color')
assert(hl('ProjectHomeFile').fg == hl('Normal').fg and hl('ProjectHomeFile').bold, 'filename hierarchy uses normal foreground and bold')
assert(hl('ProjectHomeWorkspaceText').fg == hl('Normal').fg and hl('ProjectHomeWorkspaceText').bg == nil, 'workspace text adds no backdrop-colored rectangles')
local levels = {}
for level = 0, 4 do
  local color = hl('ProjectHomeActivity' .. level).fg
  assert(color and not levels[color], 'five distinct activity foreground levels')
  levels[color] = true
end
-- Real colorscheme commands clear derived groups while the Workspace window's
-- Normal mapping remains active. Theme lookup must read global Normal, not the
-- mapped (and momentarily cleared) Backdrop. Keep that mapping active each time.
core.register(
  'fixture',
  function()
    return {
      presentation = 'workspace',
      lines = { '  Canvas and surface  ' },
      highlights = { { line = 1, start_col = 0, end_col = 22, group = 'ProjectHomeCanvas' } },
      items = {},
    }
  end
)
ctx.layout = 'fixture'
ctx.render()
for _, theme in ipairs { 'habamax', 'desert', 'habamax' } do
  vim.cmd.colorscheme(theme)
  local global_normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = true })
  local canvas = vim.api.nvim_get_hl(0, { name = 'ProjectHomeCanvas', link = true })
  assert(global_normal.bg and canvas.bg == global_normal.bg and canvas.fg == global_normal.fg, 'canvas survives real theme change with active winhighlight')
  assert(vim.api.nvim_get_hl(0, { name = 'ProjectHomeSurface', link = true }).bg, 'surface survives theme reset')
  assert(vim.api.nvim_get_hl(0, { name = 'ProjectHomeResume', link = true }).fg, 'resume retains theme foreground')
  assert(vim.wo.winhighlight:find('Normal:ProjectHomeBackdrop', 1, true), 'backdrop mapping remains active')
end
ctx.dispatch 'close'
assert(not vim.wo.cursorline and vim.wo.winhighlight == 'EndOfBuffer:Comment', 'original editor window options restored')
print 'Workspace UI passed: Unicode rectangular selection, metadata Enter, theme refresh, Navigator isolation, window restoration'
vim.cmd 'qa!'
