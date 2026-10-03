-- Workspace follows the approved two-column composition rather than a text dump.
local L = require 'project_home.layout'
local M = {}
local function block(width)
  local b = { width = width, rows = {} }
  function b:row(n)
    self.rows[n] = self.rows[n] or { parts = {}, backgrounds = {} }
    return self.rows[n]
  end
  function b:put(n, col, text, group, action, value, key, limit)
    local max = math.min(limit or self.width - col, self.width - col)
    text = L.clip(text, max)
    if text == '' then
      self:row(n)
      return
    end
    local part = { col = col, text = text, group = group or 'ProjectHomeWorkspaceText', action = action, value = value, key = key }
    table.insert(self:row(n).parts, part)
    return part
  end
  function b:bg(n, col, span, group) table.insert(self:row(n).backgrounds, { col = col, span = span, group = group }) end
  function b:rule(n) self:put(n, 0, string.rep('─', self.width), 'ProjectHomeWorkspaceBorder') end
  function b:pair(n, left, right, leftgroup, rightgroup, action, value, key)
    local rightwidth = math.min(L.width(right), math.floor(self.width * 0.52))
    self:put(n, 0, left, leftgroup, nil, nil, nil, self.width - rightwidth - 2)
    self:put(n, self.width - rightwidth, right, rightgroup, action, value, key, rightwidth)
  end
  function b:merge(other, line, col)
    for n, row in pairs(other.rows) do
      for _, p in ipairs(row.parts) do
        local copied = self:put(line + n - 1, col + p.col, p.text, p.group, p.action, p.value, p.key, other.width - p.col)
        if copied then
          copied.span = p.span
          copied.end_line = p.end_line and line + p.end_line - 1 or nil
        end
      end
      for _, bg in ipairs(row.backgrounds) do
        self:bg(line + n - 1, col + bg.col, bg.span, bg.group)
      end
    end
  end
  function b:height()
    local count = 0
    for n in pairs(self.rows) do
      count = math.max(count, n)
    end
    return count
  end
  return b
end
local function file_parts(file, root)
  local path = type(file) == 'table' and file.path or file
  path = tostring(path or '')
  local relative = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2) or path
  local leaf = relative:gsub('/$', ''):match '[^/]+$' or relative
  local directory = path:sub(-1) == '/' or vim.fn.isdirectory(path) == 1 or vim.fn.isdirectory(root .. '/' .. path) == 1
  local parent = relative:match '^(.*)/[^/]+$'
  if directory then leaf = leaf .. '/' end
  return leaf, parent and parent .. '/' or 'Project root', path, relative
end
local function shortcuts_description(relative, width)
  local lower = relative:lower():gsub('/$', '')
  if lower:match 'readme' then return 'Project guide' end
  if lower == 'init.lua' then return width < 25 and 'Config entry' or 'Configuration entry point' end
  if lower == 'lua' then return width < 22 and 'Modules' or 'Configuration modules' end
  if lower:match '^docs?' then return width < 20 and 'Documentation' or 'Guides and workflows' end
  if lower == 'src' or lower == 'lib' then return 'Source files' end
  if lower:match 'test' then return 'Tests and checks' end
  return 'Project shortcut'
end
local function left_column(model, width, compact)
  local b = block(width)
  b:put(1, 0, 'RECENT FILES', 'ProjectHomeWorkspaceHeading', 'recents', nil, 'r')
  local session = model.session or model.resume
  if session and model.has_session ~= false then
    for row = 2, 4 do
      b:bg(row, 0, width, 'ProjectHomeResume')
      b:put(row, 0, '│', 'ProjectHomeWorkspaceAccent')
    end
    b:put(3, 2, '> Resume workspace', 'ProjectHomeWorkspaceAccent', 'resume', nil, nil, width)
    if width >= 49 then b:put(3, width - 22, 'saved splits + cursors', 'ProjectHomeMuted') end
  else
    b:bg(3, 0, width, 'ProjectHomeSurface')
    b:put(3, 2, 'No saved workspace yet', 'ProjectHomeMuted')
  end
  local recents, line = model.recents or {}, 6
  if #recents == 0 then
    b:put(line, 1, 'No files opened in this project yet', 'ProjectHomeMuted')
    line = line + 2
  else
    for index, file in ipairs(recents) do
      if index > 5 then break end
      local leaf, parent, path = file_parts(file, model.root or '')
      local reserve = index == 1 and width >= 43 and 13 or 0
      local item = b:put(line, 1, leaf, 'ProjectHomeFile', 'file', path, nil, width - reserve - 1)
      if item then
        item.end_line, item.span = line + 1, width - 2
      end
      if reserve > 0 then b:put(line, width - 11, 'last opened', 'ProjectHomeMuted') end
      b:put(line + 1, 1, parent, 'ProjectHomeMuted')
      line = line + 2
    end
  end
  local exploreline = line + (compact and 0 or 1)
  b:pair(exploreline, 'START EXPLORING', 'Edit shortcuts', 'ProjectHomeWorkspaceHeading', 'ProjectHomeMuted', 'shortcuts', nil, 's')
  line = exploreline + (compact and 1 or 2)
  local shortcuts = model.shortcuts or {}
  if #shortcuts == 0 then
    b:put(line, 1, 'Add your first shortcut', 'ProjectHomeWorkspaceAccent', 'shortcuts')
  else
    local cell = math.floor((width - 3) / 2)
    for index, file in ipairs(shortcuts) do
      if index > 5 then break end
      local leaf, _, path, relative = file_parts(file, model.root or '')
      local col = (index - 1) % 2 == 0 and 1 or cell + 3
      local row = line + math.floor((index - 1) / 2) * 3
      local item = b:put(row, col, leaf, 'ProjectHomeFile', 'file', path, nil, cell)
      if item then
        item.end_line, item.span = row + 1, cell
      end
      b:put(row + 1, col, shortcuts_description(relative, cell), 'ProjectHomeMuted', nil, nil, nil, cell)
    end
  end
  return b
end
local function right_column(model, width, compact)
  local b, git = block(width), model.git or {}
  b:put(1, 0, 'GIT WORKSPACE', 'ProjectHomeWorkspaceHeading')
  if git.loading then
    b:put(3, 0, 'Loading local Git…', 'ProjectHomeMuted')
    return b
  end
  if git.error then
    b:put(3, 0, 'Git status unavailable', 'ProjectHomeWarning')
    b:put(4, 0, 'R Retry Git status', 'ProjectHomeWorkspaceAccent', 'refresh', nil, 'R')
    return b
  end
  if git.available == false then
    b:put(3, 0, 'Not a Git repository', 'ProjectHomeMuted')
    return b
  end
  b:put(3, 0, 'g  ' .. #(git.changes or {}) .. ' changed files', 'ProjectHomeWorkspaceText', 'git', nil, 'g')
  local summary = ('%d staged · %d unstaged · %d untracked'):format(git.staged or 0, git.unstaged or 0, git.untracked or 0)
  if L.width(summary) > width - 3 then
    b:put(4, 3, ('%d staged · %d unstaged'):format(git.staged or 0, git.unstaged or 0), 'ProjectHomeMuted')
    b:put(5, 3, ('%d untracked'):format(git.untracked or 0), 'ProjectHomeMuted')
  else
    b:put(4, 3, summary, 'ProjectHomeMuted')
  end
  local latest = git.latest
  if latest then
    b:put(6, 0, (latest.hash or ''):sub(1, 7) .. '  ' .. (latest.subject or ''), 'ProjectHomeMuted', 'commit', latest.hash, 'c')
    local date = latest.date and latest.date:sub(1, 10)
    if date == os.date '%Y-%m-%d' then date = 'today' end
    b:put(7, 0, 'Latest commit' .. (date and ' · ' .. date or ''), 'ProjectHomeMuted')
  else
    b:put(6, 0, 'No commits yet', 'ProjectHomeMuted')
  end
  b:rule(compact and 8 or 9)
  local prs = (model.prs or {}).items or model.prs or {}
  b:pair(compact and 9 or 11, 'PULL REQUESTS', 'View all · ' .. #prs, 'ProjectHomeWorkspaceHeading', 'ProjectHomeMuted', 'prs', nil, 'p')
  local statuses = {}
  local rows = L.git(model)
  for i, row in ipairs(rows) do
    if row.action == 'pr' then statuses[row.value] = rows[i + 1] end
  end
  local line = compact and 11 or 13
  if #prs == 0 then
    local state = (model.prs or {}).status
    b:put(
      line,
      0,
      state == 'loading' and 'Loading pull requests…' or state == 'unavailable' and 'Remote status unavailable' or 'No pull requests to show',
      'ProjectHomeMuted'
    )
    line = line + 3
  else
    for i, pr in ipairs(prs) do
      if i > 3 then break end
      local item = b:put(line, 0, 'PR #' .. pr.number .. '  ' .. (pr.title or ''), 'ProjectHomeWorkspaceText', 'pr', pr.number)
      if item then
        item.end_line, item.span = line + 1, width
      end
      local status = statuses[pr.number]
      if status then
        local text = vim.trim(status.text)
        if width < 40 then text = text:gsub('Checks failed', 'Failed'):gsub('Checks passed', 'Passed'):gsub('Checks unknown', 'Unknown checks') end
        b:put(line + 1, 0, text, status.group)
      end
      line = line + 3
    end
  end
  if model.worktrees_error then
    b:put(line, 0, 'Worktrees unavailable →', 'ProjectHomeWarning', 'worktrees', nil, 'w')
  else
    b:put(line, 0, 'Worktrees →', 'ProjectHomeWorkspaceText', 'worktrees', nil, 'w')
    local context = #(model.worktrees or {}) .. ' checkouts'
    if width >= 54 then context = context .. ' · ' .. (model.branch or '') end
    local countwidth = math.min(L.width(context), width - 15)
    b:put(line, width - countwidth, context, 'ProjectHomeMuted', nil, nil, nil, countwidth)
  end
  return b
end
local function activity(model, width)
  local b, data = block(width), model.activity or {}
  local scope = model.scope or 'repo'
  local graphwidth = 52
  local split = width >= 70
  local graphcol = split and width - graphwidth or 0
  local graphline = split and 1 or 10
  b:put(1, 0, width < 87 and 'ACTIVITY' or 'REPOSITORY ACTIVITY', 'ProjectHomeWorkspaceHeading')
  b:put(3, 0, width < 87 and 'All branches · 26w' or 'All branches · last 26 weeks', 'ProjectHomeMuted')
  b:bg(5, 0, 12, scope == 'repo' and 'ProjectHomeResume' or 'ProjectHomeSurface')
  b:bg(5, 12, 8, scope == 'you' and 'ProjectHomeResume' or 'ProjectHomeSurface')
  b:put(5, 1, 'Repository', scope == 'repo' and 'ProjectHomeWorkspaceAccent' or 'ProjectHomeMuted', 'activity', 'repo', scope == 'you' and 'a' or nil)
  b:put(5, 13, 'Yours', scope == 'you' and 'ProjectHomeWorkspaceAccent' or 'ProjectHomeMuted', 'activity', 'you', scope == 'repo' and 'a' or nil)
  local unavailable = data.status == 'unavailable'
  local missing = scope == 'you' and (not data.identity or data.identity == '')
  local loading = data.status == 'loading'
  local total = scope == 'you' and (data.mine_total or 0) or (data.total or 0)
  local meta = loading and 'Loading activity…'
    or unavailable and 'Activity unavailable'
    or missing and 'Set git user.email for your activity'
    or tostring(total) .. (total == 1 and ' commit' or ' commits')
  b:put(7, 0, meta, unavailable and 'ProjectHomeWarning' or 'ProjectHomeMuted', nil, nil, nil, split and graphcol - 3 or width)
  b:put(8, 0, unavailable and 'Retry activity →' or 'View history →', 'ProjectHomeWorkspaceText', unavailable and 'refresh' or 'history', nil, 'h')
  if not loading and not unavailable and not missing then
    if width < 52 then
      b:put(graphline, 0, 'Widen window for activity graph', 'ProjectHomeMuted')
      return b
    end
    local days = data.days or {}
    local weeks = math.min(26, math.ceil(#days / 7))
    local start = math.max(0, #days - weeks * 7)
    local month_names = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
    local previous = ''
    for week = 1, weeks do
      local entry = days[start + (week - 1) * 7 + 1] or {}
      local month = tostring(entry.date or ''):sub(6, 7)
      if month ~= '' and month ~= previous and week * 2 < graphwidth - 1 then
        b:put(graphline, graphcol + (week - 1) * 2, month_names[tonumber(month)] or '', 'ProjectHomeMuted')
        previous = month
      end
      for day = 1, 7 do
        local item = days[start + (week - 1) * 7 + day] or {}
        local count = scope == 'you' and (item.mine or 0) or (item.count or 0)
        local level = count == 0 and 0 or count < 2 and 1 or count < 4 and 2 or count < 7 and 3 or 4
        b:put(graphline + day, graphcol + (week - 1) * 2, '■', 'ProjectHomeActivity' .. level)
      end
    end
    local legendcol = graphcol + 29
    b:put(graphline + 8, legendcol, 'Less', 'ProjectHomeMuted')
    for level = 0, 4 do
      b:put(graphline + 8, legendcol + 5 + level * 2, '■', 'ProjectHomeActivity' .. level)
    end
    b:put(graphline + 8, legendcol + 16, 'More', 'ProjectHomeMuted')
  end
  return b
end
local function finish(b, margin, top)
  local result = { lines = {}, highlights = {}, items = {}, presentation = 'workspace', cursorline = false }
  for _ = 1, top do
    result.lines[#result.lines + 1] = ''
  end
  local prefix = string.rep(' ', margin)
  for n = 1, b:height() do
    local row = b.rows[n] or { parts = {}, backgrounds = {} }
    table.sort(row.parts, function(a, c) return a.col < c.col end)
    local text, display = '', 0
    local positions = {}
    for _, part in ipairs(row.parts) do
      if part.col >= display then
        text = text .. string.rep(' ', part.col - display)
        positions[#positions + 1] = { part = part, byte = #text }
        text = text .. part.text
        display = part.col + L.width(part.text)
      end
    end
    text = text .. string.rep(' ', math.max(0, b.width - display))
    result.lines[#result.lines + 1] = prefix .. text .. '  '
    local line = #result.lines
    local function byte_at(col)
      if col < 0 then return margin + col end
      local byte, cell = 0, 0
      for i = 0, vim.fn.strchars(text) - 1 do
        if cell >= col then return byte + margin end
        local char = vim.fn.strcharpart(text, i, 1)
        byte = byte + #char
        cell = cell + L.width(char)
      end
      return byte + margin + math.max(0, col - b.width)
    end
    result.highlights[#result.highlights + 1] = { line = line, start_col = math.max(0, margin - 2), end_col = #prefix + #text + 2, group = 'ProjectHomeCanvas' }
    for _, bg in ipairs(row.backgrounds) do
      result.highlights[#result.highlights + 1] = { line = line, start_col = byte_at(bg.col), end_col = byte_at(bg.col + bg.span), group = bg.group }
    end
    for _, position in ipairs(positions) do
      local part, col = position.part, position.byte + margin
      result.highlights[#result.highlights + 1] = { line = line, start_col = col, end_col = col + #part.text, group = part.group }
      if part.key and part.text:sub(1, #part.key) == part.key then
        result.highlights[#result.highlights + 1] = { line = line, start_col = col, end_col = col + #part.key, group = 'ProjectHomeWorkspaceAccent' }
      end
      if part.action then
        local item = {
          line = line,
          col = col,
          end_col = part.span and byte_at(part.col + part.span) or col + #part.text,
          end_line = part.end_line and top + part.end_line or nil,
          label = part.text,
          action = part.action,
          value = part.value,
          key = part.key,
        }
        result.items[#result.items + 1] = item
        if part.action == 'resume' then result.initial_focus = item end
      end
    end
  end
  return result
end
function M.render(model, width, height)
  width, height = width or 120, height or 50
  local canvas = math.min(124, math.max(30, width - 8))
  local margin = math.max(0, math.floor((width - canvas) / 2))
  local compact = height < 47
  local top = compact and 1 or height >= 64 and 4 or 2
  local b = block(canvas)
  local title = model.name or model.title or 'Project'
  b:bg(1, -2, canvas + 4, 'ProjectHomeSurface')
  b:put(1, 2, 'WORKSPACE / NEOVIM', 'ProjectHomeWorkspaceAccent')
  b:put(1, canvas - 14, 'Project home', 'ProjectHomeMuted')
  b:pair(3, title, model.branch or '', 'ProjectHomeWorkspaceTitle', 'ProjectHomeWorkspaceAccent')
  local path = model.root or ''
  local home = vim.env.HOME or ''
  if home ~= '' and path:sub(1, #home + 1) == home .. '/' then path = '~' .. path:sub(#home + 1) end
  local git = model.git or {}
  local context = 'Current worktree'
  if git.upstream then context = context .. (' · ↑%s ↓%s'):format(git.ahead or 0, git.behind or 0) end
  b:pair(4, path, context, 'ProjectHomeMuted', 'ProjectHomeMuted')
  b:rule(compact and 5 or 6)
  local actions = { { 'f Find file', 'find', 'f' }, { '/ Search text', 'search', '/' }, { 'e Browse', 'browse', 'e' }, { 'n New file', 'new', 'n' } }
  local col, actionline = 0, compact and 6 or 7
  for _, a in ipairs(actions) do
    if col + #a[1] > canvas - 9 then
      col = 0
      actionline = actionline + 1
    end
    b:put(actionline, col, a[1], 'ProjectHomeWorkspaceText', a[2], nil, a[3])
    col = col + #a[1] + 3
  end
  b:put(compact and 6 or 7, canvas - 6, '? More', 'ProjectHomeMuted', 'more', nil, '?')
  b:rule(actionline + 1)
  local bodyline = actionline + (compact and 2 or 3)
  local bodyend
  if canvas >= 70 then
    local lw = math.floor((canvas - 7) / 2)
    local rw = canvas - lw - 7
    local left, right = left_column(model, lw, compact), right_column(model, rw, compact)
    b:merge(left, bodyline, 0)
    b:merge(right, bodyline, lw + 7)
    local bodyheight = math.max(left:height(), right:height())
    for line = bodyline, bodyline + bodyheight - 1 do
      b:put(line, lw + 3, '│', 'ProjectHomeWorkspaceBorder')
    end
    bodyend = bodyline + bodyheight
  else
    local left, right = left_column(model, canvas, compact), right_column(model, canvas, compact)
    b:merge(left, bodyline, 0)
    local second = bodyline + left:height() + 2
    b:rule(second - 1)
    b:merge(right, second + 1, 0)
    bodyend = second + right:height() + 1
  end
  if model.show_activity ~= false then
    b:rule(bodyend + 1)
    local section = activity(model, canvas)
    b:merge(section, bodyend + 3, 0)
    bodyend = bodyend + 3 + section:height()
  end
  b:bg(bodyend + 1, -2, canvas + 4, 'ProjectHomeSurface')
  b:put(bodyend + 1, 2, 'Project-local files · repository-wide activity', 'ProjectHomeMuted', nil, nil, nil, canvas - 38)
  b:put(bodyend + 1, canvas - 30, 'R refresh · ? all actions', 'ProjectHomeMuted', 'refresh', nil, 'R')
  return finish(b, margin, top)
end
return M
