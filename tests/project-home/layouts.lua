vim.opt.rtp:append(vim.fn.getcwd() .. '/plugins/project-home-core')
local cwd = vim.fn.getcwd()
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  vim.opt.rtp:append(cwd .. '/plugins/project-home-' .. name)
end
local model = {
  title = 'nvim',
  root = '/Users/aj/code/config/nvim',
  branch = 'feature/dashboard',
  session = { buffers = {} },
  recents = { { path = 'lua/日本語.lua', label = '日本語.lua' }, { path = 'a.lua' }, { path = 'b.lua' }, { path = 'README.md' }, { path = 'docs/a.md' } },
  shortcuts = { { path = 'README.md' }, { path = 'init.lua' }, { path = 'lua/', label = 'lua/' }, { path = 'docs/', label = 'docs/' } },
  git = {
    available = true,
    changes = { { path = 'a' }, { path = 'b' } },
    staged = 1,
    unstaged = 1,
    modified = 1,
    untracked = 0,
    latest = { hash = 'abcdef1234', subject = 'Add project entry points' },
  },
  prs = {
    status = 'ready',
    items = {
      { number = 42, title = 'Improve workspace', statusCheckRollup = { { conclusion = 'FAILURE' } } },
      { number = 39, title = '環境設定', isDraft = true },
      { number = 37, title = 'A very long pull request title that still has a reachable target', reviewDecision = 'APPROVED' },
    },
  },
  worktrees = { { path = '/a' }, { path = '/b' } },
  activity = { days = {}, total = 33, mine_total = 10, status = 'ready' },
  scope = 'repo',
}
for i = 1, 182 do
  model.activity.days[i] = { date = os.date('%Y-%m-%d', os.time { year = 2026, month = 4, day = 5 } + (i - 1) * 86400), count = i % 5, mine = i % 2 }
end
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  for _, w in ipairs { 40, 60, 80, 89, 90, 120 } do
    local result = require('project_home_' .. name).render(model, w)
    assert(#result.lines > 0 and #result.items > 15)
    for i, line in ipairs(result.lines) do
      assert(vim.fn.strdisplaywidth(line) <= w, name .. ' overflow ' .. w .. ':' .. i)
    end
    for _, item in ipairs(result.items) do
      assert(item.line > 0 and item.line <= #result.lines)
      assert(item.col >= 0 and item.col < #result.lines[item.line])
      assert(item.action)
    end
    for _, h in ipairs(result.highlights) do
      assert(h.start_col >= 0 and h.end_col <= #result.lines[h.line])
    end
    local actions = {}
    for _, item in ipairs(result.items) do
      actions[item.action] = true
    end
    for _, a in ipairs { 'find', 'search', 'browse', 'new', 'resume', 'recents', 'shortcuts', 'git', 'prs', 'pr', 'worktrees', 'activity', 'history' } do
      assert(actions[a], name .. ' missing ' .. a .. ' at ' .. w)
    end
    print(name, w, #result.lines, #result.items)
  end
  for _, empty in ipairs {
    { name = 'empty', root = '/empty', git = { available = false }, prs = { items = {}, status = 'unavailable' } },
    { name = 'loading', git = { loading = true }, activity = { status = 'loading' } },
  } do
    local result = require('project_home_' .. name).render(empty, 40)
    assert(#result.lines > 0)
  end
end
for _, name in ipairs { 'navigator', 'atelier' } do
  local result = require('project_home_' .. name).render(model, 120)
  local text = table.concat(result.lines, '\n')
  assert(text:find('1 staged', 1, true) and text:find('1 unstaged', 1, true) and text:find('0 untracked', 1, true), name .. ' clipped a Git count category')
end
for _, scheme in ipairs { 'habamax', 'default' } do
  vim.cmd.colorscheme(scheme)
  require('project_home.ui').highlights()
  for _, group in ipairs { 'Title', 'Muted', 'Accent', 'Warning', 'Success', 'Border' } do
    local hl = vim.api.nvim_get_hl(0, { name = 'ProjectHome' .. group, link = true })
    assert(hl.link and not hl.fg and not hl.bg, 'Layout highlights must inherit theme links')
  end
end
vim.cmd 'qa!'
