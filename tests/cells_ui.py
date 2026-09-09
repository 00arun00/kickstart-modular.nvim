"""Verify cell frames in Neovim's rendered grid without changing notebook text."""

import sys
import time
from pathlib import Path

import nbformat
import pynvim

project = Path(sys.argv[1]).resolve()
path = project / "pde-cell-frames.ipynb"
notebook = nbformat.v4.new_notebook(
    cells=[
        nbformat.v4.new_markdown_cell("# Introduction\n\nA **rendered** cell."),
        nbformat.v4.new_code_cell(
            'x = 42\ntext = """\n# %% [markdown]\nnot a cell\n"""\nprint(x)'
        ),
        nbformat.v4.new_raw_cell("Raw text stays raw."),
    ]
)
nbformat.write(notebook, path)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
)
try:
    n.ui_attach(120, 60, rgb=True)
    time.sleep(0.3)
    source = n.current.buffer[:]

    def render(row):
        n.current.window.cursor = (row, 0)
        n.exec_lua(
            "require('custom.python.markdown').update(); require('custom.python.cells_ui').update(nil,true)"
        )
        n.command("normal! zz")
        n.command("redraw!")
        return n.exec_lua(
            "local lines={}; for r=1,60 do local line=''; for c=1,120 do line=line..vim.fn.screenstring(r,c) end; table.insert(lines,line) end return table.concat(lines,'\\n')"
        )

    code_row = next(i for i, l in enumerate(source, 1) if l == "x = 42")
    screen = render(code_row)
    assert (
        "01 · Markdown" in screen
        and "02 · Code · active" in screen
        and "03 · Raw" in screen
    ), screen
    assert "04 " not in screen
    assert "╭" not in screen and "╰" not in screen, screen
    assert "id=" not in screen, screen
    assert "Introduction" in screen and "# # Introduction" not in screen, screen
    markdown_row = next(i for i, l in enumerate(source, 1) if l == "# # Introduction")
    screen = render(markdown_row)
    assert "01 · Markdown · active" in screen and "# # Introduction" in screen, screen
    marker_row = markdown_row - 1
    screen = render(marker_row)
    assert "# %% [markdown]" in screen and "01 · Markdown · active" in screen, screen
    assert n.current.buffer[:] == source
    n.command("write")
    saved = nbformat.read(path, as_version=4)
    assert [(c.cell_type, c.source) for c in saved.cells] == [
        (c.cell_type, c.source) for c in notebook.cells
    ]
    # Concealed media/block ranges must not swallow the following header.
    n.exec_lua(
        "local ns=vim.api.nvim_create_namespace('test-concealed-body'); vim.api.nvim_buf_set_extmark(0,ns,...,0,{end_row=(...)+1,conceal_lines=''})",
        markdown_row - 1,
    )
    assert "01 · Markdown" in render(code_row)
    # Long metadata must not leak or consume wrapped blank rows.
    n.current.buffer[marker_row - 1] += ' id="' + "long-marker-" * 20 + '"'
    assert "long-marker-" not in render(code_row)
    # Narrow split frames fit inside the source text area.
    n.command("vsplit")
    n.command("vertical resize 36")
    render(code_row)
    ns = n.api.create_namespace("python-cell-frames")
    marks = n.api.buf_get_extmarks(0, ns, 0, -1, {"details": True})
    for mark in marks:
        for chunks in (
            [mark[3]["virt_text"]]
            if "virt_text" in mark[3]
            else mark[3].get("virt_lines", [])
        ):
            assert n.funcs.strdisplaywidth("".join(c[0] for c in chunks)) <= 36
    print(
        "PASS: typed/numbered frames, active state, source-marker editing, Markdown coexistence, fake-marker isolation, narrow splits and unchanged notebook save"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
