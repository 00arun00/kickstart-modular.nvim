vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
-- Run: nvim --headless -u NONE -l tests/project_home_core.lua
local repo = vim.fn.getcwd()
vim.opt.rtp:prepend(repo)
require('custom.project_home.volt').setup()
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
tmp = vim.uv.fs_realpath(tmp)
vim.fn.writefile({ 'one', 'two' }, tmp .. '/one.lua')
vim.fn.writefile({ 'alpha', 'beta' }, tmp .. '/two.lua')
require('custom.project_home.state').configure { directory = tmp .. '/state' }
local core = require 'custom.project_home'
core.setup { startup = false }
vim.cmd('cd ' .. vim.fn.fnameescape(tmp))
vim.wo.number = true
vim.wo.statusline = 'ORIGINAL'
local ctx = core.open('volt', { reuse = true, root = tmp })
assert(vim.api.nvim_win_get_cursor(ctx.win)[1] == ctx.items[1].line, 'initial focus is actionable')
assert(vim.wait(5000, function() return ctx.model.prs.status ~= 'loading' end), 'provider completion')
for _, name in ipairs(core.layouts()) do
  ctx.layout = name
  ctx.home()
  assert(vim.api.nvim_buf_get_name(ctx.buf):find('project-home://' .. name .. '/', 1, true), 'buffer name follows layout')
  assert(vim.api.nvim_buf_line_count(ctx.buf) > 8, name .. ' renders')
end
-- Every column is independently selectable by cursor position and Enter.
local ui = require 'custom.project_home.ui'
local original = ctx.dispatch
local invoked
ctx.dispatch = function(a) invoked = a end
ui.draw(ctx, { lines = { 'left            right' }, items = { { line = 1, col = 0, action = 'left' }, { line = 1, col = 16, action = 'right' } } })
vim.api.nvim_win_set_cursor(ctx.win, { 1, 16 })
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(invoked == 'right')
ui.draw(
  ctx,
  { lines = { 'new heading', 'left            right' }, items = { { line = 2, col = 0, action = 'left' }, { line = 2, col = 16, action = 'right' } } }
)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(ctx.win), { 2, 16 }), 'async redraw preserves selected action')
vim.fn.maparg('k', 'n', false, true).callback()
assert(vim.api.nvim_win_get_cursor(ctx.win)[2] == 0)
ctx.generation = ctx.generation + 1
ui.draw(ctx, {
  lines = { 'Home', '', '', '', '                    Check logs' },
  items = { { line = 1, col = 0, action = 'home' }, { line = 5, col = 20, action = 'url', value = 'https://example.test' } },
  initial_focus = { line = 5, col = 20 },
})
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(ctx.win), { 5, 20 }), 'child focus lands on content, not persistent rail')
ctx.dispatch = original
ctx.home()
local fired = false
local late = ctx.guard(function() fired = true end)
ctx.dispatch 'more'
late()
assert(not fired, 'stale callback dropped')
ctx.dispatch 'home'
ctx.dispatch('activity', 'you')
assert(require('custom.project_home.state').get(ctx.model.root).scope == 'you')
ctx.dispatch 'activity_visibility'
assert(require('custom.project_home.state').get(ctx.model.root).activity_visible == false)
-- A list opened before provider completion must update in place.
local providers = require 'custom.project_home.providers'
local original_load = providers.load
local deliver
providers.load = function(_, cb)
  deliver = cb
  return function() end
end
ctx.refresh()
local model = vim.deepcopy(ctx.model)
model.git = { available = true, loading = true, changes = {} }
deliver(model)
ctx.dispatch 'git'
assert(#ctx.pages == 1)
model.git.loading = false
model.git.changes = { { path = 'one.lua', index = ' ', worktree = 'M' } }
deliver(model)
assert(#ctx.pages == 1 and table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), '\n'):find('one.lua', 1, true))
ctx.dispatch 'home'
-- RPC null is vim.NIL, which must not be mistaken for a commit hash.
local original_history = providers.history
providers.history = function(_, _, cb) cb {} end
ctx.dispatch('history', vim.NIL)
assert(table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), '\n'):find('No commits', 1, true))
providers.history = original_history
ctx.dispatch 'home'
-- Returning from a detail view restores the selected row in the previous list.
ctx.show(ui.page('List', '', { { label = 'First', action = 'pr', value = 42 }, { label = 'Second', action = 'pr', value = 39 } }))
vim.api.nvim_win_set_cursor(ctx.win, { ctx.items[2].line, ctx.items[2].col })
local selectedrow = vim.api.nvim_win_get_cursor(ctx.win)
ctx.show(ui.page('Detail', '', {}))
ctx.dispatch 'back'
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(ctx.win), selectedrow), 'back restores selected row')
ctx.dispatch 'home'
-- Back navigation retains each PR's detail data independently.
local original_detail = providers.pr_detail
providers.pr_detail = function(_, number, cb)
  cb { title = 'PR ' .. number, body = 'Body ' .. number, statusCheckRollup = { { name = 'Check ' .. number, conclusion = 'SUCCESS' } } }
end
ctx.dispatch('pr', 42)
ctx.dispatch 'back'
ctx.dispatch('pr', 39)
ctx.dispatch('pr_checks', 42)
assert(table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), '\n'):find('Check 42', 1, true))
providers.pr_detail = original_detail
providers.load = original_load
ctx.dispatch 'home'
local checkout = tmp .. '/checkout'
vim.fn.mkdir(checkout, 'p')
vim.fn.writefile({ 'checkout' }, checkout .. '/file.lua')
ctx.dispatch('worktree', checkout)
local target = core.contexts[vim.api.nvim_get_current_buf()]
assert(target.original_options.number == true and target.original_options.statusline == 'ORIGINAL', 'new worktree inherits editor options')
target.dispatch('file', checkout .. '/file.lua')
assert(vim.wo.number and vim.wo.statusline == 'ORIGINAL', 'file restores editor chrome')
vim.cmd.tabclose()
ctx.dispatch 'close'
assert(vim.wo.number and vim.wo.statusline == 'ORIGINAL', 'dashboard options restored')
-- JSON split sessions restore in the current tab, keeping modified buffers intact.
vim.cmd('edit ' .. vim.fn.fnameescape(tmp .. '/one.lua'))
vim.cmd.vsplit(tmp .. '/two.lua')
vim.api.nvim_win_set_cursor(0, { 2, 1 })
local first = vim.api.nvim_tabpage_list_wins(0)[1]
vim.api.nvim_win_set_width(first, 17)
local session = require('custom.project_home.sessions').capture(tmp)
assert(session.count == 2)
local dirty = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(dirty, 0, 1, false, { 'unsaved' })
local oldtab = vim.api.nvim_get_current_tabpage()
local oldtabs = #vim.api.nvim_list_tabpages()
vim.cmd 'vnew'
local extra = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(extra, 0, -1, false, { 'unsaved extra' })
vim.bo[extra].bufhidden = 'wipe'
assert(require('custom.project_home.sessions').restore(session, { window_options = { number = true, statusline = 'ORIGINAL' } }))
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  assert(vim.wo[win].number and vim.wo[win].statusline == 'ORIGINAL', 'restored windows use editor options')
end
assert(#vim.api.nvim_list_tabpages() == oldtabs and vim.api.nvim_get_current_tabpage() == oldtab and vim.bo[dirty].modified)
assert(
  vim.api.nvim_buf_is_loaded(extra) and vim.bo[extra].modified and vim.api.nvim_buf_get_lines(extra, 0, -1, false)[1] == 'unsaved extra',
  'unrestored dirty buffer survives in memory'
)
assert(vim.fn.getcwd() == tmp and #vim.api.nvim_tabpage_list_wins(0) == 2)
local restoredfirst = vim.api.nvim_tabpage_list_wins(0)[1]
assert(math.abs(vim.api.nvim_win_get_width(restoredfirst) - 17) <= 2, 'split proportions preserved')
local corrupt = vim.deepcopy(session)
corrupt.tabs[1].tree = { kind = 'leaf', path = tmp .. '/missing' }
local before = #vim.api.nvim_list_tabpages()
local ok = require('custom.project_home.sessions').restore(corrupt)
assert(not ok and #vim.api.nvim_list_tabpages() == before)
-- Any one layout can be installed, even if a removed layout was remembered.
local registered = core.renderers
core.renderers = { volt = registered.volt }
require('custom.project_home.state').update('__preferences__', 'layout', 'navigator')
core.setup { startup = false }
local fallback = core.open(nil, { root = tmp, reuse = true })
assert(fallback and fallback.layout == 'volt', 'standalone layout survives missing remembered layout')
core.renderers = registered
print 'Core tests passed: layouts, column navigation, stale callbacks, preferences, safe session restoration'
vim.cmd 'qa!'
