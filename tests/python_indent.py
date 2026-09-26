"""Exercise actual Enter indentation with the full config in Python and notebooks.

Run with the Neovim Python host (pynvim and nbformat required).
All source files are temporary; no kernels are started.
"""

import tempfile
import time
from pathlib import Path

import nbformat
import pynvim

# Prefix lines, expected next-line indentation. Dict continuation documents the
# built-in indenter's existing default rather than introducing custom rules.
CASES = [
    (["def foo(", "    x: int,"], 4),
    (["def foo(", "    x,"], 4),
    (["def foo(x: int) -> str:"], 4),
    (["def foo(", "    x: dict[str, int] | None = None,", ") -> list[str]:"], 4),
    (["class Model:", "    def forward(self, x: Tensor) -> Tensor:"], 8),
    (["if ready:", "    for item in items:"], 8),
    (["items = [", "    1,"], 4),
    (["items = [", "    1,", "]"], 0),
    (["values: dict[str, int] = {"], 8),
    (["def foo():", "    return 1"], 0),
]

with tempfile.TemporaryDirectory(prefix="nvim-indent-") as directory:
    root = Path(directory)
    python = root / "probe.py"
    python.write_text("pass\n")
    notebook = root / "probe.ipynb"
    original = nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_code_cell("if ready:\n    previous = 1"),
            nbformat.v4.new_markdown_cell("# Notes\n\n**Keep this Markdown.**"),
            nbformat.v4.new_code_cell("pass"),
        ]
    )
    nbformat.write(original, notebook)
    n = pynvim.attach(
        "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"]
    )
    try:
        n.ui_attach(110, 50, rgb=True)

        def wait(check):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if check():
                    return
                time.sleep(0.02)
            raise AssertionError("Timed out waiting for editor input")

        for path in (python, notebook):
            n.command("edit! " + n.funcs.fnameescape(str(path)))
            wait(lambda: n.current.buffer.options["filetype"] == "python")
            assert n.current.buffer.options["indentexpr"] in (
                "python#GetIndent(v:lnum)",
                "GetPythonIndent(v:lnum)",
            ), n.current.buffer.options["indentexpr"]
            assert n.current.buffer.options["shiftwidth"] == 4
            source = n.current.buffer[:]
            prefix = (
                source[
                    : max(i for i, line in enumerate(source) if line.startswith("# %%"))
                    + 1
                ]
                if path == notebook
                else []
            )
            for lines, expected in CASES:
                n.current.buffer[:] = prefix + lines
                n.current.window.cursor = (len(prefix) + len(lines), len(lines[-1]) - 1)
                n.input("A\rX")
                wait(lambda: n.current.buffer[-1].strip() == "X")
                n.input("\x1b")
                wait(lambda: n.funcs.mode() == "n")
                assert n.current.buffer[-1] == " " * expected + "X", (
                    path.suffix,
                    lines,
                    n.current.buffer[:],
                )
                assert n.current.buffer[: len(prefix)] == prefix
            # The = operator uses the same Python engine.
            n.current.buffer[:] = prefix + ["def foo(x: int) -> str:", "return str(x)"]
            n.current.window.cursor = (len(prefix) + 2, 0)
            n.command("normal! ==")
            assert n.current.buffer[-1] == "    return str(x)"
            n.current.buffer[:] = source
            if path == notebook:
                n.command("write")
                saved = nbformat.read(notebook, as_version=4)
                assert [(c.cell_type, c.source) for c in saved.cells] == [
                    (c.cell_type, c.source) for c in original.cells
                ]
            print(
                f"PASS {path.suffix}: typed/untyped signatures, blocks, brackets, continuation, = and source preservation"
            )
        # Other languages still receive Tree-sitter indentation.
        n.command("edit! " + str(root / "probe.lua"))
        assert "nvim-treesitter" in n.current.buffer.options["indentexpr"]
        print("PASS: Lua Tree-sitter indentation unchanged")
    finally:
        try:
            n.command("qa!")
        except (EOFError, OSError):
            pass
        n.close()
