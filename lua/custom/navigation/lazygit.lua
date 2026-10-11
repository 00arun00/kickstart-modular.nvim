local M = {}
local menu_path

function M.open(file_history)
  local snacks = require 'snacks'
  local config = snacks.config.get 'lazygit'
  local files = vim.split(vim.env.LG_CONFIG_FILE or '', ',', { trimempty = true })
  if #files == 0 then
    local result = vim.system({ 'lazygit', '-cd' }, { text = true }):wait()
    if result.code ~= 0 then return vim.notify(result.stderr, vim.log.levels.ERROR) end
    local dir = vim.split(vim.trim(result.stdout), '\n')[1]
    local default = dir .. '/config.yml'
    if vim.fn.filereadable(default) == 1 then files[#files + 1] = default end
  end
  local theme = config.theme_path or (vim.fn.stdpath 'cache' .. '/lazygit-theme.yml')
  if config.configure ~= false and not vim.tbl_contains(files, theme) then files[#files + 1] = theme end

  -- JSON is valid YAML and supports nested command menus, unlike Snacks'
  -- simple theme-file serializer. Keep the user's own LazyGit files intact.
  local menu = {}
  for _, item in ipairs { { 'c', 'commit' }, { 'p', 'pr' } } do
    menu[#menu + 1] = {
      key = item[1],
      context = 'commits,subCommits,reflogCommits,commitFiles',
      description = 'Open selected ' .. item[2] .. ' in browser',
      command = '"$CUSTOM_NVIM_BIN" --headless -u NONE -i NONE -l "$CUSTOM_LAZYGIT_BROWSE" "$NVIM" {{.SelectedCommit.Sha | quote}} ' .. item[2],
    }
  end
  menu_path = menu_path or (vim.fn.tempname() .. '.json')
  vim.fn.writefile({
    vim.json.encode {
      -- The built-in commit reset menu otherwise takes precedence over `g`.
      keybinding = { commits = { viewResetOptions = '<c-g>' } },
      customCommands = { { key = 'g', description = 'Go to browser', commandMenu = menu } },
    },
  }, menu_path)
  files[#files + 1] = menu_path
  local script = vim.api.nvim_get_runtime_file('scripts/lazygit-browse.lua', false)[1]
  local opts = {
    env = {
      LG_CONFIG_FILE = table.concat(files, ','),
      CUSTOM_NVIM_BIN = vim.v.progpath,
      CUSTOM_LAZYGIT_BROWSE = assert(script, 'Missing LazyGit browser bridge'),
      NVIM = vim.v.servername ~= '' and vim.v.servername or vim.fn.serverstart(),
    },
  }
  if file_history then return snacks.lazygit.log_file(opts) end
  return snacks.lazygit(opts)
end

return M
