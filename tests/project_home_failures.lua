vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
-- nvim --headless -u NONE -l tests/project_home_failures.lua
local repo = vim.fn.getcwd()
vim.opt.rtp:prepend(repo)
require('custom.project_home.volt').setup()
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
tmp = vim.uv.fs_realpath(tmp)
vim.fn.writefile({ 'one' }, tmp .. '/one.lua')
vim.fn.writefile({ 'two' }, tmp .. '/two.lua')
local state = require 'custom.project_home.state'
state.configure { directory = tmp .. '/state' }
local core = require 'custom.project_home'
core.setup { startup = false }
vim.cmd('cd ' .. vim.fn.fnameescape(tmp))
state.set(tmp, { recents = 'malformed', session = 'malformed', activity_visible = 'wrong' })
local ctx = core.open('volt', { root = tmp, reuse = true })
assert(vim.wait(5000, function() return ctx.model.prs.status ~= 'loading' end))
assert(#ctx.model.recents == 0 and ctx.model.session == nil and ctx.model.show_activity == true)
ctx.dispatch 'resume'
assert(table.concat(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false), '\n'):find('No valid saved workspace', 1, true))
ctx.dispatch 'home'
state.set(tmp, {
  recents = { '/etc/hosts', tmp .. '/one.lua', false, 17 },
  session = { tree = { kind = 'unknown' }, root = tmp },
})
ctx.refresh()
assert(vim.wait(5000, function() return #ctx.model.recents == 1 end))
assert(ctx.model.recents[1].path == tmp .. '/one.lua')
assert(ctx.model.session == nil)
local sessions = require 'custom.project_home.sessions'
local bad = { root = tmp, tree = { kind = 'leaf', path = tmp .. '/missing' }, saved_at = 'bad' }
local before = #vim.api.nvim_list_tabpages()
assert(not sessions.restore(bad))
assert(#vim.api.nvim_list_tabpages() == before)
local huge = { root = tmp, tree = { kind = 'row', children = {} } }
for i = 1, 20 do
  local branch = { kind = 'row', children = {} }
  for j = 1, 8 do
    branch.children[j] = { kind = 'leaf', path = tmp .. '/one.lua' }
  end
  huge.tree.children[i] = branch
end
assert(not sessions.inspect(huge), 'saved node count bounded')
local metadata = {
  root = tmp,
  saved_at = 1e100,
  tree = {
    kind = 'row',
    width = 'bad',
    children = {
      { kind = 'leaf', path = tmp .. '/one.lua', cursor = { 1.5, 1e400 }, width = {} },
      { kind = 'leaf', path = tmp .. '/two.lua', cursor = { -999, 1e100 } },
    },
  },
}
assert(sessions.inspect(metadata).saved_at <= os.time())
assert(not sessions.inspect(metadata, false, tmp .. '/wrong-project'), 'session root mismatch rejected')
local escaped = vim.deepcopy(metadata)
escaped.tree = { kind = 'leaf', path = tmp .. '/../outside.lua' }
assert(not sessions.inspect(escaped), 'session files stay inside root')
assert(sessions.restore(metadata), 'malformed optional geometry does not crash restore')
vim.cmd.tabclose()
ctx.dispatch 'home'
ctx.prs = {
  [42] = {
    statusCheckRollup = {
      { name = 'Needs action', conclusion = 'ACTION_REQUIRED' },
      { name = 'Startup', conclusion = 'STARTUP_FAILURE' },
      { name = 'Stale', conclusion = 'STALE' },
      { name = 'Passing', conclusion = 'SUCCESS' },
    },
  },
}
ctx.dispatch('pr_checks', 42)
local warning, success = 0, 0
for _, h in ipairs(ctx.pages[#ctx.pages].highlights) do
  if h.group == 'ProjectHomeWarning' then
    warning = warning + 1
  elseif h.group == 'ProjectHomeSuccess' then
    success = success + 1
  end
end
assert(warning == 6 and success == 2, 'check labels and status have semantic failure/success colors')
print 'Failure tests passed: malformed state, project scoping, bounded sessions, missing files, check semantics'
vim.cmd 'qa!'
