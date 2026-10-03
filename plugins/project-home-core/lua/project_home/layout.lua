-- Display-width-aware layout primitives. No terminal colors are hardcoded.
local M = {}
local function width(s) return vim.fn.strdisplaywidth(s or '') end
M.width = width
function M.clip(s, limit)
  s = tostring(s or ''):gsub('[\r\n\t]', ' ')
  if limit <= 0 then return '' end
  if width(s) <= limit then return s end
  local out = ''
  for i = 0, vim.fn.strchars(s) - 1 do
    local c = vim.fn.strcharpart(s, i, 1)
    if width(out .. c) > limit - 1 then break end
    out = out .. c
  end
  return out .. '…'
end
function M.row(text, group, action, value, key)
  return { text = tostring(text or ''), group = group or 'ProjectHomeNormal', action = action, value = value, key = key }
end
function M.add(rows, text, group, action, value, key) rows[#rows + 1] = M.row(text, group, action, value, key) end
function M.blank(rows) M.add(rows, '') end
function M.heading(rows, text) M.add(rows, text, 'ProjectHomeMuted') end
function M.rule(rows, w) M.add(rows, string.rep('─', math.max(0, w)), 'ProjectHomeBorder') end
function M.section(rows, text)
  M.blank(rows)
  M.heading(rows, text)
end
function M.file_label(file)
  local path = type(file) == 'table' and (file.path or file.label or '') or tostring(file)
  local label = type(file) == 'table' and file.label or nil
  if label and label:find '/' then label = label:gsub('/$', ''):match '[^/]+$' end
  if not label or label == '' or label == path then label = path:gsub('/$', ''):match '[^/]+$' or path end
  local directory = path:sub(-1) == '/' or (type(file) == 'table' and (file.is_dir or file.type == 'directory')) or vim.fn.isdirectory(path) == 1
  if directory and label:sub(-1) ~= '/' then label = label .. '/' end
  return label, path
end
function M.file_rows(rows, files, limit, empty, root)
  if #files == 0 then
    M.add(rows, empty or 'No recent files yet', 'ProjectHomeMuted')
    return
  end
  for i, file in ipairs(files) do
    if i > limit then break end
    local label, path = M.file_label(file)
    local parent = ''
    if root then
      local relative = path:sub(1, #root + 1) == root .. '/' and path:sub(#root + 2) or path
      parent = relative:match '^(.*)/[^/]+$' or ''
    end
    M.add(rows, '  ' .. label .. (parent ~= '' and (' · ' .. parent) or ''), nil, 'file', path)
  end
end
function M.recents(model)
  local rows = {}
  M.heading(rows, 'RECENT FILES')
  M.file_rows(rows, model.recents or {}, 5, 'No files opened in this project yet', model.root or '')
  M.add(rows, '  All recent files →', 'ProjectHomeAccent', 'recents', nil, 'r')
  return rows
end
function M.explore(model)
  local rows = {}
  M.heading(rows, 'START EXPLORING')
  M.file_rows(rows, model.shortcuts or {}, 5, 'Add your first shortcut')
  M.add(rows, '  Edit shortcuts →', 'ProjectHomeAccent', 'shortcuts', nil, 's')
  return rows
end
function M.resume(model)
  -- Backend supplies session availability; absent state never promises a restore.
  local session = model.session or model.resume
  if not session or model.has_session == false then return M.row('  No saved workspace yet', 'ProjectHomeMuted') end
  return M.row('> Resume workspace', 'ProjectHomeAccent', 'resume')
end
function M.git(model)
  local rows = {}
  local git = model.git or {}
  M.heading(rows, 'GIT WORKSPACE')
  if git.loading then
    M.add(rows, 'Loading local Git…', 'ProjectHomeMuted')
    return rows
  end
  if git.error then
    M.add(rows, 'Git status unavailable', 'ProjectHomeWarning')
    M.add(rows, 'R  Retry Git status', 'ProjectHomeAccent', 'refresh', nil, 'R')
    return rows
  end
  if git.available == false or git.is_repo == false or model.is_git == false then
    M.add(rows, 'Not a Git repository', 'ProjectHomeMuted')
    return rows
  end
  local changes = git.changes or {}
  local total = type(changes) == 'number' and changes or (changes.total or changes.count or #changes)
  if total == 0 then total = git.changed_count or 0 end
  M.add(rows, 'g  ' .. total .. ' changed files', total > 0 and 'ProjectHomeAccent' or 'ProjectHomeMuted', 'git', nil, 'g')
  local staged = type(changes) == 'table' and changes.staged or git.staged
  local unstaged = type(changes) == 'table' and changes.unstaged or git.unstaged
  local untracked = type(changes) == 'table' and changes.untracked or git.untracked
  local function n(v) return type(v) == 'table' and #v or tonumber(v) or 0 end
  if staged or unstaged or untracked then
    M.add(rows, ('   %d staged · %d unstaged · %d untracked'):format(n(staged), n(unstaged), n(untracked)), 'ProjectHomeMuted')
  end
  local latest = git.latest or model.latest_commit
  if latest then
    local text = type(latest) == 'table'
        and ((latest.short_hash or latest.hash or latest.sha or ''):sub(1, 7) .. '  ' .. (latest.subject or latest.title or latest.message or ''))
      or tostring(latest)
    M.add(rows, text, 'ProjectHomeMuted', 'commit', type(latest) == 'table' and (latest.hash or latest.sha) or nil, 'c')
  end
  M.blank(rows)
  M.heading(rows, 'PULL REQUESTS')
  local prs = model.prs or {}
  if prs.items then prs = prs.items end
  if #prs == 0 then
    local state = (model.prs or {}).status
    M.add(
      rows,
      state == 'loading' and 'Loading pull requests…' or state == 'unavailable' and 'Remote status unavailable' or 'No pull requests to show',
      'ProjectHomeMuted'
    )
  end
  for i, pr in ipairs(prs) do
    if i > 3 then break end
    local number = pr.number or pr.id or i
    M.add(rows, ('PR #%s  %s'):format(number, pr.title or ''), nil, 'pr', number)
    local checks, failed, pending = pr.statusCheckRollup or {}, false, false
    local unknown, neutral = false, false
    local failures = { FAILURE = true, ERROR = true, TIMED_OUT = true, CANCELLED = true, ACTION_REQUIRED = true, STARTUP_FAILURE = true, STALE = true }
    for _, check in ipairs(checks) do
      local conclusion = check.conclusion or check.state or ''
      if failures[conclusion] then
        failed = true
      elseif conclusion == '' or conclusion == 'PENDING' or check.status == 'IN_PROGRESS' or check.status == 'QUEUED' then
        pending = true
      elseif conclusion == 'NEUTRAL' or conclusion == 'SKIPPED' then
        neutral = true
      elseif conclusion ~= 'SUCCESS' then
        unknown = true
      end
    end
    local checklabel = failed and 'Checks failed'
      or pending and 'Checks pending'
      or (unknown or #checks == 0) and 'Checks unknown'
      or neutral and 'Checks complete'
      or 'Checks passed'
    local review = pr.isDraft and 'Draft'
      or pr.reviewDecision == 'CHANGES_REQUESTED' and 'Changes requested'
      or pr.reviewDecision == 'APPROVED' and 'Approved'
      or 'Review pending'
    local status = pr.status or (checklabel .. ' · ' .. review)
    if type(status) == 'table' then status = status.label or '' end
    if status ~= '' then
      local failed = status:lower():match 'fail' or status:lower():match 'changes.requested'
      M.add(rows, '  ' .. status, failed and 'ProjectHomeWarning' or 'ProjectHomeMuted')
    end
  end
  M.add(rows, 'p  View all pull requests →', 'ProjectHomeAccent', 'prs', nil, 'p')
  M.blank(rows)
  local worktrees = model.worktrees or git.worktrees or {}
  if model.worktrees_error then
    M.add(rows, 'w  Worktrees unavailable →', 'ProjectHomeWarning', 'worktrees', nil, 'w')
  else
    M.add(rows, ('w  Worktrees · %d →'):format(#worktrees), 'ProjectHomeAccent', 'worktrees', nil, 'w')
  end
  return rows
end
function M.header(model, width_limit, name)
  local rows = {}
  M.add(rows, (model.title or model.name or 'Project') .. '  /  ' .. name, 'ProjectHomeTitle')
  M.add(rows, M.clip(model.root or '', width_limit), 'ProjectHomeMuted')
  local branch = model.branch or (model.git or {}).branch
  if branch and branch ~= '' then
    local ahead = model.ahead or (model.git or {}).ahead or 0
    local behind = model.behind or (model.git or {}).behind or 0
    local upstream = (model.git or {}).upstream
    M.add(rows, tostring(branch) .. (upstream and ('  ↑%s ↓%s'):format(ahead, behind) or '  · no upstream'), 'ProjectHomeAccent')
  end
  M.blank(rows)
  return rows
end
function M.actions(width_limit)
  local actions =
    { { 'f Find file', 'find', 'f' }, { '/ Search', 'search', '/' }, { 'e Browse', 'browse', 'e' }, { 'n New file', 'new', 'n' }, { '? More', 'more', '?' } }
  local rows = {}
  -- Multiple selectable actions are represented as segments on one terminal line.
  local row = { text = '', segments = {} }
  for _, a in ipairs(actions) do
    local gap = row.text == '' and '' or '   '
    if width(row.text .. gap .. a[1]) > width_limit and row.text ~= '' then
      rows[#rows + 1] = row
      row = { text = '', segments = {} }
      gap = ''
    end
    local col = #row.text + #gap
    row.text = row.text .. gap .. a[1]
    row.segments[#row.segments + 1] = { text = a[1], col = col, action = a[2], key = a[3], group = 'ProjectHomeAccent' }
  end
  if row.text ~= '' then rows[#rows + 1] = row end
  M.blank(rows)
  return rows
end
function M.activity(model, width_limit)
  local rows = {}
  local activity = model.activity or {}
  M.heading(rows, 'REPOSITORY ACTIVITY')
  local scope = model.scope or activity.scope or 'repo'
  M.add(rows, (scope == 'you' and 'Repository / [Yours]' or '[Repository] / Yours'), 'ProjectHomeAccent', 'activity', scope == 'you' and 'repo' or 'you', 'a')
  if activity.loading or activity.status == 'loading' then
    M.add(rows, 'Loading local commit history…', 'ProjectHomeMuted')
    return rows
  end
  if activity.status == 'unavailable' then
    M.add(rows, 'Activity unavailable', 'ProjectHomeWarning')
    M.add(rows, 'R  Retry activity', 'ProjectHomeAccent', 'refresh', nil, 'R')
    return rows
  end
  if scope == 'you' and (not activity.identity or activity.identity == '') then
    M.add(rows, 'Set git user.email to show your activity', 'ProjectHomeMuted')
    return rows
  end
  local days = activity.days or activity.counts or {}
  local total = scope == 'you' and (activity.mine_total or 0) or (activity.total or activity.count or 0)
  M.add(
    rows,
    ('%s %s · %s'):format(total, total == 1 and 'commit' or 'commits', activity.label or ('all branches · ' .. math.ceil(#days / 7) .. ' weeks')),
    'ProjectHomeMuted'
  )
  if #days > 0 and width_limit >= 26 then
    local weeks = math.min(math.floor((#days + 6) / 7), math.max(1, width_limit), 26)
    local start = math.max(0, #days - weeks * 7)
    local gap = width_limit >= weeks * 2 - 1 and ' ' or ''
    local chars = { '·', '░', '▒', '▓', '█' }
    local step = gap == '' and 1 or 2
    local graphwidth = weeks * step - #gap
    local dates = {}
    local last_month = ''
    local months = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
    for week = 1, weeks do
      local first = days[start + (week - 1) * 7 + 1]
      local month = type(first) == 'table' and tostring(first.date or ''):sub(6, 7) or ''
      if month ~= '' and month ~= last_month then
        local label = months[tonumber(month)] or ''
        local col = (week - 1) * step
        if col + #label <= graphwidth then dates[#dates + 1] = { text = label, col = col, group = 'ProjectHomeMuted' } end
        last_month = month
      end
    end
    if #dates > 0 then
      local line = string.rep(' ', graphwidth)
      for _, date in ipairs(dates) do
        line = line:sub(1, date.col) .. date.text .. line:sub(date.col + #date.text + 1)
      end
      rows[#rows + 1] = { text = line, segments = dates }
    end
    for day = 1, 7 do
      local cells, highlights = {}, {}
      local bytecol = 0
      for week = 1, weeks do
        local value = days[start + (week - 1) * 7 + day] or 0
        if type(value) == 'table' then value = scope == 'you' and (value.mine or 0) or (value.count or value.commits or 0) end
        local level = value == 0 and 1 or value < 2 and 2 or value < 4 and 3 or value < 7 and 4 or 5
        cells[#cells + 1] = chars[level]
        highlights[#highlights + 1] = { text = chars[level], col = bytecol, group = value == 0 and 'ProjectHomeMuted' or 'ProjectHomeSuccess' }
        bytecol = bytecol + #chars[level] + #gap
      end
      rows[#rows + 1] = { text = table.concat(cells, gap), segments = highlights }
    end
  elseif #days > 0 then
    M.add(rows, 'Widen window for activity graph', 'ProjectHomeMuted')
  elseif activity.loading or activity.status == 'loading' then
    M.add(rows, 'Loading local commit history…', 'ProjectHomeMuted')
  elseif activity.status == 'unavailable' then
    M.add(rows, 'Activity unavailable', 'ProjectHomeMuted')
  else
    M.add(rows, 'No activity in this window', 'ProjectHomeMuted')
  end
  if #days > 0 and width_limit >= 26 then M.add(rows, 'Less · ░ ▒ ▓ █ More', 'ProjectHomeMuted') end
  M.add(rows, 'h  Open commit history →', 'ProjectHomeAccent', 'history', nil, 'h')
  return rows
end
function M.append(target, source)
  for _, row in ipairs(source) do
    target[#target + 1] = row
  end
end
function M.columns(left, right, left_width, right_width, gap)
  gap = gap or 3
  local rows = {}
  for i = 1, math.max(#left, #right) do
    local l, r = left[i] or M.row '', right[i] or M.row ''
    local lt = M.clip(l.text, left_width)
    local pad = string.rep(' ', left_width - width(lt) + gap)
    local text = lt .. pad .. M.clip(r.text, right_width)
    local row = { text = text, segments = {} }
    local function place(part, offset, maxwidth)
      local source = part.segments or { { text = part.text, group = part.group, action = part.action, value = part.value, key = part.key, col = 0 } }
      for _, segment in ipairs(source) do
        if width(part.text:sub(1, segment.col or 0)) < maxwidth then
          local copied = vim.tbl_extend('force', {}, segment)
          copied.col = offset + (segment.col or 0)
          copied.text = M.clip(segment.text, maxwidth - width(part.text:sub(1, segment.col or 0)))
          row.segments[#row.segments + 1] = copied
        end
      end
    end
    place(l, 0, left_width)
    place(r, #lt + #pad, right_width)
    rows[#rows + 1] = row
  end
  return rows
end
-- Pair local state with collaboration only when both remain readable.
function M.git_columns(model, width_limit, omit_heading)
  local source = M.git(model)
  if omit_heading and source[1] then source[1].text = '' end
  if width_limit < 66 then return source end
  local left, right, side = {}, {}, 'left'
  for _, row in ipairs(source) do
    if row.text == 'PULL REQUESTS' then side = 'right' end
    if row.action == 'worktrees' then side = 'left' end
    if side == 'left' then
      left[#left + 1] = row
    else
      right[#right + 1] = row
    end
  end
  if #right == 0 then return left end
  while right[#right] and right[#right].text == '' do
    table.remove(right)
  end
  local lw = math.max(24, math.floor((width_limit - 3) * 0.40))
  local readable = {}
  for _, row in ipairs(left) do
    if row.text:find('staged', 1, true) and row.text:find('untracked', 1, true) and width(row.text) > lw then
      local line = '  '
      for _, part in ipairs(vim.split(vim.trim(row.text), ' · ', { plain = true })) do
        local separator = line == '  ' and '' or ' · '
        if width(line .. separator .. part) > lw and line ~= '  ' then
          readable[#readable + 1] = M.row(line, row.group)
          line, separator = '  ', ''
        end
        line = line .. separator .. part
      end
      readable[#readable + 1] = M.row(line, row.group)
    else
      readable[#readable + 1] = row
    end
  end
  return M.columns(readable, right, lw, width_limit - lw - 3)
end
function M.pad(page, amount)
  local prefix = string.rep(' ', amount)
  for i, line in ipairs(page.lines) do
    page.lines[i] = prefix .. line
  end
  for _, h in ipairs(page.highlights) do
    h.start_col = h.start_col + amount
    if h.end_col >= 0 then h.end_col = h.end_col + amount end
  end
  for _, item in ipairs(page.items) do
    item.col = (item.col or 0) + amount
  end
  return page
end
function M.finish(rows, width_limit)
  local result = { lines = {}, highlights = {}, items = {} }
  for line, row in ipairs(rows) do
    local text = M.clip(row.text, width_limit)
    result.lines[line] = text
    for _, segment in ipairs(row.segments or { { text = row.text, col = 0, group = row.group, action = row.action, value = row.value, key = row.key } }) do
      local col = segment.col or 0
      if col < #text then
        result.highlights[#result.highlights + 1] =
          { line = line, start_col = col, end_col = math.min(#text, col + #segment.text), group = segment.group or 'ProjectHomeNormal' }
        if segment.action then
          result.items[#result.items + 1] = { line = line, col = col, label = segment.text, action = segment.action, value = segment.value, key = segment.key }
        end
      end
    end
  end
  return result
end
return M
