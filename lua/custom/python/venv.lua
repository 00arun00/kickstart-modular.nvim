--- Python interpreter and tool resolution.
---
--- uv places a project's virtualenv at `<root>/.venv` deterministically, so
--- resolution is just a walk up from the buffer. The result feeds
--- `basedpyright` (which interpreter to analyse against) and `ruff` (which
--- binary to run, so editor diagnostics match a repo's pinned version rather
--- than whatever mason last installed). Both are wired up in
--- `kickstart/plugins/lspconfig.lua`; conform uses `M.ruff` too, see
--- `kickstart/plugins/conform.lua`.
---
--- Resolution fails *silently* - unresolved imports, no error - which is why
--- `:PyVenvInfo` exists. `:PyVenvSet` overrides it for the current project.
---
--- Note on precedence: `python.pythonPath` is one of the few language server
--- settings basedpyright still honours when a project ships its own
--- `pyproject.toml`/`pyrightconfig.json`, so this keeps working everywhere.

local M = {}

--- Overrides set by `:PyVenvSet`, keyed by project root.
---@type table<string, string>
local overrides = {}

local windows = vim.fn.has 'win32' == 1
local bindir = windows and 'Scripts' or 'bin'
local exe = windows and '.exe' or ''

--- Nearest directory above `path` that looks like a project.
---@param path string
---@return string|nil
local function project_root(path)
  local marker = vim.fs.find({ '.venv', 'pyproject.toml', '.git' }, { path = path, upward = true })[1]
  return marker and vim.fs.dirname(marker) or nil
end

--- Nearest `.venv` above `path`, honouring any `:PyVenvSet` override.
---@param path string
---@return string|nil
local function find_venv(path)
  local root = project_root(path)
  if root and overrides[root] then return overrides[root] end
  return vim.fs.find('.venv', { path = path, upward = true, type = 'directory' })[1]
end

--- Path to an executable inside a venv, if it actually exists there.
---@param venv string|nil
---@param name string
---@return string|nil
local function tool(venv, name)
  if not venv then return nil end
  local p = vim.fs.joinpath(venv, bindir, name .. exe)
  return vim.uv.fs_stat(p) and p or nil
end

--- `vim.fn.exepath` returns an empty string when nothing is found, not nil.
---@param name string
---@return string|nil
local function on_path(name)
  local found = vim.fn.exepath(name)
  return found ~= '' and found or nil
end

--- Directory to resolve against: the buffer's, or cwd for unnamed buffers.
---@return string
local function here()
  local dir = vim.fn.expand '%:p:h'
  return dir ~= '' and dir or assert(vim.uv.cwd())
end

--- Interpreter for a path: the project venv's, else the system one.
---@param path string
---@return string
function M.python(path) return tool(find_venv(path), 'python') or on_path 'python3' or 'python3' end

--- ruff for a path: the project's pinned one, else PATH (mason installs there).
---@param path string
---@return string
function M.ruff(path) return tool(find_venv(path), 'ruff') or on_path 'ruff' or 'ruff' end

vim.api.nvim_create_user_command('PyVenvInfo', function()
  local path = here()
  local root = project_root(path)
  local lines = {
    'root:   ' .. (root or '(none)'),
    'venv:   ' .. (find_venv(path) or '(none - falling back to system python)'),
    'python: ' .. M.python(path),
    'ruff:   ' .. M.ruff(path),
  }
  if root and overrides[root] then table.insert(lines, 'override: set via :PyVenvSet') end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'Python env' })
end, { desc = 'Report the resolved Python interpreter and ruff binary' })

vim.api.nvim_create_user_command('PyVenvSet', function(opts)
  local input = vim.fn.expand(opts.args)
  local stat = vim.uv.fs_stat(input)
  if not stat then return vim.notify('No such path: ' .. opts.args, vim.log.levels.ERROR, { title = 'Python env' }) end

  -- Accept the venv directory or an interpreter inside it (`<venv>/bin/python`).
  local venv = stat.type == 'directory' and input or vim.fs.dirname(vim.fs.dirname(input))
  if not tool(venv, 'python') then return vim.notify(venv .. ' does not look like a virtualenv', vim.log.levels.ERROR, { title = 'Python env' }) end

  local root = project_root(here())
  if not root then return vim.notify('Not inside a project - nothing to attach the override to', vim.log.levels.WARN, { title = 'Python env' }) end
  overrides[root] = vim.fn.fnamemodify(venv, ':p'):gsub('/$', '')

  -- Both servers read the interpreter once at startup, so they must restart.
  for _, name in ipairs { 'basedpyright', 'ruff' } do
    for _, client in ipairs(vim.lsp.get_clients { name = name }) do
      client:stop()
    end
  end
  vim.notify('venv set to ' .. overrides[root] .. '\nrestarting basedpyright and ruff', vim.log.levels.INFO, { title = 'Python env' })
end, {
  nargs = 1,
  desc = 'Point Python tooling at a specific virtualenv',
  --- Project venvs first, then ordinary path completion so an interpreter
  --- outside the project still works.
  complete = function(arg_lead)
    local root = project_root(here())
    local out = {}
    if root then
      -- Bounded depth: a monorepo has a venv per package, but scanning the
      -- whole tree on every <Tab> is not worth it.
      for name, type in vim.fs.dir(root, { depth = 3 }) do
        if type == 'directory' and vim.fs.basename(name) == '.venv' then table.insert(out, vim.fs.joinpath(root, name)) end
      end
    end
    vim.list_extend(out, vim.fn.getcompletion(arg_lead, 'file'))
    return vim.tbl_filter(function(c) return c:find(arg_lead, 1, true) ~= nil end, out)
  end,
})

return M
