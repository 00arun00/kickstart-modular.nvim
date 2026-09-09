"""Run with the editor host Python; pass a disposable uv project with ipykernel/ruff.

Usage: ~/.local/share/nvim/python/bin/python tests/notebook.py '/tmp/test project'
Requires installed plugins and :UpdateRemotePlugins. Only writes test notebooks.
"""

import sys
import time
from pathlib import Path

import nbformat
import pynvim

project = Path(sys.argv[1]).resolve()
notebook = project / "pde-smoke.ipynb"
code = "import os, sys\nprint(sys.executable)\nprint(os.getcwd())\nprint(6 * 7)"
nb = nbformat.v4.new_notebook(
    cells=[
        nbformat.v4.new_markdown_cell("# PDE smoke test", metadata={"tags": ["keep"]}),
        nbformat.v4.new_code_cell(
            code,
            metadata={"tags": ["check"]},
            outputs=[
                nbformat.v4.new_output("stream", name="stdout", text="saved output\n")
            ],
            execution_count=1,
        ),
        nbformat.v4.new_code_cell("print(43)"),
    ],
    metadata={
        "kernelspec": {
            "name": "python3",
            "display_name": "Python 3",
            "language": "python",
        },
        "custom": {"keep": True},
    },
)
nbformat.write(nb, notebook)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-i", "NONE", str(notebook)]
)
try:
    n.exec_lua(
        "_G.test_notifications = {}; vim.notify = function(msg) table.insert(_G.test_notifications, msg) end"
    )
    assert n.current.buffer.options["filetype"] == "python", n.current.buffer[:]
    assert "# %%" in "\n".join(n.current.buffer[:])
    n.command("write")
    saved = nbformat.read(notebook, as_version=4)
    assert saved.cells[0].source == "# PDE smoke test"
    assert saved.cells[0].metadata.tags == ["keep"]
    assert saved.metadata.custom.keep is True
    assert saved.cells[1].outputs[0].text == "saved output\n"
    n.exec_lua("require('conform').format({async=false, timeout_ms=10000})")
    n.command("write")
    saved = nbformat.read(notebook, as_version=4)
    assert "import os\nimport sys" in saved.cells[1].source, saved.cells[1].source
    n.exec_lua("require('custom.python.notebook').init()")
    assert n.exec_lua("return #vim.fn.MoltenRunningKernels(true)") == 1, n.exec_lua(
        "return _G.test_notifications"
    )
    assert n.exec_lua(
        "return vim.wait(15000, function() return next(require('custom.python.notebook').ready) ~= nil end, 50)"
    )
    # Run through the cell helper, exercising the same path as <leader>jc.
    line = next(
        i for i, value in enumerate(n.current.buffer[:], 1) if value == "import os"
    )
    n.current.window.cursor = (line, 0)
    n.exec_lua("require('custom.python.notebook').run(true)")
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        time.sleep(0.3)
        n.exec_lua("require('custom.python.notebook').export()")
        result = nbformat.read(notebook, as_version=4)
        output = "".join(
            o.get("text", o.get("data", {}).get("text/plain", ""))
            for c in result.cells
            if c.cell_type == "code"
            for o in c.outputs
        )
        if "42" in output and "43" in output:
            break
    else:
        raise AssertionError(
            f"No kernel output: {output}\n{n.exec_lua('return _G.test_notifications')}"
        )
    assert str(project / ".venv/bin/python") in output, output
    assert str(project) in output, output
    n.exec_lua("require('custom.python.notebook').restart()")
    assert n.exec_lua(
        "return vim.wait(15000, function() return next(require('custom.python.notebook').ready) ~= nil end, 50)"
    )
    n.command("MoltenDeinit")
    n.command("edit!")
    assert n.current.buffer.options["filetype"] == "python"
    assert any("print(6 * 7)" in line for line in n.current.buffer[:])
    # New notebooks also need the conversion write handler.
    fresh = project / "pde-new.ipynb"
    fresh.unlink(missing_ok=True)
    n.command("edit " + n.funcs.fnameescape(str(fresh)))
    n.command("write")
    nbformat.validate(nbformat.read(fresh, as_version=4))
    n.current.buffer.append(["# %%", "pde_undefined_name"])
    n.command("write")
    assert n.exec_lua("""return vim.wait(15000, function()
      for _, d in ipairs(vim.diagnostic.get(0)) do
        if d.message:find('pde_undefined_name', 1, true) then return true end
      end
      return false
    end, 100)"""), n.command_output("messages")
    assert n.exec_lua(
        "return vim.wait(10000, function() local sources = {}; for _,d in ipairs(vim.diagnostic.get(0)) do sources[d.source] = true end; return sources.basedpyright and sources.Ruff end, 100)"
    )
    foreign = project / "pde-foreign.ipynb"
    other = nbformat.v4.new_notebook(
        cells=[nbformat.v4.new_code_cell("x <- 1")],
        metadata={"kernelspec": {"name": "ir", "display_name": "R", "language": "R"}},
    )
    nbformat.write(other, foreign)
    n.command("edit " + n.funcs.fnameescape(str(foreign)))
    assert n.current.buffer.options["filetype"] == "json"
    n.command("write")
    assert nbformat.read(foreign, as_version=4).cells[0].source == "x <- 1"

    print(
        "PASS: open/save/new notebook, metadata/outputs, Ruff formatting, Molten execution, project interpreter/cwd, export/reopen, restart, diagnostics, foreign notebooks"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
