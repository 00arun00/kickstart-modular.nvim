"""Navigation contracts with controlled discovery order, without live test runners."""

import subprocess

import pytest

pytestmark = [pytest.mark.fast, pytest.mark.python]


@pytest.mark.parametrize("report_mode", ["short", "errors"])
@pytest.mark.parametrize("order", ["root-first", "nested-first", "nested-only"])
def test_navigation_uses_project_results_regardless_of_discovery_order(
    tmp_path, pytestconfig, order, report_mode
):
    script = tmp_path / "navigation.lua"
    script.write_text(r"""
vim.opt.rtp:prepend(vim.env.TEST_CONFIG_ROOT)
local root = vim.env.TEST_PROJECT_ROOT
local path = root .. '/tests/example.py'
vim.cmd.edit(path)
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'header', 'pass', '', '', 'fail', ''})
local source = vim.api.nvim_get_current_win()
local canonical, nested = 'registered-project', 'registered-open-buffer'
package.loaded['custom.python.venv'] = { root = function() return root end }
package.loaded.nio = { run = function(fn) fn() end }
-- Explicitly drain scheduled previews; no timer or polling determines ordering.
local scheduled = {}
vim.schedule = function(fn) scheduled[#scheduled + 1] = fn end
local positions = {
  {id='pass', name='passing', path=path, type='test', range={1,0,2,0}},
  {id='fail', name='failing', path=path, type='test', range={4,0,5,0}},
}
local tree = {
  data = function() return {type='file', path=path} end,
  iter_nodes = function()
    local i = 0
    return function()
      i = i + 1
      if positions[i] then return i, {data=function() return positions[i] end} end
    end
  end,
}
local order = vim.env.TEST_DISCOVERY_ORDER
local results = {pass={status='passed'}, fail={status='failed', short='failure details'}}
if vim.env.TEST_REPORT_MODE == 'errors' then
  results.fail = {status='failed', errors={{message='failure details'}}}
end
local client = {listeners={}}
function client:get_adapter(path)
  local id = path == root and order ~= 'nested-only' and canonical or nested
  return id, {root=function() return root end}
end
function client:get_position(_, opts)
  local adapter = opts and opts.adapter
  if adapter == canonical and order == 'nested-only' then return nil, adapter end
  return tree, adapter or nested
end
function client:get_results(adapter)
  if adapter == canonical or order == 'nested-only' then return results end
  return {}
end
require('custom.navigation.tests')(client)
local discover = client.listeners.discover_positions
if order == 'root-first' then discover(canonical, tree); discover(nested, tree)
elseif order == 'nested-first' then discover(nested, tree); discover(canonical, tree)
else discover(nested, tree) end
-- Ignore startup discovery; invoke the installed mapping directly.
scheduled = {}
vim.fn.maparg(']f', 'n', false, true).callback()
assert(vim.api.nvim_get_current_line() == 'fail', 'did not select failed test')
assert(vim.api.nvim_get_current_win() == source, 'navigation stole focus')
for _, fn in ipairs(scheduled) do fn() end
local previews = 0
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.w[win].test_navigation_preview then
    previews = previews + 1
    assert(not vim.api.nvim_win_get_config(win).focusable)
    assert(table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win),0,-1,false), '\n'):find('failure details',1,true))
  end
end
assert(previews == 1, 'expected exactly one result preview')
assert(vim.api.nvim_get_current_win() == source, 'preview stole focus')
-- Drain only work triggered by the mapping under test. Even no-move boundary
-- cases are observed after execution, rather than passing on an old cursor.
local function navigate(key, row, status)
  scheduled = {}
  vim.fn.maparg(key, 'n', false, true).callback()
  for _, fn in ipairs(scheduled) do fn() end
  assert(vim.api.nvim_win_get_cursor(source)[1] == row, key .. ': wrong row')
  assert(vim.api.nvim_get_current_win() == source, key .. ': stole focus')
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].test_navigation_preview then
      count = count + 1
      assert(status, 'unexpected result preview')
      local cfg = vim.api.nvim_win_get_config(win)
      assert(not cfg.focusable)
      assert(cfg.title[1][1]:find(status, 1, true))
    end
  end
  assert(count == (status and 1 or 0), 'stale/missing preview')
end
navigate('[t', 2, 'Passed')
-- The current passing test is not a previous failure.
vim.api.nvim_win_set_cursor(source, {3,0})
navigate('[f', 3)
navigate(']f', 5, 'Failed')
navigate(']t', 5) -- End of file: no wrap, close the old preview.
-- Class headings are not test targets; discovered tests can lack results.
vim.api.nvim_buf_set_lines(0, -1, -1, false, {'unrun', ''})
positions[#positions+1] = {id='class', path=path, type='namespace', range={5,0,7,0}}
positions[#positions+1] = {id='unrun', path=path, type='test', range={6,0,7,0}}
navigate(']t', 7)
navigate('[t', 5, 'Failed')
-- A pending preview must not appear after leaving the originating buffer.
vim.api.nvim_win_set_cursor(source, {1,0})
scheduled = {}
vim.fn.maparg(']f', 'n', false, true).callback()
vim.cmd.enew()
for _, fn in ipairs(scheduled) do fn() end
for _, win in ipairs(vim.api.nvim_list_wins()) do
  assert(not vim.w[win].test_navigation_preview, 'preview followed buffer switch')
end
assert(vim.fn.maparg(']t', 'n', false, true).buffer ~= 1)
""")
    import os

    env = dict(
        os.environ,
        TEST_CONFIG_ROOT=str(pytestconfig.rootpath),
        TEST_PROJECT_ROOT=str(tmp_path),
        TEST_DISCOVERY_ORDER=order,
        TEST_REPORT_MODE=report_mode,
    )
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
