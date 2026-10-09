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

local windows = vim.fn.has 'win32' == 1
local bindir = windows and 'Scripts' or 'bin'
local exe = windows and '.exe' or ''

--- Nearest directory above `path` that looks like a project.
---@param path string
---@return string|nil
local function project_root(path)
  local marker = vim.fs.find({ '.venv', 'pyproject.toml', 'setup.cfg', 'setup.py', 'pytest.ini', '.git' }, { path = path, upward = true })[1]
  return marker and vim.fs.dirname(marker) or nil
end

-- One file per canonical project root keeps independent editor sessions from
-- overwriting each other's selections. These are local preferences, not repo files.
local function selection_file(root)
  local key = vim.uv.fs_realpath(root) or vim.fs.normalize(root)
  return vim.fs.joinpath(vim.fn.stdpath 'state', 'python-envs', vim.fn.sha256(key))
end

local function selection(root)
  if not root then return nil end
  local file = selection_file(root)
  if vim.fn.filereadable(file) == 0 then return nil end
  local path = vim.fn.readfile(file)[1]
  return path and path ~= '' and path or nil
end

--- Nearest `.venv` above `path`, honouring the saved project selection.
local function find_venv(path)
  local chosen = selection(project_root(path))
  if chosen then
    local python = vim.fs.joinpath(chosen, bindir, 'python' .. exe)
    assert(vim.fn.executable(python) == 1, 'Saved Python environment is unavailable: ' .. chosen .. '. Use :PyVenvSet or :PyVenvReset')
    return chosen
  end
  return vim.fs.find('.venv', { path = path, upward = true, type = 'directory' })[1]
end

--- Path to an executable inside a venv, if it actually exists there.
---@param venv string|nil
---@param name string
---@return string|nil
local function tool(venv, name)
  if not venv then return nil end
  local p = vim.fs.joinpath(venv, bindir, name .. exe)
  return vim.fn.executable(p) == 1 and p or nil
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
function M.root(path) return project_root(path) or path end

function M.venv(path) return find_venv(path) end

function M.tool(path, name) return tool(find_venv(path), name) or on_path(name) end

function M.here() return here() end

function M.python(path) return tool(find_venv(path), 'python') or on_path 'python3' or 'python3' end

--- ruff for a path: the project's pinned one, else PATH (mason installs there).
---@param path string
---@return string
function M.ruff(path) return tool(find_venv(path), 'ruff') or on_path 'ruff' or 'ruff' end

-- Restart only clients serving this project, preserving other open projects.
function M.restart(root)
  local pending = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    if (client.name == 'basedpyright' or client.name == 'ruff') and M.root(client.root_dir or root) == root then
      for bufnr in pairs(client.attached_buffers) do
        pending[bufnr] = pending[bufnr] or {}
        pending[bufnr][client.name] = client.root_dir or root
      end
      client:stop(true)
    end
  end
  vim.defer_fn(function()
    for bufnr, names in pairs(pending) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_call(bufnr, function()
          for name, client_root in pairs(names) do
            local config = vim.lsp.config[name]
            if config then
              config = vim.deepcopy(config)
              config.root_dir = client_root
              vim.lsp.start(config, { bufnr = bufnr })
            end
          end
        end)
      end
    end
  end, 200)
end

vim.api.nvim_create_user_command('PyVenvReset', function()
  local root = project_root(here())
  if root then
    vim.fn.delete(selection_file(root))
    M.restart(root)
  end
end, { desc = 'Return this project to automatic .venv detection' })

vim.api.nvim_create_user_command('PyVenvInfo', function()
  local path = here()
  local root = project_root(path)
  local lines = {
    'root:   ' .. (root or '(none)'),
    'venv:   ' .. (find_venv(path) or '(none - falling back to system python)'),
    'python: ' .. M.python(path),
    'ruff:   ' .. M.ruff(path),
  }
  if selection(root) then table.insert(lines, 'override: saved via :PyVenvSet') end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'Python env' })
end, { desc = 'Report the resolved Python interpreter and ruff binary' })

local function set_venv(root, path)
  local input = vim.fn.expand(path)
  local stat = vim.uv.fs_stat(input)
  if not stat then return vim.notify('No such path: ' .. path, vim.log.levels.ERROR, { title = 'Python env' }) end

  -- Accept the venv directory or an interpreter inside it (`<venv>/bin/python`).
  local venv = stat.type == 'directory' and input or vim.fs.dirname(vim.fs.dirname(input))
  if not tool(venv, 'python') then return vim.notify(venv .. ' does not look like a virtualenv', vim.log.levels.ERROR, { title = 'Python env' }) end

  venv = vim.fs.normalize(vim.fn.fnamemodify(venv, ':p')):gsub('/$', '')
  local file = selection_file(root)
  vim.fn.mkdir(vim.fs.dirname(file), 'p')
  vim.fn.writefile({ venv }, file)

  M.restart(root)
  vim.notify(
    'venv saved as ' .. venv .. '\nPython servers restarting; restart active kernels/debug sessions separately',
    vim.log.levels.INFO,
    { title = 'Python env' }
  )
end

function M.pick()
  local root = project_root(here())
  if not root then return vim.notify('Open a file inside a Python project first', vim.log.levels.WARN) end
  local choices, seen = {}, {}
  local function add(path)
    if not path or not tool(path, 'python') then return end
    local key = vim.uv.fs_realpath(path) or path
    if seen[key] then return end
    seen[key] = true
    table.insert(choices, path)
  end
  add(selection(root))
  add(vim.fs.find('.venv', { path = root, upward = true, type = 'directory' })[1])
  -- Only immediate children: include any environment name without scanning
  -- dependency trees or assuming which environment manager created it.
  for name in vim.fs.dir(root) do
    add(vim.fs.joinpath(root, name))
  end
  add(vim.env.VIRTUAL_ENV)
  local manual = 'Enter another environment path…'
  table.insert(choices, manual)
  vim.ui.select(choices, { prompt = 'Python environment: ' .. vim.fs.basename(root) }, function(choice)
    if not choice then return end
    if choice == manual then
      vim.ui.input({ prompt = 'Environment path: ', default = root .. '/', completion = 'dir' }, function(path)
        if path and path ~= '' then set_venv(root, path) end
      end)
    else
      set_venv(root, choice)
    end
  end)
end

vim.api.nvim_create_user_command('PyVenvSet', function(opts)
  if opts.args == '' then return M.pick() end
  local root = project_root(here())
  if not root then return vim.notify('Open a file inside a Python project first', vim.log.levels.WARN) end
  set_venv(root, opts.args)
end, {
  nargs = '?',
  desc = 'Pick or specify a virtualenv for this project',
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
