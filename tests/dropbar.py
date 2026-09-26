"""Exercise breadcrumb sources, notebook menus, fuzzy search, and split isolation."""

import tempfile
import time
from pathlib import Path

import nbformat
import pynvim

with tempfile.TemporaryDirectory(prefix="nvim-dropbar-") as directory:
    root = Path(directory).resolve()
    path = root / "navigation.ipynb"
    nb = nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_markdown_cell(
                "# Experiment\n\nA **rendered** introduction."
            ),
            nbformat.v4.new_code_cell(
                "class Model:\n    def forward(self, x: int) -> int:\n        return x + 1"
            ),
            nbformat.v4.new_markdown_cell("## Results\n\nCompare the output."),
            nbformat.v4.new_raw_cell("Reference notes"),
        ]
    )
    nbformat.write(nb, path)
    n = pynvim.attach(
        "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
    )
    try:
        n.ui_attach(140, 55, rgb=True)

        def wait(check):
            until = time.monotonic() + 10
            while time.monotonic() < until:
                if check():
                    return
                time.sleep(0.05)
            raise AssertionError(
                (
                    n.command_output("messages"),
                    n.current.buffer.name,
                    n.current.buffer[:],
                    n.funcs.mode(),
                )
            )

        def bar(win=None):
            return n.exec_lua(
                "local w=...; local b=require('dropbar.utils').bar.get({win=w or vim.api.nvim_get_current_win()}); if not b then return {} end; b:_update(); local t={}; for _,s in ipairs(b.components) do table.insert(t,s._.opts.name or s.name) end return t",
                win or n.current.window.handle,
            )

        def menu():
            return n.exec_lua(
                "return _G.dropbar.menus ~= nil and require('dropbar.utils').menu.get_current() ~= nil"
            )

        wait(
            lambda: n.current.buffer.options["filetype"] == "python" and len(bar()) > 0
        )
        source = n.current.buffer[:]
        code = next(i for i, s in enumerate(source, 1) if "return x" in s)
        notes = next(i for i, s in enumerate(source, 1) if s == "# ## Results")
        n.current.window.cursor = (code, 8)
        wait(lambda: any("forward" in s for s in bar()))
        labels = bar()
        assert any("02 Code" in s for s in labels), labels
        assert any("Model" in s for s in labels), labels
        firstwin = n.current.window.handle
        n.command("vsplit")
        secondwin = n.current.window.handle
        n.command("vertical resize 46")
        n.current.window.cursor = (notes, 0)
        labels = bar()
        assert any("03 Markdown" in s and "Results" in s for s in labels), labels
        assert not any("forward" in s for s in labels), labels
        assert any("02 Code" in s for s in bar(firstwin)), bar(firstwin)
        assert any("03 Markdown" in s for s in bar(secondwin)), bar(secondwin)
        # Jump to current cell start through the normal breadcrumb API.
        n.exec_lua("require('dropbar.api').goto_context_start()")
        assert n.current.window.cursor[0] == notes - 1
        n.current.window.cursor = (1, 0)  # all-cells menu also works from metadata
        n.exec_lua("require('custom.navigation.notebook').pick_cells()")
        wait(menu)
        assert (
            n.exec_lua("return #require('dropbar.utils').menu.get_current().entries")
            == 4
        )
        n.input("/")
        wait(
            lambda: n.exec_lua(
                "local m=require('dropbar.utils').menu.get_current(); return m and m.fzf_state ~= nil"
            )
        )
        n.input("Results")
        time.sleep(0.2)
        n.input("<CR>")
        wait(lambda: n.current.buffer.name == str(path) and not menu())
        assert n.current.window.cursor[0] == notes - 1, n.current.window.cursor
        # The advertised keyboard picker opens a path menu and returns cleanly.
        bar()
        n.input(" ;a")
        wait(menu)
        n.input("q")
        wait(lambda: not menu())
        assert n.current.window.handle == secondwin
        # Unsaved edits invalidate cached cell labels.
        n.current.buffer[notes - 1] = "# ## Updated results"
        labels = bar()
        assert any("Updated results" in s for s in labels), labels
        n.current.buffer[:] = source
        n.command("write")
        saved = nbformat.read(path, as_version=4)
        assert [(c.cell_type, c.source) for c in saved.cells] == [
            (c.cell_type, c.source) for c in nb.cells
        ]
        # Plain Markdown uses heading hierarchy, not notebook parsing.
        md = root / "notes.md"
        md.write_text("# Main\n\n## Detail\n\nText\n")
        n.command("edit " + str(md))
        n.current.window.cursor = (5, 0)
        wait(lambda: any("Detail" in s for s in bar()))
        assert any("Main" in s for s in bar()), bar()
        # Plain Python fallback works with its Tree-sitter parser even before LSP.
        py = root / "model.py"
        py.write_text("class Plain:\n    def method(self):\n        return 1\n")
        n.command("edit " + str(py))
        n.current.window.cursor = (3, 8)
        wait(lambda: any("method" in s for s in bar()))
        time.sleep(
            1
        )  # Let initial LSP/attachment refreshes settle before opening a menu.
        # Enter selects the named scope; l opens its child submenu.
        labels = bar()
        class_index = next(i for i, s in enumerate(labels, 1) if "Plain" in s)
        n.exec_lua("require('dropbar.api').pick(...)", class_index)
        wait(menu)
        n.input("l")
        time.sleep(0.1)
        n.input("<CR>")
        wait(lambda: not menu())
        assert n.current.buffer.name == str(py)
        assert n.current.window.cursor[0] == 2, (
            n.current.window.cursor,
            labels,
            n.command_output("messages"),
        )
        floatwin = n.api.open_win(
            n.current.buffer,
            False,
            {
                "relative": "editor",
                "row": 2,
                "col": 2,
                "width": 30,
                "height": 5,
                "style": "minimal",
            },
        )
        assert not n.exec_lua(
            "return require('dropbar.configs').opts.bar.enable(vim.api.nvim_get_current_buf(),...)",
            floatwin.handle,
        )
        n.api.win_close(floatwin, True)
        # A nofile output split and a floating source window must be excluded.
        scratch = n.api.create_buf(False, True)
        n.api.win_set_buf(0, scratch)
        assert not n.exec_lua(
            "return require('dropbar.configs').opts.bar.enable(vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win())"
        )
        assert n.current.window.options["winbar"] == "", n.current.window.options[
            "winbar"
        ]
        print(
            "PASS: Python scopes, Markdown headings, notebook types/titles, split independence, cell menu, fuzzy jump, cache invalidation, unchanged save and scratch exclusion"
        )
    finally:
        try:
            n.command("qa!")
        except (EOFError, OSError):
            pass
        n.close()
