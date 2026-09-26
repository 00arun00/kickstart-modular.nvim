"""Notebook cell titles: explicit metadata, comments, fallback, edits and save."""

import tempfile
import time
from pathlib import Path

import nbformat
import pynvim

with tempfile.TemporaryDirectory(prefix="notebook-titles-") as directory:
    path = Path(directory).resolve() / "titles.ipynb"
    notebook = nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_code_cell(
                "# Different comment\nload()",
                metadata={"title": "Load training dataset", "tags": ["training"]},
            ),
            nbformat.v4.new_code_cell(
                "\n# Build the dataloader\nloader = make_loader()"
            ),
            nbformat.v4.new_code_cell("model = Model()"),
            nbformat.v4.new_code_cell("", metadata={"tags": ["empty"]}),
            nbformat.v4.new_markdown_cell("# Results\n\nText"),
        ]
    )
    nbformat.write(notebook, path)
    n = pynvim.attach(
        "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
    )
    try:
        n.ui_attach(140, 50, rgb=True)
        time.sleep(0.3)
        source = n.current.buffer[:]

        def titles():
            return n.exec_lua(
                "local buf=vim.api.nvim_get_current_buf(); local cells=require('custom.python.cells_ui').scan(buf); local result={}; for _,c in ipairs(cells) do local s=require('custom.navigation.notebook').get_symbols(buf,vim.api.nvim_get_current_win(),{c.first+1,0}); table.insert(result,s[1].name) end return result"
            )

        assert titles() == [
            "01 Code · Load training dataset",
            "02 Code · Build the dataloader",
            "03 Code · model = Model()",
            "04 Code",
            "05 Markdown · Results",
        ], titles()
        marker = next(
            i
            for i, l in enumerate(source)
            if l.startswith("# %% Load training dataset")
        )
        assert "tags=" in source[marker]
        n.current.buffer[marker] = source[marker].replace(
            "Load training dataset", "Download dataset"
        )
        assert titles()[0] == "01 Code · Download dataset"
        n.command("write")
        saved = nbformat.read(path, as_version=4)
        assert saved.cells[0].metadata.title == "Download dataset"
        assert saved.cells[0].metadata.tags == ["training"]
        assert [(c.cell_type, c.source) for c in saved.cells] == [
            (c.cell_type, c.source) for c in notebook.cells
        ]
        # Reload through Jupytext, rather than only checking the JSON metadata.
        n.command("edit!")
        assert titles()[0] == "01 Code · Download dataset"
        # Marker options alone must never become a title, including opaque IDs.
        lines = n.current.buffer[:]
        empty = next(
            i for i, l in enumerate(lines) if l.startswith("# %%") and "empty" in l
        )
        n.current.buffer[empty] = '# %% id="opaque-cell-id" tags=["empty"]'
        assert titles()[3] == "04 Code"
        # Long/non-ASCII labels remain valid display text and are bounded.
        n.current.buffer[empty] = "# %% " + "分析 " * 50
        assert n.funcs.strchars(titles()[3]) <= 70
        print(
            "PASS: marker title priority, leading comments, code fallback, empty cells, metadata exclusion, live edits and notebook title/source roundtrip"
        )
    finally:
        try:
            n.command("qa!")
        except (EOFError, OSError):
            pass
        n.close()
