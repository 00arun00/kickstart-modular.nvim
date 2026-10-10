"""Our popup styling against controlled results, without a live test runner."""

import os
import subprocess

import pytest

pytestmark = [pytest.mark.fast, pytest.mark.python]


@pytest.mark.parametrize(
    "status,highlight",
    [
        ("passed", "DiagnosticOk"),
        ("failed", "DiagnosticError"),
        ("skipped", "DiagnosticWarn"),
        ("none", "FloatBorder"),
    ],
)
def test_output_popup_contract(tmp_path, pytestconfig, status, highlight):
    script = tmp_path / "output.lua"
    script.write_text(r"""
vim.opt.rtp:prepend(vim.env.TEST_CONFIG_ROOT)
vim.o.columns, vim.o.lines = 120, 35
local calls, received = 0, nil
local output = {open=function(opts) calls=calls+1; received=opts; return 'delegated' end}
package.loaded['neotest.consumers.output'] = output
package.loaded.nio = {create=function(fn) return fn end}
package.loaded['neotest.lib'] = {ui={float={open=function(opts)
  assert(opts.auto_close)
  local buf=vim.api.nvim_create_buf(false,true)
  return {win_id=vim.api.nvim_open_win(buf,true, {
    relative='editor',row=0,col=0,width=opts.width,height=opts.height,
  })}
end}}}
local status=vim.env.TEST_STATUS
local tree={data=function() return {id='test'} end}
local client={
  get_nearest=function() return tree,'adapter' end,
  get_position=function(_,id) assert(id=='test'); return tree,'adapter' end,
  get_results=function(_,adapter)
    assert(adapter=='adapter')
    return status=='none' and {} or {test={status=status}}
  end,
}
require('custom.navigation.test_output')(client)
for _,explicit in ipairs({false,true}) do
  assert(output.open({short=true,enter=true,auto_close=true,position_id=explicit and 'test' or nil})=='delegated')
  assert(received.short and received.enter and received.auto_close)
  local win=received.open_win({width=200,height=100})
  local cfg=vim.api.nvim_win_get_config(win)
  assert(cfg.width<=72 and cfg.height<=21, 'popup must fit editor')
  assert(cfg.border[1][2]==vim.env.TEST_HIGHLIGHT)
  local title=status=='none' and 'Test output' or status:sub(1,1):upper()..status:sub(2)
  assert(cfg.title[1][1]:find(title,1,true))
  assert(vim.wo[win].winhighlight=='Normal:NormalFloat')
  vim.api.nvim_win_close(win,true)
end
local custom=function() end
output.open({open_win=custom})
assert(received.open_win==custom, 'caller-supplied window factory was replaced')
assert(calls==3)
""")
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
        env=dict(
            os.environ,
            TEST_CONFIG_ROOT=str(pytestconfig.rootpath),
            TEST_STATUS=status,
            TEST_HIGHLIGHT=highlight,
        ),
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stdout + result.stderr
