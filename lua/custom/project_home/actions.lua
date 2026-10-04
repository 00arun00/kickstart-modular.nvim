local M = {}
local ui = require 'custom.project_home.ui'
local function provider() return require 'custom.project_home.providers' end
local function notify(err) vim.notify(tostring(err), vim.log.levels.WARN, { title = 'Project home' }) end
local function absolute(ctx, path)
  if not path or path == '' then return ctx.model.root end
  return path:sub(1, 1) == '/' and path or vim.fs.normalize(ctx.model.root .. '/' .. path)
end
local function textpage(ctx, title, text)
  title = tostring(title or ''):gsub('[\r\n\t]', ' ')
  local p = ui.page(title, ctx.model.root, {})
  p.textview = true
  p.lines = { '', '  ' .. title, '  Backspace back · H home · q close', '' }
  p.highlights = { { line = 2, start_col = 2, group = 'ProjectHomeTitle' }, { line = 3, start_col = 2, group = 'ProjectHomeMuted' } }
  for _, line in ipairs(vim.split(text or '', '\n', { plain = true })) do
    p.lines[#p.lines + 1] = '  ' .. line
    if line:sub(1, 1) == '+' then
      p.highlights[#p.highlights + 1] = { line = #p.lines, start_col = 2, group = 'DiffAdd' }
    elseif line:sub(1, 1) == '-' then
      p.highlights[#p.highlights + 1] = { line = #p.lines, start_col = 2, group = 'DiffDelete' }
    end
  end
  ctx.replace(p)
end
local function loading(ctx, title) ctx.show(ui.page(title, 'Loading…', {})) end
local function open_file(ctx, path, line)
  path = absolute(ctx, path)
  if vim.fn.isdirectory(path) == 1 then return M.dispatch(ctx, 'browse', path) end
  local b = vim.fn.bufadd(path)
  vim.fn.bufload(b)
  vim.api.nvim_win_set_buf(ctx.win, b)
  ui.restore_options(ctx)
  if line then pcall(vim.api.nvim_win_set_cursor, ctx.win, { math.max(1, math.min(line, vim.api.nvim_buf_line_count(b))), 0 }) end
end
local function newfile(ctx)
  vim.ui.input(
    { prompt = 'New project-relative file: ' },
    ctx.guard(function(path)
      if not path or path == '' then return end
      local p = absolute(ctx, path)
      if path:sub(1, 1) == '/' or path:sub(-1) == '/' or p:sub(1, #ctx.model.root + 1) ~= ctx.model.root .. '/' then
        notify 'Choose a path inside this project.'
        return
      end
      if (vim.uv or vim.loop).fs_stat(p) then
        notify 'That path already exists. Use Find file to open it.'
        return
      end
      vim.fn.mkdir(vim.fs.dirname(p), 'p')
      open_file(ctx, p)
    end)
  )
end
local function find(ctx)
  local ok, telescope = pcall(require, 'telescope.builtin')
  if ok then
    telescope.find_files { cwd = ctx.model.root, hidden = true }
    return
  end
  vim.ui.input(
    { prompt = 'Open project file: ', default = ctx.model.root .. '/', completion = 'file' },
    ctx.guard(function(p)
      if p and p ~= '' then open_file(ctx, p) end
    end)
  )
end
local function search(ctx)
  local ok, telescope = pcall(require, 'telescope.builtin')
  if ok and vim.fn.executable 'rg' == 1 then
    telescope.live_grep { cwd = ctx.model.root }
    return
  end
  if vim.fn.executable 'rg' ~= 1 then
    notify 'Text search needs ripgrep (rg). Find file and Explore remain available.'
    return
  end
  vim.ui.input(
    { prompt = 'Search project text: ' },
    ctx.guard(function(q)
      if not q or q == '' then return end
      loading(ctx, 'Search: ' .. q)
      local finish = ctx.guard(function(res)
        if res.code > 1 then
          textpage(ctx, 'Search failed', res.stderr)
          return
        end
        local entries = {}
        for line in (res.stdout or ''):gmatch '[^\n]+' do
          local ok, data = pcall(vim.json.decode, line)
          if ok and data.type == 'match' and #entries < 250 then
            local d = data.data
            entries[#entries + 1] = {
              label = d.path.text .. ':' .. d.line_number,
              detail = d.lines.text:gsub('\n$', ''),
              action = 'search_hit',
              value = {
                path = d.path.text,
                line = d.line_number,
              },
            }
          end
        end
        if #entries == 0 then entries = { { label = 'No matching lines.' } } end
        ctx.replace(ui.page('Search: ' .. q, 'Up to 250 matching lines · project only', entries))
      end)
      vim.system({ 'rg', '--json', '--fixed-strings', '--max-count', '30', '--', q, '.' }, { cwd = ctx.model.root, text = true }, function(res)
        vim.schedule(function() finish(res) end)
      end)
    end)
  )
end
function M.dispatch(ctx, action, value)
  local model = ctx.model
  local root = model.root
  if action == 'file' then
    open_file(ctx, value)
  elseif action == 'search_hit' then
    open_file(ctx, value.path, value.line)
  elseif action == 'find' then
    find(ctx)
  elseif action == 'search' then
    search(ctx)
  elseif action == 'new' then
    newfile(ctx)
  elseif action == 'browse' then
    local path = absolute(ctx, value)
    local ok, oil = pcall(require, 'oil')
    if ok then
      oil.open(path)
    else
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    end
  elseif action == 'recents' then
    local rows = {}
    for _, e in ipairs(model.recents or {}) do
      rows[#rows + 1] = { label = e.label or e.path, action = 'file', value = e.path }
    end
    if #rows == 0 then rows = { { label = 'No files opened in this project yet.', detail = 'Use Find file or Start exploring to begin.' } } end
    ctx.show(ui.page('Recent files', root, rows))
  elseif action == 'shortcuts' or action == 'explore' then
    require('custom.project_home.shortcuts').edit(root, ctx.guard(ctx.refresh))
  elseif action == 'resume' then
    local session = require('custom.project_home.state').get(root).session
    local info, err = require('custom.project_home.sessions').inspect(session, false, root)
    if not info then
      ctx.show(ui.page('Resume workspace', err, { { label = 'Open files, then save with :ProjectHomeSessionSave', action = 'home' } }))
      return
    end
    local rows =
      { { label = 'Restore ' .. info.count .. ' windows in a new tab', detail = 'Current windows and unsaved buffers stay open.', action = 'restore' } }
    for _, file in ipairs(info.files) do
      rows[#rows + 1] = { label = file.path, detail = 'Cursor at line ' .. file.line }
    end
    ctx.show(ui.page('Resume workspace', os.date('%b %d · %H:%M', info.saved_at), rows))
  elseif action == 'restore' then
    local ok, err = require('custom.project_home.sessions').restore(
      require('custom.project_home.state').get(root).session,
      { window_options = ctx.original_options, root = root }
    )
    if not ok then notify(err) end
  elseif action == 'git' then
    if model.git.error then
      ctx.show(ui.page('Git unavailable', model.git.error, {}))
      return
    end
    if model.git.loading then
      ctx.show(ui.page('Working changes', 'Loading local Git…', {}, 'git'))
      return
    end
    if not model.git.available then
      notify 'This folder is not a Git repository.'
      return
    end
    local rows = {}
    for _, c in ipairs(model.git.changes or {}) do
      rows[#rows + 1] = {
        label = (c.index or ' ') .. (c.worktree or ' ') .. '  ' .. c.path,
        detail = c.untracked and 'Untracked · open to inspect' or c.staged and 'Includes staged changes' or 'Working tree change',
        action = c.untracked and 'file' or 'diff',
        value = c.path,
      }
    end
    if #rows == 0 then rows[#rows + 1] = { label = 'Working tree is clean.' } end
    if vim.fn.executable 'lazygit' == 1 then rows[#rows + 1] = { label = 'Open LazyGit', action = 'lazygit' } end
    rows[#rows + 1] = { label = 'Commit history', action = 'history' }
    ctx.show(ui.page('Working changes', model.branch or root, rows, 'git'))
  elseif action == 'diff' then
    loading(ctx, 'Diff · ' .. value)
    provider().gitdiff(root, value, ctx.guard(function(data, err) textpage(ctx, 'Diff · ' .. value, data or err or 'No diff available.') end))
  elseif action == 'lazygit' then
    vim.cmd.tabnew()
    vim.fn.termopen({ 'lazygit' }, { cwd = root })
    vim.cmd.startinsert()
  elseif action == 'history' then
    if type(value) == 'string' and value ~= '' then return M.dispatch(ctx, 'commit', value) end
    loading(ctx, model.scope == 'you' and 'Your activity' or 'Repository activity')
    provider().history(
      root,
      model.scope or 'repo',
      ctx.guard(function(items, err)
        if not items then
          textpage(ctx, 'History unavailable', err)
          return
        end
        local rows = {}
        for _, c in ipairs(items) do
          rows[#rows + 1] = { label = c.subject, detail = c.hash:sub(1, 8) .. ' · ' .. c.author .. ' · ' .. c.date, action = 'commit', value = c.hash }
        end
        if #rows == 0 then rows = { { label = 'No commits in this scope.' } } end
        ctx.replace(ui.page('Commit history', model.scope == 'you' and 'Your commits · all local branches' or 'Repository · all local branches', rows))
      end)
    )
  elseif action == 'commit' then
    loading(ctx, 'Commit ' .. value:sub(1, 8))
    provider().git(
      root,
      { 'show', '--no-ext-diff', '--no-textconv', '--format=fuller', '--stat', '--patch', value },
      ctx.guard(function(data, err) textpage(ctx, 'Commit ' .. value:sub(1, 8), data or err) end)
    )
  elseif action == 'prs' then
    local rows = {}
    for _, pr in ipairs(model.prs.items or {}) do
      rows[#rows + 1] = {
        label = '#' .. pr.number .. ' ' .. pr.title,
        detail = pr.headRefName .. ' · ' .. (pr.isDraft and 'Draft' or pr.reviewDecision ~= '' and pr.reviewDecision or 'Open'),
        action = 'pr',
        value = pr.number,
      }
    end
    if #rows == 0 then rows = { { label = model.prs.status == 'loading' and 'Loading pull requests…' or model.prs.error or 'No open pull requests.' } } end
    ctx.show(ui.page('Pull requests', root, rows, 'prs'))
  elseif action == 'pr' then
    loading(ctx, 'Pull request #' .. value)
    provider().pr_detail(
      root,
      value,
      ctx.guard(function(pr, err)
        if not pr then
          textpage(ctx, 'Pull request unavailable', err)
          return
        end
        ctx.prs = ctx.prs or {}
        ctx.prs[value] = pr
        local entries = {
          { label = pr.title, detail = (pr.headRefName or '') .. ' → ' .. (pr.baseRefName or 'main') },
          { label = 'Overview', action = 'pr_overview', value = value },
          { label = 'Checks', action = 'pr_checks', value = value },
          { label = 'Changed files', action = 'pr_files', value = value },
        }
        if pr.url then entries[#entries + 1] = { label = 'Open on GitHub ↗', action = 'url', value = pr.url } end
        ctx.replace(ui.page('Pull request #' .. value, pr.isDraft and 'Draft' or pr.reviewDecision or 'Open', entries))
      end)
    )
  elseif action == 'pr_overview' then
    ctx.show(ui.page('PR #' .. value .. ' · Overview', '', {}))
    textpage(ctx, ctx.prs[value].title, ctx.prs[value].body or 'No description provided.')
  elseif action == 'pr_checks' then
    local rows = {}
    for _, c in ipairs(ctx.prs[value].statusCheckRollup or {}) do
      local status = (c.conclusion and c.conclusion ~= '' and c.conclusion) or c.state or c.status or 'Pending'
      local failure = vim.tbl_contains({ 'FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'STALE' }, status)
      local group = failure and 'ProjectHomeWarning' or status == 'SUCCESS' and 'ProjectHomeSuccess' or 'ProjectHomeMuted'
      rows[#rows + 1] = {
        label = c.name or c.context or 'Check',
        detail = status,
        group = group,
        detail_group = group,
        action = (c.detailsUrl or c.targetUrl) and 'url' or nil,
        value = c.detailsUrl or c.targetUrl,
      }
    end
    if #rows == 0 then rows = { { label = 'No checks reported for this pull request.' } } end
    ctx.show(ui.page('PR #' .. value .. ' · Checks', 'Live GitHub status', rows))
  elseif action == 'pr_files' then
    loading(ctx, 'PR #' .. value .. ' · Diff')
    provider().gh(
      root,
      { 'pr', 'diff', tostring(value) },
      ctx.guard(function(data, err) textpage(ctx, 'PR #' .. value .. ' · Diff', type(data) == 'string' and data or err or 'Diff unavailable.') end)
    )
  elseif action == 'url' then
    if type(value) == 'string' and value:match '^https://' then vim.ui.open(value) end
  elseif action == 'worktrees' then
    local rows = {}
    for _, w in ipairs(model.worktrees or {}) do
      rows[#rows + 1] = {
        label = (w.current and '● ' or '○ ') .. (w.branch or 'Detached HEAD'),
        detail = w.path .. (w.locked and ' · locked' or ''),
        action = 'worktree',
        value = w.path,
      }
    end
    if #rows == 0 then
      rows =
        { { label = model.worktrees_error or 'No Git worktrees available.', group = model.worktrees_error and 'ProjectHomeWarning' or 'ProjectHomeMuted' } }
    end
    ctx.show(ui.page('Worktrees', 'Open in a new tab · unsaved work stays in its current tab', rows, 'worktrees'))
  elseif action == 'worktree' then
    if vim.fn.isdirectory(value) ~= 1 then
      notify 'This worktree is no longer available. Refresh the dashboard.'
      return
    end
    vim.cmd.tabnew()
    for key, option in pairs(ctx.original_options or {}) do
      pcall(function() vim.wo[key] = option end)
    end
    vim.cmd('tcd ' .. vim.fn.fnameescape(value))
    require('custom.project_home').open(ctx.layout, { root = value, reuse = true })
  elseif action == 'activity' then
    ctx.scope = value == 'you' and 'you' or 'repo'
    require('custom.project_home.state').update(root, 'scope', ctx.scope)
    ctx.home()
  elseif action == 'more' then
    ctx.show(ui.page('Workspace actions', root, {
      { label = model.show_activity == false and 'Show activity' or 'Hide activity', action = 'activity_visibility' },
      { label = 'Find file', action = 'find' },
      { label = 'Search project text', action = 'search' },
      { label = 'Explore files', action = 'browse' },
      { label = 'New file', action = 'new' },
      { label = 'Recent files', action = 'recents' },
      { label = 'Resume workspace', action = 'resume' },
      { label = 'Edit shortcuts', action = 'shortcuts' },
      { label = 'Working changes', action = 'git' },
      { label = 'Pull requests', action = 'prs' },
      { label = 'Worktrees', action = 'worktrees' },
      { label = 'Commit history', action = 'history' },
    }))
  else
    return false
  end
  return true
end
return M
