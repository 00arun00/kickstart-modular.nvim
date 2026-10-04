vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local ui, view = require 'custom.project_home.ui', require 'custom.project_home.volt.view'
local ctx = {
  buf = vim.api.nvim_get_current_buf(),
  win = vim.api.nvim_get_current_win(),
  layout = 'volt',
  generation = 1,
  model = {
    root = root,
    session = {},
    recents = { 'one.lua', 'two.lua' },
    git = { available = true, changes = {} },
    prs = { items = { { number = 42, title = 'First PR' }, { number = 43, title = 'Second PR' } } },
    activity = { status = 'loading' },
  },
}
local invoked
ctx.dispatch = function(action, value) invoked = { action, value } end
ui.attach(ctx)
ui.highlights()
local function draw() ui.draw(ctx, view.render(ctx.model, 120, 52)) end
local function key(k)
  local mapping = vim.fn.maparg(k, 'n', false, true)
  assert(type(mapping.callback) == 'function', 'mapped key ' .. k)
  mapping.callback()
end
draw()
key 'r'
assert(ctx.keyboard_section == 'recent')
key '2'
assert(invoked[1] == 'file' and invoked[2] == 'two.lua', 'numbers open the focused section')
key 'j'
key '<CR>'
assert(invoked[2] == 'one.lua', 'j skips heading and metadata')
key 'j'
key '<CR>'
assert(invoked[2] == 'two.lua', 'movement wraps within section')
key 'k'
local before = vim.api.nvim_win_get_cursor(ctx.win)
ctx.model.git.latest = { hash = '1234567', subject = 'Async update' }
draw()
assert(vim.deep_equal(before, vim.api.nvim_win_get_cursor(ctx.win)), 'background redraw preserves selected file')
key '?'
assert(ctx.help_win and vim.api.nvim_win_is_valid(ctx.help_win), 'help is a real popup')
local help = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(ctx.help_win), 0, -1, false), '\n')
assert(help:find('Recent files', 1, true) and help:find('Press r again', 1, true), 'help reflects focused section')
key '<Esc>'
assert(vim.api.nvim_get_current_win() == ctx.win and vim.deep_equal(before, vim.api.nvim_win_get_cursor(ctx.win)), 'help restores exact focus')
key '<Tab>'
assert(ctx.keyboard_section == 'git', 'Tab moves directly from recent files to Git')
assert(vim.fn.maparg('x', 'n') == '', 'removed section has no dashboard key binding')
key '<S-Tab>'
assert(ctx.keyboard_section == 'recent')
key 'r'
assert(invoked[1] == 'recents', 'repeat section key opens full list')
key 'p'
key '2'
assert(invoked[1] == 'pr' and invoked[2] == 43)
key '<Esc>'
assert(ctx.keyboard_section == nil, 'Esc returns to dashboard-level navigation')
invoked = nil
key '2'
assert(invoked == nil, 'numbers do nothing without focused section')
key 'f'
assert(invoked[1] == 'find', 'global action remains immediate')
ui.draw(ctx, ui.page('Child', '', { { label = 'An action', action = 'example' } }))
assert(not ctx.keyboard_active and vim.fn.maparg('2', 'n') == '', 'home number mappings do not leak to child pages')
key '<Esc>'
assert(invoked[1] == 'back', 'child Escape retains back navigation')
print 'Keyboard passed: section jumps, numbers, bounded movement, async focus, contextual help, and child isolation'
