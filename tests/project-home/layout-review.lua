vim.opt.rtp:append(vim.fn.getcwd() .. '/plugins/project-home-core')
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  vim.opt.rtp:append(vim.fn.getcwd() .. '/plugins/project-home-' .. name)
end
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  local mod = require('project_home_' .. name)
  local state = {
    name = 'Example',
    root = '/example',
    branch = 'main',
    git = { available = true, error = 'permission denied' },
    activity = {
      status = 'unavailable',
      days = { { count = 0 } },
    },
  }
  local out = mod.render(state, 120)
  local text = table.concat(out.lines, '\n')
  assert(text:find('Git status unavailable', 1, true))
  assert(not text:find('0 changed files', 1, true))
  assert(text:find('Activity unavailable', 1, true))
  assert(not text:find('0 commits', 1, true))
  assert(not text:find('↑0', 1, true))
  state.activity = { status = 'ready', days = { { count = 0 } } }
  state.scope = 'you'
  text = table.concat(mod.render(state, 120).lines, '\n')
  assert(text:find('Set git user.email', 1, true))
  state.show_activity = false
  text = table.concat(mod.render(state, 120).lines, '\n')
  assert(not text:find('Set git user.email', 1, true))
  print(name .. ' review states PASS')
end
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  local render = require('project_home_' .. name).render
  local plain = table.concat(render({ git = { available = false }, show_activity = false }, 120).lines, '\n')
  assert(plain:find('Not a Git repository', 1, true) and not plain:find('Git status unavailable', 1, true))
  local failed =
    table.concat(render({ git = { available = true }, worktrees = {}, worktrees_error = 'Permission denied', show_activity = false }, 120).lines, '\n')
  assert(failed:find('Worktrees unavailable', 1, true) and not failed:find('Worktrees · 0', 1, true))
end
-- A non-success GitHub conclusion must never become a green/passing summary.
for _, name in ipairs { 'workspace', 'navigator', 'atelier' } do
  local mod = require('project_home_' .. name)
  for _, outcome in ipairs { 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'STALE', 'FAILURE' } do
    local state = {
      git = { available = true },
      prs = { items = { { number = 1, title = 'Check', statusCheckRollup = { { conclusion = outcome } } } } },
      show_activity = false,
    }
    local out = mod.render(state, 120)
    assert(table.concat(out.lines, '\n'):find('Checks failed', 1, true), name .. ' missed ' .. outcome)
    local warning = false
    for _, h in ipairs(out.highlights) do
      if h.group == 'ProjectHomeWarning' then warning = true end
    end
    assert(warning, 'Failure must have semantic warning color')
  end
  local state = {
    git = { available = true },
    prs = { items = { { number = 1, title = 'Check', statusCheckRollup = { { conclusion = 'UNRECOGNIZED' } } } } },
    show_activity = false,
  }
  assert(table.concat(mod.render(state, 120).lines, '\n'):find('Checks unknown', 1, true))
end
local nav = require 'project_home_navigator'
local page = {
  lines = { 'PR #42', string.rep('full diff contents ', 15), 'Open file' },
  highlights = { { line = 1, start_col = 0, end_col = -1, group = 'ProjectHomeTitle' } },
  items = { { line = 3, col = 0, label = 'Open file', action = 'file', value = '/a' } },
}
local out = nav.decorate({}, 120, page)
assert(out.lines[2]:find(page.lines[2], 1, true))
local has_pr, has_file = false, false
for _, item in ipairs(out.items) do
  if item.action == 'prs' then has_pr = true end
  if item.action == 'file' then
    has_file = true
    assert(item.col == 22)
    assert(item.value == '/a')
  end
end
assert(has_pr and has_file)
assert(
  out.initial_focus and out.initial_focus.action == 'file' and out.initial_focus.col == 22,
  'Navigator must initially focus its content action, not its rail'
)
assert(nav.decorate({}, 80, page) == page)
print 'Navigator child decoration PASS'
vim.cmd 'qa!'
