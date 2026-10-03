local M = {}
local uv = vim.uv
local function trim(s) return vim.trim(s or '') end
local function fields(s)
  local parts = vim.split(s or '', '\0', { plain = true })
  if parts[#parts] == '' then table.remove(parts) end
  return parts
end

-- All external work is asynchronous and argv-based. Opening Home never fetches,
-- stages, checks out, or changes remote state.
local function run(argv, cwd, callback, timeout)
  local cancelled = false
  local process
  local ok, err = pcall(function()
    process = vim.system(argv, {
      cwd = cwd,
      text = false,
      timeout = timeout or 5000,
      env = { GIT_TERMINAL_PROMPT = '0', GH_PROMPT_DISABLED = '1', GH_NO_UPDATE_NOTIFIER = '1', NO_COLOR = '1', LC_ALL = 'C' },
    }, function(result)
      vim.schedule(function()
        if cancelled then return end
        if result.code == 0 then
          callback(result.stdout or '', nil)
        else
          local message = trim(result.stderr)
          if result.code == 124 then message = 'Request timed out' end
          callback(nil, message ~= '' and message or ('Command failed (' .. result.code .. ')'))
        end
      end)
    end)
  end)
  if not ok then vim.schedule(function()
    if not cancelled then callback(nil, tostring(err)) end
  end) end
  return function()
    cancelled = true
    if process then pcall(function() process:kill(15) end) end
  end
end

function M.git(root, args, callback)
  local argv = { 'git', '--no-pager', '-c', 'core.quotepath=false', '-c', 'color.ui=false' }
  vim.list_extend(argv, args)
  return run(argv, root, callback)
end

function M.gh(root, args, callback)
  if vim.fn.executable 'gh' ~= 1 then
    local cancelled = false
    vim.schedule(function()
      if not cancelled then callback(nil, 'GitHub CLI (gh) is not installed') end
    end)
    return function() cancelled = true end
  end
  local argv = { 'gh' }
  vim.list_extend(argv, args)
  return run(argv, root, callback, 8000)
end

local function json_callback(callback)
  return function(output, err)
    if err then return callback(nil, err) end
    local ok, data = pcall(vim.json.decode, output)
    if not ok then return callback(nil, 'Invalid response from GitHub CLI') end
    callback(data)
  end
end

function M.parse_status(output)
  local changes = {}
  local parts = fields(output)
  local i = 1
  while i <= #parts do
    local record = parts[i]
    if #record >= 4 then
      local index, working = record:sub(1, 1), record:sub(2, 2)
      local path = record:sub(4)
      local change = {
        path = path,
        index = index,
        worktree = working,
        staged = index ~= ' ' and index ~= '?' and index ~= '!',
        untracked = index == '?',
        conflict = index == 'U' or working == 'U' or record:sub(1, 2) == 'AA' or record:sub(1, 2) == 'DD',
      }
      if index == 'R' or index == 'C' or working == 'R' or working == 'C' then
        i = i + 1
        change.old_path = parts[i]
      end
      changes[#changes + 1] = change
    end
    i = i + 1
  end
  return changes
end

function M.parse_worktrees(output, root)
  local result, current = {}, nil
  -- -z avoids quoted paths and supports whitespace/newlines in checkout names.
  for _, item in ipairs(fields(output)) do
    local key, value = item:match '^(%S+)%s(.*)$'
    key = key or item
    if key == 'worktree' then
      current = { path = value, current = vim.fs.normalize(value) == vim.fs.normalize(root) }
      result[#result + 1] = current
    elseif current then
      if key == 'branch' then
        current.branch = value:gsub('^refs/heads/', '')
      elseif key == 'HEAD' then
        current.head = value
      elseif key == 'detached' then
        current.branch = '(detached)'
      elseif key == 'locked' then
        current.locked = value or true
      elseif key == 'prunable' then
        current.prunable = value or true
      end
    end
  end
  return result
end

local function parse_log(output)
  local parts, result = fields(output), {}
  for i = 1, #parts - 4, 5 do
    result[#result + 1] = { hash = trim(parts[i]), subject = parts[i + 1], author = parts[i + 2], date = parts[i + 3], email = parts[i + 4] }
  end
  return result
end

local function sort_prs(model)
  local function rank(pr)
    if pr.headRefName == model.branch then return 0 end
    for _, request in ipairs(pr.reviewRequests or {}) do
      if model.prs.user and request.login == model.prs.user then return 1 end
    end
    if model.prs.user and pr.author and pr.author.login == model.prs.user then return 2 end
    return 3
  end
  table.sort(model.prs.items, function(a, b)
    local ar, br = rank(a), rank(b)
    return ar < br or (ar == br and a.number > b.number)
  end)
end

function M.load(cwd, callback)
  cwd = uv.fs_realpath(cwd) or vim.fs.normalize(cwd)
  local model = {
    root = cwd,
    name = vim.fs.basename(cwd),
    branch = '',
    git = { available = false, loading = true, changes = {}, staged = 0, unstaged = 0, modified = 0, untracked = 0 },
    prs = { items = {}, status = 'loading' },
    worktrees = {},
    activity = { days = {}, status = 'loading', total = 0, mine_total = 0 },
  }
  local stopped, pending = false, {}
  local function emit()
    if not stopped then callback(vim.deepcopy(model)) end
  end
  local function track(cancel) pending[#pending + 1] = cancel end
  local function git(args, cb)
    track(M.git(model.root, args, function(out, err)
      if not stopped then cb(out, err) end
    end))
  end
  local function gh(args, cb)
    track(M.gh(model.root, args, function(out, err)
      if not stopped then cb(out, err) end
    end))
  end
  emit()
  track(M.git(cwd, { 'rev-parse', '--show-toplevel' }, function(output, err)
    if stopped then return end
    if err then
      model.git.loading = false
      local non_git = err:lower():find('not a git repository', 1, true) ~= nil
      if not non_git then model.git.error = err end
      model.prs.status, model.prs.error = 'unavailable', non_git and 'No Git repository' or 'Local Git is unavailable'
      model.activity.status = 'unavailable'
      model.activity.error = model.prs.error
      emit()
      return
    end
    model.root = trim(output)
    model.name = vim.fs.basename(model.root)
    model.git.available = true
    emit()
    git({ 'status', '--porcelain=v1', '-z', '--untracked-files=normal' }, function(out, status_err)
      model.git.loading = false
      model.git.error = status_err
      if out then
        model.git.changes = M.parse_status(out)
        for _, change in ipairs(model.git.changes) do
          if change.staged then model.git.staged = model.git.staged + 1 end
          if not change.untracked and change.worktree ~= ' ' then model.git.unstaged = model.git.unstaged + 1 end
          if change.untracked then
            model.git.untracked = model.git.untracked + 1
          else
            model.git.modified = model.git.modified + 1
          end
        end
      end
      emit()
    end)
    git({ 'status', '--porcelain=v2', '--branch', '-z', '--untracked-files=no' }, function(out)
      if out then
        for _, line in ipairs(fields(out)) do
          model.branch = line:match '^# branch.head (.+)$' or model.branch
          model.git.upstream = line:match '^# branch.upstream (.+)$' or model.git.upstream
          local ahead, behind = line:match '^# branch.ab %+(%d+) %-(%d+)'
          if ahead then
            model.git.ahead, model.git.behind = tonumber(ahead), tonumber(behind)
          end
        end
      end
      sort_prs(model)
      emit()
    end)
    git({ 'log', '-1', '-z', '--format=%H%x00%s%x00%an%x00%cI%x00%aE' }, function(out)
      if out then model.git.latest = parse_log(out)[1] end
      emit()
    end)
    git({ 'worktree', 'list', '--porcelain', '-z' }, function(out, wt_err)
      model.worktrees = out and M.parse_worktrees(out, model.root) or {}
      model.worktrees_error = wt_err
      emit()
    end)
    -- Resolve identity first; missing identity must not masquerade as zero activity.
    git({ 'config', '--get', 'user.email' }, function(email)
      model.activity.identity = email and trim(email) ~= '' and trim(email) or nil
      git({ 'log', '--all', '--since=183.days', '-z', '--format=%H%x00%cs%x00%aE' }, function(out, activity_err)
        local now = os.time()
        local index, seen = {}, {}
        for offset = 181, 0, -1 do
          local day = { date = os.date('%Y-%m-%d', now - offset * 86400), count = 0, mine = 0 }
          model.activity.days[#model.activity.days + 1] = day
          index[day.date] = day
        end
        local parts = fields(out)
        for i = 1, #parts - 2, 3 do
          local hash, date, author = trim(parts[i]), parts[i + 1], parts[i + 2]
          if not seen[hash] and index[date] then
            seen[hash] = true
            local day = index[date]
            day.count = day.count + 1
            model.activity.total = model.activity.total + 1
            if model.activity.identity and author:lower() == model.activity.identity:lower() then
              day.mine = day.mine + 1
              model.activity.mine_total = model.activity.mine_total + 1
            end
          end
        end
        model.activity.status = activity_err and 'unavailable' or 'ready'
        model.activity.error = activity_err
        emit()
      end)
    end)
    git({ 'remote', '-v' }, function(remotes)
      if not remotes or remotes == '' then
        model.prs.status, model.prs.error = 'unavailable', 'No remote configured'
        emit()
        return
      end
      gh(
        {
          'pr',
          'list',
          '--state',
          'open',
          '--limit',
          '100',
          '--json',
          'number,title,headRefName,url,isDraft,reviewDecision,statusCheckRollup,author,reviewRequests',
        },
        json_callback(function(prs, pr_err)
          model.prs.status = pr_err and 'unavailable' or 'ready'
          model.prs.error = pr_err
          model.prs.items = type(prs) == 'table' and prs or {}
          sort_prs(model)
          emit()
        end)
      )
      gh({ 'api', 'user', '--jq', '.login' }, function(login)
        model.prs.user = login and trim(login) or nil
        sort_prs(model)
        emit()
      end)
    end)
  end))
  return function()
    stopped = true
    for _, cancel in ipairs(pending) do
      cancel()
    end
  end
end

local function read_untracked(root, path)
  local full = vim.fs.normalize(root .. '/' .. path)
  local canonical = uv.fs_realpath(full)
  local realroot = uv.fs_realpath(root) or root
  if not canonical or (canonical ~= realroot and canonical:sub(1, #realroot + 1) ~= realroot .. '/') then return nil, 'File is outside this checkout' end
  local stat = uv.fs_stat(canonical)
  if not stat or stat.type ~= 'file' then return nil, 'Not a regular file' end
  if stat.size > 512 * 1024 then return 'Untracked file is larger than 512 KiB; open it to inspect.' end
  local ok, lines = pcall(vim.fn.readfile, canonical, '', 500)
  if not ok then return nil, tostring(lines) end
  return 'Untracked: ' .. path .. '\n' .. table.concat(vim.tbl_map(function(line) return '+' .. line end, lines), '\n')
end

function M.gitdiff(root, path, callback)
  if type(path) ~= 'string' or path == '' then
    callback(nil, 'Choose a file')
    return function() end
  end
  local results, errors, count, cancelled = {}, {}, 0, false
  local cancels = {}
  local function done(kind)
    return function(out, err)
      if cancelled then return end
      count = count + 1
      results[kind], errors[kind] = out, err
      if count ~= 2 then return end
      local chunks = {}
      if results.unstaged and results.unstaged ~= '' then chunks[#chunks + 1] = 'Unstaged changes\n' .. results.unstaged end
      if results.staged and results.staged ~= '' then chunks[#chunks + 1] = 'Staged changes\n' .. results.staged end
      if #chunks > 0 then
        callback(table.concat(chunks, '\n'))
      elseif errors.unstaged and errors.staged then
        callback(nil, errors.unstaged)
      else
        cancels[#cancels + 1] = M.git(root, { 'ls-files', '--error-unmatch', '--', path }, function(_, tracked_err)
          if cancelled then return end
          if tracked_err then
            callback(read_untracked(root, path))
          else
            callback 'No textual changes (the file may be binary or have mode-only changes).'
          end
        end)
      end
    end
  end
  cancels[#cancels + 1] = M.git(root, { 'diff', '--no-ext-diff', '--no-textconv', '--', path }, done 'unstaged')
  cancels[#cancels + 1] = M.git(root, { 'diff', '--cached', '--no-ext-diff', '--no-textconv', '--', path }, done 'staged')
  return function()
    cancelled = true
    for _, cancel in ipairs(cancels) do
      cancel()
    end
  end
end

function M.history(root, scope, callback)
  local cancelled, cancels = false, {}
  local function query(email)
    local args = { 'log', '--all', '-n', '100', '-z', '--format=%H%x00%s%x00%an%x00%cI%x00%aE' }
    if scope == 'you' then
      if not email or trim(email) == '' then
        callback(nil, 'Set git user.email to view your activity')
        return
      end
      local escaped = trim(email):gsub('([\x5c%.%[%]%*%^%$])', '\\%1')
      args[#args + 1] = '--author=<' .. escaped .. '>'
      args[#args + 1] = '--regexp-ignore-case'
    end
    cancels[#cancels + 1] = M.git(root, args, function(out, err)
      if not cancelled then callback(out and parse_log(out) or nil, err) end
    end)
  end
  if scope == 'you' then
    cancels[#cancels + 1] = M.git(root, { 'config', '--get', 'user.email' }, function(email)
      if not cancelled then query(email) end
    end)
  else
    query()
  end
  return function()
    cancelled = true
    for _, cancel in ipairs(cancels) do
      cancel()
    end
  end
end

function M.pr_detail(root, number, callback)
  number = tonumber(number)
  if not number or number < 1 or number % 1 ~= 0 then
    callback(nil, 'Invalid PR number')
    return function() end
  end
  return M.gh(
    root,
    { 'pr', 'view', tostring(number), '--json', 'number,title,headRefName,baseRefName,url,body,author,isDraft,reviewDecision,statusCheckRollup,files,reviews' },
    json_callback(callback)
  )
end

return M
