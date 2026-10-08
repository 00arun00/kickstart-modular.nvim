vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
vim.opt.rtp:prepend(vim.fn.getcwd())
local render = require('custom.project_home.volt.view').render
local days = {}
for i = 1, 364 do
  days[i] = { date = os.date('%Y-%m-%d', os.time { year = 2026, month = 1, day = i, hour = 12 }), count = i <= 182 and 3 or 1, mine = i <= 182 and 2 or 0 }
end
local model = {
  root = '/tmp',
  name = 'test',
  session = {},
  recents = {},
  git = { available = false },
  activity = { status = 'ready', identity = 'me', year_days = days },
}
for _, case in ipairs { { 80, 26, 178, 0 }, { 120, 39, 443, 174 }, { 166, 52, 716, 356 } } do
  for _, scope in ipairs { 'repo', 'you' } do
    model.scope = scope
    local page = render(model, case[1], 50)
    local graph_rows = 0
    local text = table.concat(page.lines, '\n')
    for _, line in ipairs(page.lines) do
      local cells = 0
      for _, glyph in ipairs { '■', '□' } do
        local _, count = line:gsub(glyph, '')
        cells = cells + count
      end
      if cells == case[2] then graph_rows = graph_rows + 1 end
      assert(vim.fn.strdisplaywidth(line) <= case[1], 'content fits width')
    end
    local _, future = text:gsub('□', '')
    assert(not text:find('▣', 1, true) and future == 4, 'Wednesday ends history, with four hollow future days')
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
-- Every weekday keeps the same row, including Monday/Sunday boundaries.
for weekday = 1, 7 do
  for i, day in ipairs(days) do
    day.date = os.date('%Y-%m-%d', os.time { year = 2026, month = 1, day = 5 + weekday - 1 - (#days - i), hour = 12 })
  end
  local rows = {}
  for _, line in ipairs(render(model, 80, 50).lines) do
    if line:find('□', 1, true) or select(2, line:gsub('■', '')) == 26 then rows[#rows + 1] = line end
  end
  assert(#rows == 7)
  for row, line in ipairs(rows) do
    local _, filled = line:gsub('■', '')
    assert(filled == (row <= weekday and 26 or 25), 'past and today use the same filled square')
    assert((line:find('□', 1, true) ~= nil) == (row > weekday), 'only future days are hollow')
  end
  assert(
    rows[1]:find('Mo', 1, true) and rows[3]:find('We', 1, true) and rows[5]:find('Fr', 1, true) and rows[7]:find('Su', 1, true),
    'weekday labels stay fixed'
  )
end
model.session = nil
for _, item in ipairs(render(model, 80, 50).items) do
  assert(item.action ~= 'resume', 'no resume action without a saved session')
end
print 'Workspace activity passed: responsive ranges, visible counts, scopes, and conditional Resume shortcut'
