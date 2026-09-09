"""Markdown rendering/reveal and notebook source preservation with real plugins."""

import sys
import time
from pathlib import Path

import nbformat
import pynvim

project = Path(sys.argv[1]).resolve()
path = project / "pde-markdown.ipynb"
markdown = '# Results\n\nSome **bold**, *italic*, and `code`.\n\n- one\n- two\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n> A quote\n\n```python\nprint("example")\n```'
markdown += '\n\n<font color="red">Answer here.</font>\n\n```html\n<font color="red">Literal example</font>\n```'
code = 'value = 42\ntext = """\n# %% [markdown]\n# not a real cell\n"""\nprint(value)'
original = nbformat.v4.new_notebook(
    cells=[
        nbformat.v4.new_markdown_cell(markdown),
        nbformat.v4.new_code_cell(code),
        nbformat.v4.new_markdown_cell("## Second\n\nAnother paragraph."),
    ],
    metadata={"custom": {"keep": True}},
)
nbformat.write(original, path)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
)
try:
    n.exec_lua(
        "_G.md_messages={}; vim.notify=function(m) table.insert(_G.md_messages,m) end"
    )

    def wait(check):
        end = time.monotonic() + 15
        while time.monotonic() < end:
            if check():
                return
            time.sleep(0.1)
        raise AssertionError(n.exec_lua("return _G.md_messages"))

    wait(lambda: n.current.buffer.options["filetype"] == "python")
    n.ui_attach(120, 60, rgb=True)
    source = n.current.buffer[:]
    code_row = next(i for i, l in enumerate(source, 1) if l == "value = 42")
    md_row = next(i for i, l in enumerate(source, 1) if l == "# # Results")
    second_row = next(i for i, l in enumerate(source, 1) if l == "# ## Second")
    ns = n.api.create_namespace("python-notebook-markdown")

    def marks():
        return n.api.buf_get_extmarks(0, ns, 0, -1, {"details": True})

    n.current.window.cursor = (code_row, 0)
    n.exec_lua("require('custom.python.markdown').update()")
    wait(lambda: len(marks()) > 15)
    n.command("normal! zt")
    n.command("normal! 20\x19")
    n.command("redraw!")
    screen = n.exec_lua(
        "local lines={}; for r=1,60 do local line=''; for c=1,120 do line=line..vim.fn.screenstring(r,c) end; table.insert(lines,line) end return table.concat(lines,'\\n')"
    )
    assert "Results" in screen, screen
    assert "# # Results" not in screen, screen
    font_row = next(i for i, line in enumerate(source) if "Answer here." in line)
    literal_row = next(i for i, line in enumerate(source) if "Literal example" in line)
    font_marks = [
        m for m in marks() if m[1] == font_row and "conceal" in m[3] and m[2] >= 2
    ]
    assert len(font_marks) == 2, [m for m in marks() if m[1] == font_row]
    assert not any(
        m[1] == literal_row and "conceal" in m[3] and m[2] >= 2 for m in marks()
    )
    assert n.current.window.options["linebreak"]
    inactive = marks()
    assert any("RenderMarkdownH1" in str(m) for m in inactive)
    assert any("RenderMarkdownTable" in str(m) for m in inactive)
    assert any("@markup.strong" in str(m) for m in inactive)
    assert not any(code_row - 1 <= m[1] < second_row - 2 for m in inactive), inactive
    assert n.current.buffer[:] == source
    n.current.window.cursor = (md_row + 3, 0)
    n.exec_lua("require('custom.python.markdown').update()")
    assert not any(m[1] < code_row - 2 for m in marks()), marks()
    assert any(m[1] >= second_row - 2 for m in marks())
    n.command("redraw!")
    active_screen = n.exec_lua(
        "local lines={}; for r=1,60 do local line=''; for c=1,120 do line=line..vim.fn.screenstring(r,c) end; table.insert(lines,line) end return table.concat(lines,'\\n')"
    )
    assert "# # Results" in active_screen and "**bold**" in active_screen, active_screen

    n.exec_lua("require('custom.python.markdown').toggle()")
    assert not marks()
    n.exec_lua("require('custom.python.markdown').toggle()")
    n.current.buffer[md_row - 1] = "# # Edited Results"
    n.current.window.cursor = (code_row, 0)
    n.exec_lua("require('custom.python.markdown').update()")
    assert any("RenderMarkdownH1" in str(m) for m in marks())
    n.command("write")
    saved = nbformat.read(path, as_version=4)
    assert saved.cells[0].source == markdown.replace("# Results", "# Edited Results")
    assert saved.cells[1].source == code
    assert saved.metadata.custom.keep
    n.command("undo")
    n.exec_lua("require('custom.python.markdown').update()")
    assert n.current.buffer[md_row - 1] == "# # Results"
    # Ordinary comments must remain untouched.
    plain = project / "pde-plain.py"
    plain.write_text("# ordinary comment\nx=1\n")
    n.command("edit! " + n.funcs.fnameescape(str(plain)))
    assert not marks()
    assert n.current.window.options["concealcursor"] != "nvic"
    ordinary_md = project / "pde-ordinary.md"
    ordinary_md.write_text("# Ordinary Markdown\n\n**Still rendered**\n")
    n.command("edit " + n.funcs.fnameescape(str(ordinary_md)))
    n.exec_lua(
        "require('render-markdown').render({buf=vim.api.nvim_get_current_buf(), config={anti_conceal={enabled=false},render_modes=true}})"
    )
    wait(
        lambda: n.exec_lua(
            "local ns=require('render-markdown.core.ui').ns; return #vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{})>0"
        )
    )
    assert not marks()
    print(
        "PASS: Markdown headings/emphasis/tables, whole-cell reveal, toggle, code isolation, source/save/undo preservation, ordinary Python"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
