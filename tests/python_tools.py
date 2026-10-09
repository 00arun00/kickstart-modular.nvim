"""Exercise LSP, pytest results, and a real debugpy breakpoint in a disposable project.

Run with the editor host Python after installing plugins; argv[1] is a uv project
with pytest. Its .venv is selected even when Neovim starts outside that project.
"""

import sys
import time
import subprocess
import tempfile
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
    print(n.exec_lua("return {mode=vim.fn.mode(), ft=vim.bo.filetype, line=vim.api.nvim_get_current_line(), windows=vim.api.nvim_list_wins()}"), flush=True)
    raise AssertionError(
        f"Timed out: {lua}\n{n.exec_lua('return _G.test_notifications')}"
    )


try:
    n.ui_attach(120, 35, rgb=True)
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
    # Exercise the actual lazy-loading test mapping, not only the Neotest API.
    n.input(" tf")
    counts = wait(
        "local s = require('neotest').state; for _,id in ipairs(s.adapter_ids()) do local c = s.status_counts(id); if c and c.passed == 1 and c.failed == 1 then return c end end"
    )
    assert counts["total"] == 2, counts
    wait("return #vim.fn.sign_getplaced(vim.api.nvim_get_current_buf(), {group='neotest-status'})[1].signs > 0")
    n.exec_lua("""
      local config = require('neotest.config')
      local function indicator()
        vim.cmd('redraw!')
        return vim.api.nvim_eval_statusline(vim.wo.statuscolumn,
          {use_statuscol_lnum=4}).str
      end
      assert(indicator():find(config.icons.passed, 1, true), 'missing real passing test sign')
      local ns = vim.api.nvim_create_namespace('neotest-gutter-collision')
      vim.diagnostic.set(ns, 0, {{lnum=3, col=0, message='fixture', severity=vim.diagnostic.severity.ERROR}})
      assert(not indicator():find(config.icons.passed, 1, true), 'test sign hid diagnostic')
      require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 4)
      local bp = vim.fn.sign_getdefined('DapBreakpoint')[1].text:gsub('%s', '')
      assert(indicator():find(bp, 1, true), 'diagnostic or test hid breakpoint')
      require('dap.breakpoints').clear()
      vim.diagnostic.reset(ns)
      assert(indicator():find(config.icons.passed, 1, true), 'test sign did not return')
    """)
    # The popup shares diagnostic styling and communicates the result by color.
    n.current.window.cursor = (4, 0)
    n.input(" to")
    wait("return vim.bo.filetype == 'neotest-output'")
    n.exec_lua("local c=vim.api.nvim_win_get_config(0); assert(c.border[1][2]=='DiagnosticOk'); assert(c.title[1][1]:find('Passed')); assert(vim.wo.winhighlight:find('NormalFloat',1,true))")
    n.command("close")
    # Read the latest failure from both the source line and the summary selection.
    n.current.window.cursor = (7, 0)
    n.input(" to")
    wait("return vim.bo.filetype == 'neotest-output'")
    wait("return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'):find('assert 1 == 2', 1, true)")
    n.exec_lua("local c=vim.api.nvim_win_get_config(0); assert(c.border[1][2]=='DiagnosticError'); assert(c.title[1][1]:find('Failed'))")
    assert "test session starts" not in "\n".join(n.current.buffer[:]), "test popup must not show the entire run"
    assert "test_environment" not in "\n".join(n.current.buffer[:]), "unrelated test leaked into popup"
    n.command("close")
    n.exec_lua("require('neotest').summary.open({enter=true})")
    wait("return vim.bo.filetype == 'neotest-summary'")
    wait("for i,line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do if line:find('test_failure_is_reported', 1, true) then vim.api.nvim_win_set_cursor(0, {i,0}); return true end end")
    for key in ("K", " to"):
        n.input(key)
        wait("return vim.bo.filetype == 'neotest-output'")
        wait("return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'):find('assert 1 == 2', 1, true)")
        assert "test session starts" not in "\n".join(n.current.buffer[:])
        n.command("close")
    # File entries have no per-test report and should retain the complete log.
    n.exec_lua("for i,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do if line:find('test_pde_smoke.py',1,true) then vim.api.nvim_win_set_cursor(0,{i,0}); return end end; error('missing file row')")
    n.input(" to")
    wait("return vim.bo.filetype == 'neotest-output'")
    wait("return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false), '\\n'):find('test session starts',1,true)")
    n.command("close")
    n.exec_lua("require('neotest').summary.close()")
    # Debug the nearest pytest test through its new mapping and real adapter.
    n.current.window.cursor = (4, 0)
    n.exec_lua("""
      local dap = require('dap')
      require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 5)
      _G.neotest_stopped = false
      dap.listeners.after.event_stopped['neotest-test'] = function(_, event) _G.neotest_stopped = event.reason end
    """)
    n.input(" td")
    # event_stopped listeners can run before nvim-dap's asynchronous thread and
    # stack requests finish. Continue only when the breakpoint frame is ready.
    wait("local s = require('dap').session(); return _G.neotest_stopped == 'breakpoint' and s and s.stopped_thread_id and s.current_frame and s.current_frame.line == 5")
    n.exec_lua("require('dap').clear_breakpoints(); require('dap').continue()")
    wait("return require('dap').session() == nil")
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
    wait("local s = require('dap').session(); return _G.dap_stopped and s and s.stopped_thread_id and s.current_frame and s.current_frame.line == 2")
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
    # A separate unittest-only project must work without pytest installed.
    with tempfile.TemporaryDirectory(prefix="unittest-project-") as directory:
        unit_root = Path(directory).resolve()
        (unit_root / "pyproject.toml").write_text("")
        subprocess.run([sys.executable, "-m", "venv", "--without-pip", str(unit_root / ".venv")], check=True)
        (unit_root / "tests").mkdir()
        unit_file = unit_root / "tests" / "test_unit.py"
        unit_file.write_text("import unittest\nclass Example(unittest.TestCase):\n    def test_ok(self):\n        self.assertEqual(1, 1)\n    def test_bad(self):\n        self.assertEqual(1, 2)\n")
        (unit_root / "tests" / "test_other.py").write_text("import unittest\nclass Other(unittest.TestCase):\n    def test_ok(self):\n        self.assertTrue(True)\n")
        n.command("edit " + n.funcs.fnameescape(str(unit_file)))
        n.input(" ta")
        n.vars["unit_root"] = str(unit_root)
        counts = wait("local s = require('neotest').state; for _,id in ipairs(s.adapter_ids()) do if id:find(vim.g.unit_root, 1, true) then local c = s.status_counts(id); if c and c.passed == 2 and c.failed == 1 then return c end end end")
        assert counts["total"] == 3, counts
        # Change an existing test and add one outside Neovim: refresh must run both.
        unit_file.write_text(unit_file.read_text().replace("self.assertEqual(1, 2)", "self.assertEqual(1, 1)"))
        (unit_root / "tests" / "test_new.py").write_text("import unittest\nclass New(unittest.TestCase):\n    def test_new(self):\n        self.assertTrue(True)\n")
        n.input(" ta")
        counts = wait("local s = require('neotest').state; for _,id in ipairs(s.adapter_ids()) do if id:find(vim.g.unit_root, 1, true) then local c = s.status_counts(id); if c and c.passed == 4 and c.failed == 0 and c.running == 0 then return c end end end")
        assert counts["total"] == 4, counts

    print(
        "PASS: LSP project interpreter and restart, pytest and unittest discovery/pass/fail, debugpy breakpoint and project interpreter"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
