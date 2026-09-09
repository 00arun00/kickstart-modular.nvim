local M = {}
function M.check()
  local env, host = require 'custom.python.venv', require 'custom.python.host'
  vim.health.start 'Python PDE'
  for _, name in ipairs { 'python', 'jupytext' } do
    local path = host.executable(name)
    if vim.fn.executable(path) == 1 then
      vim.health.ok('Editor ' .. name .. ': ' .. path)
    else
      vim.health.error('Missing editor ' .. name, { 'Run bash scripts/setup-python.sh, restart, :UpdateRemotePlugins, restart' })
    end
  end
  local path = env.here()
  vim.health.info('Project root: ' .. env.root(path))
  vim.health.info('Project Python: ' .. env.python(path))
  vim.health.info('Ruff: ' .. env.ruff(path))
  if not env.venv(path) then vim.health.warn('No project .venv; using PATH Python', { 'Run uv sync in your project' }) end
  local result = vim.system({ env.python(path), '-c', 'import ipykernel, pytest' }, { text = true }):wait(10000)
  if result.code == 0 then
    vim.health.ok 'Project has ipykernel and pytest'
  else
    vim.health.warn('Project notebook/test dependencies missing', { 'Run uv add --dev ipykernel pytest', result.stderr or '' })
  end
  if vim.fn.exists ':MoltenInit' == 2 then
    vim.health.ok 'Molten remote commands registered'
  else
    vim.health.error('Molten commands not registered', { ':UpdateRemotePlugins, then restart Neovim' })
  end
end
return M
