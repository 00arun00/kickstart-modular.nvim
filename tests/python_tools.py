"""Exercise LSP, pytest results, and a real debugpy breakpoint in a disposable project.

Run with the editor host Python after installing plugins; argv[1] is a uv project
with pytest. Its .venv is selected even when Neovim starts outside that project.
"""

import sys
import time
from pathlib import Path

import pynvim

project = Path(sys.argv[1]).resolve()
test_file = project / "test_pde_smoke.py"
test_file.write_text("""import sys
from pathlib import Path

def test_environment():
    assert Path(sys.prefix).name == ".venv"

def test_failure_is_reported():
    assert 1 == 2
""")
program = project / "pde_debug.py"
program.write_text("import sys\nvalue = 42\nprint(value)\n")
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-i", "NONE", str(test_file)]
)


def wait(lua, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = n.exec_lua(lua)
        if result:
            return result
        time.sleep(0.1)
    print(
        n.exec_lua(
            "local s = require('neotest').state; local r = {}; for _,id in ipairs(s.adapter_ids()) do r[id] = s.status_counts(id) end; return r"
        ),
        flush=True,
    )
    print(n.command_output("messages"), flush=True)
    raise AssertionError(
        f"Timed out: {lua}\n{n.exec_lua('return _G.test_notifications')}"
    )


try:
    n.exec_lua(
        "_G.test_notifications = {}; vim.notify = function(msg) table.insert(_G.test_notifications, msg) end"
    )
    n.exec_lua(
        "vim.env.VIRTUAL_ENV = vim.fs.dirname(vim.fs.dirname(require('custom.python.host').executable('python')))"
    )
    wait("return #vim.lsp.get_clients({bufnr=0}) >= 2")
    python = n.exec_lua(
        "return vim.lsp.get_clients({name='basedpyright',bufnr=0})[1].settings.python.pythonPath"
    )
    assert python == str(project / ".venv/bin/python"), python
    old = n.exec_lua("return vim.lsp.get_clients({name='basedpyright',bufnr=0})[1].id")
    n.command("PyVenvSet " + n.funcs.fnameescape(str(project / ".venv")))
    wait(
        f"local c = vim.lsp.get_clients({{name='basedpyright',bufnr=0}}); return #c == 1 and c[1].id ~= {old}"
    )
    n.exec_lua("require('neotest').run.run(vim.api.nvim_buf_get_name(0))")
    counts = wait(
        "local s = require('neotest').state; for _,id in ipairs(s.adapter_ids()) do local c = s.status_counts(id); if c and c.passed == 1 and c.failed == 1 then return c end end"
    )
    assert counts["total"] == 2, counts
    n.command("edit " + n.funcs.fnameescape(str(program)))
    n.current.window.cursor = (2, 0)
    n.exec_lua("""
      local dap = require('dap')
      dap.toggle_breakpoint()
      _G.dap_stopped = false
      dap.listeners.after.event_stopped['pde-test'] = function() _G.dap_stopped = true end
      local config = vim.deepcopy(dap.configurations.python[1])
      config.console = 'internalConsole'
      dap.run(config)
    """)
    wait("return _G.dap_stopped")
    # Evaluate through the active debug adapter while paused at our breakpoint.
    n.exec_lua("""
      local session = require('dap').session()
      session:request('evaluate', {expression='sys.executable', context='repl'}, function(err, result)
        _G.debug_python = err and vim.inspect(err) or result.result
      end)
    """)
    evaluated = wait("return _G.debug_python")
    assert str(project / ".venv/bin/python") in evaluated, evaluated
    n.exec_lua("require('dap').terminate()")
    print(
        "PASS: LSP project interpreter and restart, pytest discovery/pass/fail, debugpy breakpoint and project interpreter"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
