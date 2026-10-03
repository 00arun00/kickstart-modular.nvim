-- Run: nvim --headless -u NONE -i NONE -l tests/project_home_providers.lua
local cwd = vim.fn.getcwd()
vim.opt.rtp:append(cwd .. '/plugins/project-home-core')
local p = require 'project_home.providers'
local state = require 'project_home.state'
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local r = vim.system(args, { text = true }):wait()
  assert(r.code == 0, r.stderr)
  return vim.trim(r.stdout)
end
local function write(path, lines) vim.fn.writefile(lines, root .. '/' .. path) end
local function call(fn)
  local done, value, err = false, nil, nil
  fn(function(v, e)
    value, err, done = v, e, true
  end)
  assert(vim.wait(8000, function() return done end, 10), 'callback timed out')
  return value, err
end
local function load(path)
  local model
  local cancel = p.load(path, function(m) model = m end)
  assert(
    vim.wait(8000, function() return model and not model.git.loading and model.activity.status ~= 'loading' and model.prs.status ~= 'loading' end, 10),
    'load timed out'
  )
  vim.wait(80)
  cancel()
  return model
end
local ok, err = xpcall(function()
  git('init', '-b', 'main')
  git('config', 'user.name', 'Project Home Test')
  git('config', 'user.email', 'owner@example.test')
  write('README.md', { '# Project', 'first line' })
  write('old name.lua', { 'return 1' })
  git('add', '.')
  git('commit', '-m', 'Initial owner commit')
  write('other.lua', { 'return 2' })
  git('add', '.')
  git('commit', '--author', 'Other Person <other@example.test>', '-m', 'Other author')
  git('switch', '-c', 'feature/dashboard')
  git('mv', 'old name.lua', 'new name.lua')
  write('README.md', { '# Project', 'staged line' })
  git('add', 'README.md')
  write('README.md', { '# Project', 'unstaged line' })
  write('untracked file.lua', { 'return true' })
  git('worktree', 'add', root .. '-worktree', 'main')
  local model = load(root)
  assert(model.root == (vim.uv.fs_realpath(root) or root), vim.inspect(model))
  assert(model.branch == 'feature/dashboard', vim.inspect(model))
  assert(#model.git.changes == 3, vim.inspect(model.git))
  assert(model.git.staged == 2 and model.git.untracked == 1)
  local rename = vim.tbl_filter(function(c) return c.path == 'new name.lua' end, model.git.changes)[1]
  assert(rename and rename.old_path == 'old name.lua', vim.inspect(model.git.changes))
  assert(#model.worktrees == 2)
  assert(model.activity.total == 2 and model.activity.mine_total == 1, vim.inspect(model.activity))
  assert(#model.activity.year_days == 364 and #model.activity.days == 182, 'full-year history preserves the other layouts’ 26-week data')
  assert(model.prs.status == 'unavailable' and model.prs.error == 'No remote configured')
  local diff = call(function(cb) p.gitdiff(root, 'README.md', cb) end)
  assert(diff:find('Unstaged changes', 1, true) and diff:find('Staged changes', 1, true))
  local untracked = call(function(cb) p.gitdiff(root, 'untracked file.lua', cb) end)
  assert(untracked:find('+return true', 1, true))
  local history = call(function(cb) p.history(root, 'you', cb) end)
  assert(#history == 1 and history[1].subject == 'Initial owner commit', vim.inspect(history))
  git('config', 'user.email', 'OWNER@EXAMPLE.TEST')
  local case_history = call(function(cb) p.history(root, 'you', cb) end)
  assert(#case_history == 1 and load(root).activity.mine_total == 1, 'history and graph use the same case-insensitive identity')
  git('config', 'user.email', 'owner@exampleXtest')
  local literal_history = call(function(cb) p.history(root, 'you', cb) end)
  assert(#literal_history == 0, 'email punctuation is literal, not a regex wildcard')
  git('config', 'user.email', '')
  local no_identity = load(root)
  assert(not no_identity.activity.identity and no_identity.activity.total == 2, 'missing identity preserves repo activity')
  local absent_history, identity_error = call(function(cb) p.history(root, 'you', cb) end)
  assert(not absent_history and identity_error:find('user.email', 1, true), 'missing identity must not be an empty success')
  git('config', 'user.email', 'owner@example.test')
  local wt = load(root .. '-worktree')
  assert(wt.branch == 'main' and #wt.git.changes == 0)
  local callbacks = 0
  local cancel = p.load(root, function() callbacks = callbacks + 1 end)
  cancel()
  local count = callbacks
  vim.wait(150)
  assert(callbacks == count, 'cancelled load delivered a stale callback')
  state.configure { directory = root .. '/state-test' }
  assert(state.set(root, { shortcuts = { 'README.md', 'new name.lua' }, activity_scope = 'you' }))
  assert(state.get(root).shortcuts[2] == 'new name.lua')
  assert(state.update(root, 'recent', { 'README.md' }))
  assert(state.get(root).activity_scope == 'you')
  assert(vim.tbl_isempty(state.get(root .. '-worktree')), 'worktree state leaked')
  git('remote', 'add', 'origin', 'https://github.com/example/project-home-fixture.git')
  local real_gh = p.gh
  p.gh = function(_, args, cb)
    local output = args[1] == 'api' and 'owner\n'
      or vim.json.encode {
        { number = 7, title = 'Other', headRefName = 'elsewhere', author = { login = 'someone' }, reviewRequests = {} },
        { number = 3, title = 'Mine', headRefName = 'feature/dashboard', author = { login = 'owner' }, reviewRequests = {} },
        { number = 4, title = 'Review', headRefName = 'review', author = { login = 'someone' }, reviewRequests = { { login = 'owner' } } },
      }
    vim.schedule(function() cb(output) end)
    return function() end
  end
  local remote = load(root)
  assert(remote.prs.status == 'ready' and #remote.prs.items == 3)
  assert(remote.prs.items[1].number == 3 and remote.prs.items[2].number == 4, vim.inspect(remote.prs))
  p.gh = function(_, _, cb)
    vim.schedule(function() cb(nil, 'Offline fixture') end)
    return function() end
  end
  local offline = load(root)
  assert(offline.prs.status == 'unavailable' and offline.git.available and #offline.git.changes > 0)
  p.gh = function(_, _, cb)
    vim.schedule(function() cb '{invalid json' end)
    return function() end
  end
  local malformed = load(root)
  assert(malformed.prs.status == 'unavailable' and malformed.prs.error:find('Invalid response', 1, true), 'malformed PR response is not zero PRs')
  assert(malformed.git.available and #malformed.git.changes >= 3, 'remote failure leaves local Git functional')
  p.gh = real_gh
  local statefile = root .. '/state-test/' .. vim.fn.sha256(vim.fs.normalize(root)) .. '.json'
  vim.fn.writefile({ '{invalid json' }, statefile)
  local reset, state_error = state.get(root)
  assert(vim.tbl_isempty(reset) and state_error, 'malformed persisted JSON degrades to safe defaults')
  assert(state.update(root, 'shortcuts', { 'README.md' }), 'state can recover after malformed JSON')
  local plain = root .. '-plain'
  vim.fn.mkdir(plain, 'p')
  local non_git = load(plain)
  assert(not non_git.git.available and not non_git.git.loading and not non_git.git.error, 'ordinary non-Git folder is an empty state, not a failed Git command')
  vim.fn.delete(plain, 'rf')
  local unborn = root .. '-unborn'
  vim.fn.mkdir(unborn, 'p')
  assert(vim.system({ 'git', '-C', unborn, 'init', '-b', 'main' }):wait().code == 0)
  local empty = load(unborn)
  assert(empty.git.available and not empty.git.latest and #empty.git.changes == 0)
  vim.fn.delete(unborn, 'rf')
end, debug.traceback)
vim.fn.delete(root .. '-worktree', 'rf')
vim.fn.delete(root, 'rf')
if not ok then error(err) end
print 'Project home providers: Git, rename/whitespace, staged/unstaged, authors, worktrees, cancellation, remote failures, persistence passed'
