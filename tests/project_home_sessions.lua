-- Multi-tab project/global capture, restore, and save lifecycle.
vim.opt.rtp:prepend(vim.fn.getcwd())
local sessions = require 'custom.project_home.sessions'
local state = require 'custom.project_home.state'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/a/.git', 'p')
vim.fn.mkdir(root .. '/b/.git', 'p')
root = vim.uv.fs_realpath(root)
state.configure { directory = root .. '/state' }
for _, path in ipairs { 'a/one.lua', 'a/two.lua', 'a/three.lua', 'b/one.lua' } do
  vim.fn.writefile({ 'first', 'second', 'third' }, root .. '/' .. path)
end
vim.cmd('cd ' .. vim.fn.fnameescape(root .. '/a'))
local function edit(path) vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/' .. path)) end
edit 'a/one.lua'
vim.cmd 'tabnew'
edit 'a/two.lua'
vim.cmd('vsplit ' .. vim.fn.fnameescape(root .. '/a/three.lua'))
local active_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(active_win, { 2, 2 })
local active_tab = vim.api.nvim_get_current_tabpage()
vim.cmd 'tabnew'
edit 'b/one.lua'
vim.cmd('tcd ' .. vim.fn.fnameescape(root .. '/b'))
vim.cmd 'tabnew'
edit 'a/one.lua'
vim.cmd('vsplit ' .. vim.fn.fnameescape(root .. '/b/one.lua'))
vim.api.nvim_set_current_tabpage(active_tab)
local project = sessions.capture(root .. '/a')
local global = sessions.capture(root .. '/a', { scope = 'global' })
assert(#project.tabs == 2 and project.count == 3, 'project excludes foreign and mixed-project tabs')
assert(#global.tabs == 4 and global.count == 6, 'global includes mixed-project tabs')
assert(project.active_tab == 2 and global.active_tab == 2, 'active tab saved')
assert(not sessions.inspect(global, false, root .. '/a'), 'global snapshot cannot restore as project')
local original_tabs = vim.api.nvim_list_tabpages()
vim.cmd 'tabnew'
local target = vim.api.nvim_get_current_tabpage()
assert(sessions.restore(project, { root = root .. '/a' }))
assert(#vim.api.nvim_list_tabpages() == 6, 'project reuses target and adds one tab')
for _, tab in ipairs(original_tabs) do
  assert(vim.api.nvim_tabpage_is_valid(tab), 'unrelated tabs preserved')
end
assert(vim.api.nvim_tabpage_is_valid(target), 'dashboard tab reused')
assert(vim.api.nvim_buf_get_name(0) == root .. '/a/three.lua', 'active window restored')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 2 }), 'active cursor restored')
-- A global restore hides dirty buffers even with destructive bufhidden settings.
vim.cmd 'tabnew'
local dirty = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(dirty, 0, -1, false, { 'unsaved unrelated work' })
vim.bo[dirty].bufhidden = 'wipe'
local current = vim.api.nvim_get_current_tabpage()
local invalid = vim.deepcopy(global)
invalid.tabs[4].tree = { kind = 'leaf', path = root .. '/missing' }
local before = vim.api.nvim_list_tabpages()
assert(not sessions.restore(invalid, { scope = 'global' }))
assert(vim.deep_equal(before, vim.api.nvim_list_tabpages()), 'invalid snapshot leaves all tabs unchanged')
assert(sessions.restore(global, { scope = 'global' }))
assert(#vim.api.nvim_list_tabpages() == 4, 'global replaces entire tab layout')
assert(vim.api.nvim_tabpage_is_valid(current), 'global reuses current tab as first restored tab')
assert(vim.api.nvim_buf_is_loaded(dirty) and vim.bo[dirty].modified, 'global preserves unsaved buffers')
assert(vim.api.nvim_buf_get_lines(dirty, 0, -1, false)[1] == 'unsaved unrelated work')
assert(vim.api.nvim_buf_get_name(0) == root .. '/a/three.lua')
assert(vim.api.nvim_tabpage_get_number(0) == 2, 'global restores active tab order')
assert(vim.fn.getcwd(-1, 3) == root .. '/b', 'per-tab working directory restored')
-- Exit updates project snapshots and global snapshot independently.
require('custom.project_home').setup { startup = false }
vim.api.nvim_exec_autocmds('VimLeavePre', {})
local saved = state.get(sessions.global_key).session
assert(#saved.tabs == 4 and #state.get(root .. '/a').session.tabs == 2)
assert(#state.get(root .. '/b').session.tabs == 1)
assert(sessions.restore(global, { scope = 'global' }))
assert(vim.deep_equal(saved, state.get(sessions.global_key).session), 'restore does not overwrite last-exit snapshot')
-- Dashboard-only exit must retain the previous useful global snapshot.
sessions.restoring = true
vim.cmd 'tabnew'
vim.cmd 'silent hide tabonly'
sessions.restoring = false
vim.api.nvim_exec_autocmds('VimLeavePre', {})
assert(vim.deep_equal(saved, state.get(sessions.global_key).session), 'empty exit preserves saved global session')
-- Existing single-tab data remains restorable.
local legacy = { root = root .. '/a', tree = project.tabs[1].tree, saved_at = os.time() }
assert(sessions.inspect(legacy, true, root .. '/a').count == 1)
print 'Sessions passed: project/global tabs, mixed projects, active window, preflight, unsaved buffers, exit persistence, legacy snapshots'
vim.cmd 'qa!'
