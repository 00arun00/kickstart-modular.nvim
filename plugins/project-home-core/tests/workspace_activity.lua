vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
vim.opt.rtp:append(vim.fn.getcwd() .. '/plugins/project-home-core')
vim.opt.rtp:append(vim.fn.getcwd() .. '/plugins/project-home-volt')
local render = require('project_home_volt.view').render
local days = {}
for i = 1, 364 do
  days[i] = { date = '2026-01-01', count = i <= 182 and 3 or 1, mine = i <= 182 and 2 or 0 }
end
local model = {
  root = '/tmp',
  name = 'test',
  session = {},
  recents = {},
  shortcuts = {},
  git = { available = false },
  activity = { status = 'ready', identity = 'me', year_days = days },
}
for _, case in ipairs { { 80, 26, 182, 0 }, { 120, 39, 455, 182 }, { 166, 52, 728, 364 } } do
  for _, scope in ipairs { 'repo', 'you' } do
    model.scope = scope
    local page = render(model, case[1], 50)
    local graph_rows = 0
    local text = table.concat(page.lines, '\n')
    for _, line in ipairs(page.lines) do
      local _, cells = line:gsub('■', '')
      if cells == case[2] then graph_rows = graph_rows + 1 end
      assert(vim.fn.strdisplaywidth(line) <= case[1], 'content fits width')
    end
    assert(graph_rows == 7, 'scope preserves range and seven complete rows')
    assert(text:find(tostring(case[2]) .. (case[1] == 80 and ' weeks' or 'w'), 1, true), 'period follows width')
    assert(text:find(tostring(scope == 'repo' and case[3] or case[4]) .. ' commits', 1, true), 'count sums only visible days')
    local resume, recent
    for _, item in ipairs(page.items) do
      if item.action == 'resume' then resume = item end
      if item.action == 'recents' then recent = item end
    end
    assert(resume and resume.key == 'u' and resume.line < recent.line, 'resume is a toolbar shortcut')
  end
end
model.session = nil
for _, item in ipairs(render(model, 80, 50).items) do
  assert(item.action ~= 'resume', 'no resume action without a saved session')
end
print 'Workspace activity passed: responsive ranges, visible counts, scopes, and conditional Resume shortcut'
