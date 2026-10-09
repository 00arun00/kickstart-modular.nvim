"""Real Neotest registration when environment and adapter roots differ."""

import os
import subprocess

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.python]


@pytest.mark.parametrize("nested_environment", [False, True])
def test_project_run_resolves_registered_adapter(tmp_path, pytestconfig, nested_environment):
    project = tmp_path / "project"
    package = project / "pkg" if nested_environment else project
    package.mkdir(parents=True)
    (project / "pyproject.toml").write_text("")
    (package / ".venv").mkdir()
    test_file = package / "test_example.py"
    test_file.write_text("def test_example():\n    assert True\n")
    script = tmp_path / "registered_adapter.lua"
    script.write_text(r'''
vim.opt.rtp:prepend(vim.env.TEST_CONFIG_ROOT)
local plugins = vim.fn.stdpath('data') .. '/lazy/'
for _, name in ipairs({'neotest', 'neotest-python', 'nvim-nio', 'plenary.nvim', 'nvim-treesitter'}) do
  vim.opt.rtp:append(plugins .. name)
end
vim.env.PATH = vim.env.TEST_CONFIG_ROOT .. '/.test-venv/bin:' .. vim.env.PATH
local project, scope = vim.env.TEST_PROJECT_ROOT, vim.env.TEST_ENV_ROOT
local file = scope .. '/test_example.py'
vim.cmd.cd(project)
vim.cmd.edit(file)
local env = require('custom.python.venv')
assert(env.root(vim.fs.dirname(file)) == scope, 'fixture must select environment root')
local spec = require('custom.plugins.neotest')[1].opts()
local config = require('neotest.config')
config.setup {adapters=spec.adapters}
-- Exercise real registration and parsing in this editor, without a worker editor.
require('neotest.lib').subprocess.enabled = function() return false end
local client = require('neotest.client')(require('neotest.adapters')())
local done, failure, ran = false, nil, false
require('nio').run(function()
  local ok, err = xpcall(function()
    client:_start {autocmds=false}
    local registered = client:get_adapter(project)
    assert(registered, 'Neotest did not register the project')
    assert(spec.adapters[1].root(scope) == project)
    -- Keep execution at the consumer boundary; real positions must be present
    -- on the registered adapter when the run is dispatched.
    package.loaded.neotest = {run={run=function(args)
      assert(args[1] == scope, 'changed requested test scope')
      assert(args.adapter == registered, 'did not use registered project adapter')
      local tree = client:get_position(file, {adapter=args.adapter})
      assert(tree, 'refresh did not discover the test file')
      local found = false
      for _, node in tree:iter_nodes() do
        if node:data().type == 'test' then found = true end
      end
      assert(found, 'no test positions discovered')
      ran = true
    end}}
    spec.consumers.project(client).run(env.root(vim.fs.dirname(file)))
    assert(ran, 'project run was not dispatched')
  end, debug.traceback)
  failure = not ok and err or nil
  done = true
end)
assert(vim.wait(15000, function() return done end), 'discovery did not complete')
assert(not failure, failure)
''')
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
        env=dict(os.environ, TEST_CONFIG_ROOT=str(pytestconfig.rootpath),
                 TEST_PROJECT_ROOT=str(project), TEST_ENV_ROOT=str(package),
                 XDG_STATE_HOME=str(tmp_path / "state"), XDG_CACHE_HOME=str(tmp_path / "cache")),
        capture_output=True, text=True, timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
