"""Real workflows, dispatched in separate process groups by test_python_tools."""

import subprocess
import sys
from pathlib import Path

from python_editor import Editor


def venv(path):
    subprocess.run(
        [sys.executable, "-m", "venv", "--without-pip", str(path)], check=True
    )
    return path / "bin/python"


def lsp(editor, project, delayed=False):
    (project / ".venv").unlink()
    environments = [project / ".venv", project / "alternate"]
    modules = []
    for index, environment in enumerate(environments):
        python = venv(environment)
        site = Path(
            subprocess.check_output(
                [
                    python,
                    "-c",
                    "import sysconfig; print(sysconfig.get_path('purelib'))",
                ],
                text=True,
            ).strip()
        )
        module = site / "robustness_env.py"
        module.write_text(f"VALUE = {index}\n")
        modules.append(module)
    source = project / "environment.py"
    source.write_text("import robustness_env\nvalue = robustness_env.VALUE\n")
    gate = project / "release-lsp"
    if delayed:
        editor.lua(
            """
          local python, proxy, gate = ...
          local cmd = vim.lsp.config.basedpyright.cmd
          vim.lsp.config('basedpyright', {cmd=vim.list_extend({python, proxy, gate}, cmd)})
        """,
            sys.executable,
            str(Path(__file__).with_name("lsp_gate.py")),
            str(gate),
        )
    editor.edit(source)
    if delayed:
        # Two initialized unrelated clients deliberately satisfy the old wait.
        editor.lua("""
          for i=1,2 do
            vim.lsp.start({name='robustness-extra-'..i, cmd=function(dispatchers)
              local stopped=false
              return {
                request=function(method, params, callback)
                  vim.schedule(function() callback(nil, method=='initialize' and {capabilities={}} or nil) end)
                  return true, 1
                end,
                notify=function() return true end,
                is_closing=function() return stopped end,
                terminate=function() stopped=true; dispatchers.on_exit(0,0) end,
              }
            end})
          end
        """)
        editor.wait(
            "unrelated clients ready while BasedPyright is gated",
            """
          local b=...
          return #vim.lsp.get_clients({name='robustness-extra-1',bufnr=b})==1
            and #vim.lsp.get_clients({name='robustness-extra-2',bufnr=b})==1
        """,
            editor.buffer,
        )
        assert (
            editor.lua(
                "return #vim.lsp.get_clients({name='basedpyright',bufnr=...})",
                editor.buffer,
            )
            == 0
        )
        gate.touch()

    old = -1
    for environment, module in zip(environments, modules):
        if old != -1:
            editor.nvim.command(
                "PyVenvSet " + editor.nvim.funcs.fnameescape(str(environment))
            )
        client = editor.wait(
            "BasedPyright with selected environment",
            """
          local b, python, old = ...
          local c=vim.lsp.get_clients({name='basedpyright',bufnr=b})[1]
          return c and c.id~=old and c.initialized and c.settings.python
            and c.settings.python.pythonPath==python and c.id
        """,
            editor.buffer,
            str(environment / "bin/python"),
            old,
        )
        # Prove the server resolves imports from the selected environment, not
        # merely that the Lua settings table contains the desired string.
        editor.lua(
            """
          local id,b=...
          _G.definition=nil
          local accepted=vim.lsp.get_client_by_id(id):request('textDocument/definition', {
            textDocument={uri=vim.uri_from_bufnr(b)}, position={line=0,character=10}
          }, function(err,result) _G.definition={error=err,result=result or {}} end, b)
          assert(accepted, 'definition request rejected')
        """,
            client,
            editor.buffer,
        )
        definition = editor.wait(
            "definition response from selected environment", "return _G.definition"
        )
        assert not definition.get("error"), definition
        assert str(module) in str(definition["result"]), definition
        old = client


def pytest_file(project):
    source = project / "test_pde_smoke.py"
    source.write_text("""import sys
from pathlib import Path

def test_environment():
    assert Path(sys.prefix) == Path(__file__).parent / ".venv"

def test_failure_is_reported():
    assert 1 == 2
""")
    return source


def pytest_run(editor, project):
    source = pytest_file(project)
    editor.observe_runs()
    editor.edit(source)
    expected = {
        str(source) + "::test_environment": "passed",
        str(source) + "::test_failure_is_reported": "failed",
    }
    editor.run(" tf", project, expected)
    # An identical second run must produce new completions, not reuse counts.
    editor.run(" tf", project, expected)
    editor.wait(
        "navigation mapping installed",
        "return vim.fn.maparg(']f','n',false,true).buffer==1",
    )
    editor.nvim.current.window.cursor = (1, 0)
    source_window = editor.nvim.current.window.handle
    editor.key("]f")
    preview = editor.wait(
        "failed-test preview",
        """
      for _,w in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[w].test_navigation_preview then return w end
      end
    """,
    )
    assert editor.nvim.current.window.handle == source_window
    assert editor.nvim.current.window.cursor[0] == 7
    assert not editor.nvim.api.win_get_config(preview)["focusable"]
    text = "\n".join(
        editor.nvim.api.buf_get_lines(
            editor.nvim.api.win_get_buf(preview), 0, -1, False
        )
    )
    assert "assert 1 == 2" in text, text
    editor.key(" to")
    editor.wait("failure output popup", "return vim.bo.filetype=='neotest-output'")
    editor.wait(
        "per-test failure report",
        "return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),'\\n'):find('assert 1 == 2',1,true)",
    )
    text = "\n".join(editor.nvim.current.buffer[:])
    assert "test_environment" not in text and "test session starts" not in text, text


def unittest_run(editor, project):
    (project / ".venv").unlink()
    python = venv(project / ".venv")
    subprocess.run(
        [
            python,
            "-c",
            "import importlib.util; assert importlib.util.find_spec('pytest') is None",
        ],
        check=True,
    )
    tests = project / "tests"
    tests.mkdir()
    source = tests / "test_unit.py"
    source.write_text(
        "import unittest\nclass Example(unittest.TestCase):\n    def test_ok(self):\n        self.assertEqual(1, 1)\n    def test_bad(self):\n        self.assertEqual(1, 2)\n"
    )
    other = tests / "test_other.py"
    other.write_text(
        "import unittest\nclass Other(unittest.TestCase):\n    def test_ok(self):\n        self.assertTrue(True)\n"
    )
    editor.observe_runs()
    editor.edit(source)
    expected = {
        str(source) + "::Example::test_ok": "passed",
        str(source) + "::Example::test_bad": "failed",
        str(other) + "::Other::test_ok": "passed",
    }
    baseline = editor.run(" ta", project, expected)
    results = editor.results(project, expected, baseline)
    report = str(results[str(source) + "::Example::test_bad"].get("errors"))
    assert "1 != 2" in report and "Ran 2 tests" not in report, report
    # Change one existing result and add a file outside Neovim. Every expected
    # test must complete in this new run, including the unchanged passing test.
    source.write_text(
        source.read_text().replace("self.assertEqual(1, 2)", "self.assertEqual(1, 1)")
    )
    added = tests / "test_new.py"
    added.write_text(
        "import unittest\nclass New(unittest.TestCase):\n    def test_new(self):\n        self.assertTrue(True)\n"
    )
    expected = {id: "passed" for id in expected}
    expected[str(added) + "::New::test_new"] = "passed"
    editor.run(" ta", project, expected)


def stopped(editor, source, line):
    editor.wait(
        "debugger paused in expected source frame",
        """
      local file,line=...
      local s=require('dap').session()
      local f=s and s.current_frame
      return s and s.stopped_thread_id and f and f.line==line and f.source and f.source.path==file
    """,
        str(source),
        line,
    )
    editor.lua("""
      _G.debug_evaluation=nil
      require('dap').session():request('evaluate', {expression='sys.executable',context='repl'},
        function(err,result) _G.debug_evaluation={error=err,result=result} end)
    """)
    result = editor.wait("debug interpreter evaluation", "return _G.debug_evaluation")
    assert not result.get("error"), result
    return result["result"]["result"]


def debug_file(editor, project):
    source = project / "program.py"
    source.write_text("import sys\nvalue = 42\nprint(value)\n")
    editor.edit(source)
    editor.lua(
        """
      require('lazy').load({plugins={'nvim-dap'}})
      local dap=require('dap')
      require('dap.breakpoints').set({}, ..., 2)
      local config=vim.deepcopy(dap.configurations.python[1])
      config.console='internalConsole'
      dap.run(config)
    """,
        editor.buffer,
    )
    assert str(project / ".venv/bin/python") in stopped(editor, source, 2)
    editor.lua("require('dap').clear_breakpoints(); require('dap').continue()")
    editor.wait("debugger exit", "return require('dap').session()==nil")


def debug_test(editor, project):
    source = pytest_file(project)
    editor.observe_runs()
    editor.edit(source)
    editor.nvim.current.window.cursor = (4, 0)
    editor.discovered(project, {str(source) + "::test_environment": "passed"})
    editor.lua("require('dap.breakpoints').set({}, ..., 5)", editor.buffer)
    baseline = editor.lua("return _G.test_runs.serial")
    editor.key(" td")
    assert str(project / ".venv/bin/python") in stopped(editor, source, 5)
    editor.lua("require('dap').clear_breakpoints(); require('dap').continue()")
    editor.wait("debugger exit", "return require('dap').session()==nil")
    editor.results(project, {str(source) + "::test_environment": "passed"}, baseline)


if __name__ == "__main__":
    scenario, directory = sys.argv[1:]
    project = Path(directory).resolve()
    with Editor() as editor:
        # Set stale shell activation before opening the project / starting LSPs.
        editor.lua(
            "vim.env.VIRTUAL_ENV=vim.fs.dirname(vim.fs.dirname(require('custom.python.host').executable('python')))"
        )
        if scenario.startswith("lsp"):
            lsp(editor, project, delayed=scenario == "lsp-delayed")
        else:
            {
                "pytest": pytest_run,
                "unittest": unittest_run,
                "debug-file": debug_file,
                "debug-test": debug_test,
            }[scenario](editor, project)
    print("PASS:", scenario)
