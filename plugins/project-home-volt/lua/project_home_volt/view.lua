local M = {}
local L = require 'project_home.layout'
local U = require 'volt.ui'
local function c(text, group, action, value, key, section)
  return { tostring(text or ''), 'ProjectHomeVolt' .. (group or 'Text'), action and { action = action, value = value, key = key, section = section } or nil }
end
local function fill(text, width)
  text = L.clip(text, math.max(0, width))
  return text .. string.rep(' ', math.max(0, width - L.width(text)))
end
local function pad(n) return c(string.rep(' ', math.max(0, n))) end
local function fit(row, width)
  local out, remaining = {}, width
  for _, chunk in ipairs(row) do
    if remaining <= 0 then break end
    local copy = vim.deepcopy(chunk)
    copy[1] = L.clip(copy[1], remaining)
    remaining = remaining - L.width(copy[1])
    out[#out + 1] = copy
  end
  out[#out + 1] = pad(remaining)
  return out
end
local function pair(left, right, width)
  local reserve = math.min(U.line_w(right), math.floor(width * 0.52))
  local row = fit(left, width - reserve)
  vim.list_extend(row, fit(right, reserve))
  return row
end
local function title(key, text, section, width, extra)
  local label = c(text, 'Title')
  label.heading = section
  return pair({ c(key .. ' ', 'Accent'), label }, extra or {}, width)
end
local function action(text, name, key, section, value, group) return c(text, group, name, value, key, section) end
local function file_info(file, root)
  local path = type(file) == 'table' and file.path or file
  path = tostring(path or '')
  local relative = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2) or path
  local clean = relative:gsub('/$', '')
  local leaf, parent = clean:match '[^/]+$' or clean, clean:match '^(.*)/[^/]+$'
  local directory = path:sub(-1) == '/' or vim.fn.isdirectory(root .. '/' .. path) == 1
  return leaf .. (directory and '/' or ''), parent and parent .. '/' or 'Project root', path, relative
end
local function files(model, width)
  local rows = { title('r', 'Recent files', 'recent', width, { action('All recent →', 'recents', nil, 'recent', nil, 'Muted') }), {} }
  local recents = model.recents or {}
  if #recents == 0 then
    rows[#rows + 1] = { pad(2), c('Your recent project files appear here.', 'Muted') }
    rows[#rows + 1] = { pad(2), action('Find your first file →', 'find', nil, 'recent', nil, 'Accent') }
  else
    for i, file in ipairs(recents) do
      if i > 5 then break end
      local leaf, parent, path = file_info(file, model.root)
      rows[#rows + 1] = { pad(2), action(fill(leaf, width - 2), 'file', nil, 'recent', path, 'Title') }
      rows[#rows + 1] = { pad(2), c(L.clip(parent, width - 2), 'Muted') }
    end
  end
  rows[#rows + 1] = {}
  rows[#rows + 1] =
    title('x', 'Start Exploring', 'explore', width, #(model.shortcuts or {}) > 0 and { action('Edit →', 'shortcuts', nil, 'explore', nil, 'Muted') } or {})
  rows[#rows + 1] = {}
  local entries = model.shortcuts or {}
  if #entries == 0 then rows[#rows + 1] = { pad(2), action('Add a project shortcut →', 'shortcuts', nil, 'explore', nil, 'Accent') } end
  local cell = math.floor((width - 3) / 2)
  for i = 1, math.min(5, #entries), 2 do
    local columns = {}
    for j = i, math.min(i + 1, #entries) do
      local leaf, _, path, rel = file_info(entries[j], model.root)
      local low = rel:lower():gsub('/$', '')
      local description = low:find('readme', 1, true) and 'Project guide'
        or low == 'init.lua' and 'Config entry'
        or low == 'lua' and 'Modules'
        or low:match '^docs?' and 'Documentation'
        or low:find('test', 1, true) and 'Tests & checks'
        or 'Project shortcut'
      columns[#columns + 1] = {
        w = cell,
        pad = j == i and 3 or 0,
        lines = {
          fit({ pad(2), action(fill(leaf, cell - 2), 'file', nil, 'explore', path, 'Title') }, cell),
          fit({
            pad(2),
            c(cell < 17 and (description == 'Project guide' and 'Guide' or description == 'Documentation' and 'Docs' or description) or description, 'Muted'),
          }, cell),
        },
      }
    end
    vim.list_extend(rows, U.grid_col(columns))
    if i + 2 <= #entries then rows[#rows + 1] = {} end
  end
  return vim.tbl_map(function(row) return fit(row, width) end, rows)
end
local function repository(model, width)
  local git = model.git or {}
  local rows = { title('g', 'Git workspace', 'git', width), {} }
  if git.loading or git.available == false or git.error then
    rows[#rows + 1] = { pad(2), c(git.loading and 'Reading local Git…' or git.error and 'Git status unavailable' or 'No Git repository', 'Muted') }
    if git.error then rows[#rows + 1] = { pad(2), action('Retry →', 'refresh', 'R', 'git', nil, 'Warn') } end
    return vim.tbl_map(function(row) return fit(row, width) end, rows)
  end
  local changed = #(git.changes or {})
  rows[#rows + 1] = { pad(2), action(changed .. ' changed files', 'git', nil, 'git', nil, 'Text') }
  local counts = ('%d staged · %d unstaged · %d untracked'):format(git.staged or 0, git.unstaged or 0, git.untracked or 0)
  if L.width(counts) <= width - 2 then
    rows[#rows + 1] = { pad(2), c(counts, 'Muted') }
  else
    rows[#rows + 1] = { pad(2), c(('%d staged · %d unstaged'):format(git.staged or 0, git.unstaged or 0), 'Muted') }
    rows[#rows + 1] = { pad(2), c(('%d untracked'):format(git.untracked or 0), 'Muted') }
  end
  rows[#rows + 1] = {}
  if git.latest then
    rows[#rows + 1] = { pad(2), action(L.clip(git.latest.subject or 'Latest commit', width - 2), 'commit', 'c', 'git', git.latest.hash) }
    rows[#rows + 1] = { pad(2), c((git.latest.hash or ''):sub(1, 7) .. '  ·  ' .. ((git.latest.date or ''):sub(1, 10)), 'Muted') }
  else
    rows[#rows + 1] = { pad(2), c('No commits yet', 'Muted') }
  end
  rows[#rows + 1] = {}
  if width < 40 then
    rows[#rows] = U.separator('─', width, 'ProjectHomeVoltRule')
  else
    rows[#rows + 1] = U.separator('─', width, 'ProjectHomeVoltRule')
    rows[#rows + 1] = {}
  end
  local prs = (model.prs or {}).items or {}
  rows[#rows + 1] =
    title('p', 'Pull requests', 'prs', width, { action(#prs > 0 and ('View all · ' .. #prs) or 'Browse →', 'prs', nil, 'prs', nil, 'Muted') })
  rows[#rows + 1] = {}
  if #prs == 0 then
    local status = (model.prs or {}).status
    rows[#rows + 1] = {
      pad(2),
      c(status == 'loading' and 'Fetching pull requests…' or status == 'unavailable' and 'Remote status unavailable' or 'No open pull requests', 'Muted'),
    }
  else
    for i, pr in ipairs(prs) do
      if i > 3 then break end
      rows[#rows + 1] = { pad(2), action(fill('#' .. pr.number .. '  ' .. (pr.title or ''), width - 2), 'pr', nil, 'prs', pr.number, 'Title') }
      local status = vim.trim(L.pr_status(pr))
      local group = status:lower():find('fail', 1, true) and 'Bad'
        or status:find('Changes requested', 1, true) and 'Warn'
        or status:find('passed', 1, true) and 'Good'
        or 'Tag'
      rows[#rows + 1] = { pad(2), c(L.clip(status, width - 2), group) }
      rows[#rows + 1] = {}
    end
  end
  if #prs == 0 then
    rows[#rows + 1] = {}
    rows[#rows + 1] = {}
  end
  rows[#rows + 1] = pair(
    { c('w ', 'Accent'), action('Worktrees →', 'worktrees', 'w', 'git') },
    { c(model.worktrees_error and 'unavailable' or tostring(#(model.worktrees or {})) .. ' checkouts', 'Muted') },
    width
  )
  return vim.tbl_map(function(row) return fit(row, width) end, rows)
end
local function activity(model, width)
  local data, scope = model.activity or {}, model.scope or 'repo'
  local weeks = width >= 136 and 52 or width >= 110 and 39 or 26
  local graphwidth = weeks * 2 + 3
  local side = width >= 72
  local leftwidth = side and width - graphwidth - 3 or width
  local days = data.year_days or data.days or {}
  local start, total = math.max(0, #days - weeks * 7), 0
  for i = start + 1, #days do
    total = total + (scope == 'you' and (days[i].mine or 0) or (days[i].count or 0))
  end
  local bad = data.status == 'unavailable'
  local missing = scope == 'you' and (not data.identity or data.identity == '')
  local left = {
    { c('Activity', 'Title', nil, nil, nil, nil) },
    {},
    {
      c(
        data.status == 'loading' and 'Loading…' or bad and 'Activity unavailable' or missing and 'Identity not set' or tostring(total) .. ' commits',
        'Accent'
      ),
    },
    { c(leftwidth < 21 and ('Last ' .. weeks .. ' weeks') or ('All branches · ' .. weeks .. 'w'), 'Muted') },
    {},
  }
  left[1][1].heading = 'activity'
  local repo = action(' Repository ', 'activity', scope == 'you' and 'a' or nil, 'activity', 'repo', scope == 'repo' and 'Key' or 'Tag')
  local yours = action(' Yours ', 'activity', scope == 'repo' and 'a' or nil, 'activity', 'you', scope == 'you' and 'Key' or 'Tag')
  if leftwidth >= 21 then
    left[#left + 1] = { repo, c ' ', yours }
  else
    left[#left + 1] = { repo }
    left[#left + 1] = { yours }
  end
  left[#left + 1] = {}
  left[#left + 1] = { action(bad and 'Retry →' or 'h History →', bad and 'refresh' or 'history', 'h', 'activity') }
  local graph = {}
  if bad or missing or data.status == 'loading' then
    graph = {
      {},
      {
        c(
          bad and 'Activity could not be loaded. Retry to refresh.' or missing and 'Set git user.email to see your activity.' or 'Reading repository history…',
          'Muted'
        ),
      },
    }
  elseif width < 55 then
    graph = { { c('Widen window to show heatmap', 'Muted') } }
  else
    local month_names = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
    local months, last, previous_col = { pad(3) }, '', -5
    local offset = 3
    for w = 1, weeks do
      local date = (days[start + (w - 1) * 7 + 1] or {}).date or ''
      local month = tonumber(date:sub(6, 7))
      local col = 3 + (w - 1) * 2
      if month and month ~= last and col - previous_col >= 5 and col + 3 <= graphwidth then
        months[#months + 1] = pad(col - offset)
        months[#months + 1] = c(month_names[month], 'Muted')
        offset, previous_col, last = col + 3, col, month
      end
    end
    graph[1] = fit(months, graphwidth)
    local date = (days[start + 1] or {}).date or ''
    local yy, mm, dd = date:match '(%d+)%-(%d+)%-(%d+)'
    local first = yy and tonumber(os.date('%w', os.time { year = tonumber(yy), month = tonumber(mm), day = tonumber(dd), hour = 12 })) or 0
    local labels = { 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa' }
    for d = 1, 7 do
      local weekday = (first + d - 1) % 7
      local row = { c((weekday % 2 == 1 and labels[weekday + 1] or '  ') .. ' ', 'Muted') }
      for w = 1, weeks do
        local day = days[start + (w - 1) * 7 + d] or {}
        local count = scope == 'you' and (day.mine or 0) or (day.count or 0)
        local level = count == 0 and 0 or count < 2 and 1 or count < 4 and 2 or count < 7 and 3 or 4
        row[#row + 1] = c('■ ', 'Heat' .. level)
      end
      graph[#graph + 1] = row
    end
    graph[#graph + 1] = pair(
      {},
      { c('Less ', 'Muted'), c('■ ', 'Heat0'), c('■ ', 'Heat1'), c('■ ', 'Heat2'), c('■ ', 'Heat3'), c('■ ', 'Heat4'), c('More', 'Muted') },
      graphwidth
    )
  end
  if side then
    return U.grid_col {
      { lines = vim.tbl_map(function(r) return fit(r, leftwidth) end, left), w = leftwidth, pad = 3 },
      { lines = vim.tbl_map(function(r) return fit(r, graphwidth) end, graph), w = graphwidth },
    }
  end
  return U.grid_row { left, { {} }, graph }
end
function M.render(model, width, height)
  require('project_home_volt.theme').apply()
  width, height = width or 120, height or 50
  local canvas = math.min(144, math.max(20, width - 8))
  if width < 28 then canvas = math.max(1, width - 2) end
  local margin = math.max(0, math.floor((width - canvas) / 2))
  local tall = height >= 47 and canvas >= 70
  local header = { {} }
  if tall then
    for _, line in ipairs {
      '█▄  █  █   █  ▀▀█▀▀  █▄ ▄█',
      '█ ▀▄█  ▀▄ ▄▀    █    █ ▀ █',
      '▀   ▀    ▀    ▀▀▀▀▀  ▀   ▀',
    } do
      header[#header + 1] = { c(line, 'Accent') }
    end
  end
  header[#header + 1] = pair({ c(model.name or model.title or 'Project', 'Title') }, { c(model.branch or 'No branch', 'Accent') }, canvas)
  local path = model.root or ''
  local home = vim.env.HOME or ''
  if home ~= '' and path:sub(1, #home + 1) == home .. '/' then path = '~' .. path:sub(#home + 1) end
  local git = model.git or {}
  header[#header + 1] = pair(
    { c(path, 'Muted') },
    { c(git.upstream and ('Current worktree · ↑%d ↓%d'):format(git.ahead or 0, git.behind or 0) or 'Current worktree', 'Muted') },
    canvas
  )
  header[#header + 1] = U.separator('─', canvas, 'ProjectHomeVoltRule')
  local toolbar, row = {}, {}
  local buttons = { { 'f', 'Find', 'find' }, { '/', 'Search', 'search' }, { 'e', 'Browse', 'browse' }, { 'n', 'New', 'new' }, { '?', 'Help', 'keyboard_help' } }
  if (model.session or model.resume) and model.has_session ~= false then table.insert(buttons, 1, { 'u', 'Resume', 'resume' }) end
  for _, button in ipairs(buttons) do
    local buttonwidth = #button[2] + 5
    if U.line_w(row) + buttonwidth > canvas and #row > 0 then
      toolbar[#toolbar + 1] = row
      row = {}
    end
    if button[1] == '?' then row[#row + 1] = pad(canvas - U.line_w(row) - 6) end
    row[#row + 1] = action(button[1], button[3], button[1], 'actions', nil, 'Accent')
    row[#row + 1] = action(' ' .. button[2], button[3], nil, 'actions')
    row[#row + 1] = c '   '
  end
  toolbar[#toolbar + 1] = row
  toolbar[#toolbar + 1] = U.separator('─', canvas, 'ProjectHomeVoltRule')
  toolbar[#toolbar + 1] = {}
  local body
  if canvas >= 72 then
    local left = math.floor((canvas - 7) / 2)
    local a, b = files(model, left), repository(model, canvas - left - 7)
    local divider = {}
    for _ = 1, math.max(#a, #b) do
      divider[#divider + 1] = { c('│', 'Rule') }
    end
    body = U.grid_col { { lines = a, w = left, pad = 3 }, { lines = divider, w = 1, pad = 3 }, { lines = b, w = canvas - left - 7 } }
  else
    body = U.grid_row { files(model, canvas), { {}, U.separator('─', canvas, 'ProjectHomeVoltRule'), {} }, repository(model, canvas) }
  end
  local sections = { { name = 'header', lines = header }, { name = 'actions', lines = toolbar }, { name = 'workspace', lines = body } }
  if model.show_activity ~= false then
    sections[#sections + 1] =
      { name = 'activity', lines = U.grid_row { { {}, U.separator('─', canvas, 'ProjectHomeVoltRule'), {} }, activity(model, canvas) } }
  end
  sections[#sections + 1] = { name = 'footer', lines = { {}, { c('r recent · x explore · p PRs · g Git · Tab sections · ? help', 'Muted') } } }
  for _, section in ipairs(sections) do
    section.lines = vim.tbl_map(function(r)
      local line = { pad(margin) }
      vim.list_extend(line, fit(r, canvas))
      return line
    end, section.lines)
  end
  return require('project_home_volt.renderer').page(sections, width)
end
return M
