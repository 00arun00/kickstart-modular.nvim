local M = {}

local function notify(message) vim.notify(message, vim.log.levels.INFO, { title = 'Git Blame' }) end

local function open_pr(url)
  local repo = url:match '^https://github%.com/([^/]+/[^/]+)/commit/'
  local sha = url:match '/commit/(%x+)$'
  if not repo or not sha then return notify 'PR lookup currently supports github.com remotes only.' end
  if vim.fn.executable 'gh' ~= 1 then return notify 'Install and authenticate the GitHub CLI (gh) to find PRs.' end
  vim.system(
    { 'gh', 'api', '--hostname', 'github.com', 'repos/' .. repo .. '/commits/' .. sha .. '/pulls' },
    {
      text = true,
      timeout = 15000,
    },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then return notify('PR lookup failed: ' .. vim.trim(result.stderr or 'Check gh authentication.')) end
      local ok, prs = pcall(vim.json.decode, result.stdout)
      if not ok or type(prs) ~= 'table' then return notify 'GitHub returned an invalid PR response.' end
      if #prs == 0 then return notify 'No GitHub PR is associated with this commit. Use gc to open the commit.' end
      local function open(pr)
        if pr then vim.ui.open(pr.html_url) end
      end
      if #prs == 1 then return open(prs[1]) end
      vim.ui.select(prs, {
        prompt = 'Pull requests for this commit',
        format_item = function(pr) return ('#%s %s (%s)'):format(pr.number, pr.title, pr.state) end,
      }, open)
    end)
  )
end

local function browse_commit(sha, root, pr)
  if sha:match '^0+$' then return notify 'This line is uncommitted and has no commit or PR yet.' end
  local cwd = vim.fn.getcwd()
  vim.fn.chdir(root)
  local ok, err = pcall(function()
    local opts = { what = 'commit', commit = sha }
    if pr then
      opts.open = open_pr
      opts.notify = false
    end
    require('snacks').gitbrowse(opts)
  end)
  vim.fn.chdir(cwd)
  if not ok then notify(tostring(err)) end
end

function M.from_lazygit(sha, root, pr)
  -- Leave the terminal behind while Neovim handles any remote/PR chooser.
  for _, terminal in pairs(require('snacks').terminal.list()) do
    if terminal.buf == vim.api.nvim_get_current_buf() then
      terminal:hide()
      break
    end
  end
  vim.cmd.stopinsert()
  -- Gitbrowse must use the supplied repository rather than an unrelated file
  -- that became current when the LazyGit window was hidden.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_call(buf, function() browse_commit(sha, root, pr) end)
  vim.api.nvim_buf_delete(buf, { force = true })
end

function M.browse(pr)
  local name = vim.api.nvim_buf_get_name(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local root = vim.b.custom_snacks_blame_root
  if root then
    -- Each patch belongs to the nearest preceding full commit header.
    local lines = vim.api.nvim_buf_get_lines(0, 0, line, false)
    for i = #lines, 1, -1 do
      local sha = lines[i]:match '^commit (%x+)'
      if sha and (#sha == 40 or #sha == 64) then return browse_commit(sha, root, pr) end
    end
    return notify 'Move the cursor onto a commit or its patch first.'
  end
  -- Gitsigns exposes no public selected-commit API for its blame split.
  -- Match its revision buffer name and use the same per-line cache as its own actions.
  local cache = require('gitsigns.cache').cache
  for _, entry in pairs(cache) do
    if entry:get_rev_bufname():gsub('^gitsigns:', 'gitsigns-blame:') == name then
      local info = entry.blame and entry.blame.entries[line]
      if not info then return notify 'Blame information is no longer available; reopen blame.' end
      return browse_commit(info.commit.sha, entry.git_obj.repo.toplevel, pr)
    end
  end
  notify 'Could not find the source buffer for this blame view; reopen blame.'
end

local function map_browse(buf)
  vim.keymap.set('n', 'gc', function() M.browse(false) end, { buffer = buf, desc = 'Open blamed commit in browser' })
  vim.keymap.set('n', 'gp', function() M.browse(true) end, { buffer = buf, desc = 'Open blamed GitHub PR in browser' })
end

function M.snacks()
  local root = require('snacks').git.get_root()
  if not root then return notify 'The current file is not in a Git repository.' end
  return require('snacks').git.blame_line {
    -- Keep headers predictable for browsing; avoid an interactive pager.
    env = { GIT_PAGER = 'cat', GIT_CONFIG_COUNT = '1', GIT_CONFIG_KEY_0 = 'format.pretty', GIT_CONFIG_VALUE_0 = 'medium' },
    win = {
      on_buf = function(win)
        vim.b[win.buf].custom_snacks_blame_root = root
        map_browse(win.buf)
      end,
    },
  }
end

function M.gitsigns(toggle)
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.filetype ~= 'gitsigns-blame' then
    local entry = require('gitsigns.cache').cache[vim.api.nvim_get_current_buf()]
    if not entry then return notify 'Gitsigns is not attached to this file yet.' end
    name = entry:get_rev_bufname():gsub('^gitsigns:', 'gitsigns-blame:')
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == name then
      if toggle then
        vim.api.nvim_win_close(win, true)
      else
        vim.api.nvim_set_current_win(win)
      end
      return
    end
  end
  require('gitsigns').blame()
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('CustomBlameBrowse', { clear = true }),
    pattern = 'gitsigns-blame',
    callback = function(event) map_browse(event.buf) end,
  })
end

return M
