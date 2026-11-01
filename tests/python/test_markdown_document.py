"""Retained document lifecycle with real parsing, placements and emitted UI grids.

Conversion is controlled so tests force stale completions without TeX processes.
The grid contains image placeholders, not terminal-side decoded image pixels.
"""

import os
import warnings
from pathlib import Path

import pynvim
import pytest

pytestmark = [pytest.mark.integration, pytest.mark.python]

SOURCE = [f"Source line {i:03d}: ordinary prose." for i in range(1, 191)]
SOURCE[39:42] = ["$$", "a+b=c", "$$"]
SOURCE[64:67] = ["$$", "a+b=c", "$$"]
SOURCE[88] = ""
SOURCE[93] = ""
SOURCE[89:93] = [
    "| Quantity | Equation |",
    "| --- | --- |",
    "| **Mass** | $$m=n$$ |",
    "| Momentum | $$p=q$$ |",
]
SOURCE[139:142] = ["$$", "x+y=z", "$$"]


@pytest.fixture
def document(tmp_path, monkeypatch, pytestconfig):
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data /= os.environ.get("NVIM_APPNAME", "nvim")
    for name in ("STATE", "CACHE", "DATA"):
        monkeypatch.setenv(f"XDG_{name}_HOME", str(tmp_path / name.lower()))
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        n.ui_attach(100, 24, rgb=True, ext_linegrid=True)
        n.exec_lua(
            "local root,data,source=...; assert(loadfile(root..'/tests/support/markdown_reading.lua'))(root,data,source)",
            str(pytestconfig.rootpath), str(data), SOURCE,
        )
        wait(n, "require('custom.markdown.document').status(reading_fixture.buf).ready")
        n.current.window.options["scrolloff"] = 0
        yield n
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()


def wait(n, condition):
    assert n.exec_lua("return vim.wait(5000,function()return " + condition + " end)"), condition


class GridFrames:
    """Decode every published flush, including transient frames between RPCs."""

    def __init__(self):
        self.grids = {}
        self.frames = []

    def consume(self, n):
        pending = n._session._pending_messages
        while pending:
            message = pending.popleft()
            if message.type != "notification" or message.name != "redraw":
                continue
            for event in message.args:
                name = event[0]
                for args in event[1:]:
                    if name == "grid_resize":
                        grid, width, height = args
                        self.grids[grid] = [[" "] * width for _ in range(height)]
                    elif name == "grid_clear":
                        grid = args[0]
                        self.grids[grid] = [[" "] * len(row) for row in self.grids[grid]]
                    elif name == "grid_line":
                        grid, row, col, cells = args[:4]
                        for cell in cells:
                            for _ in range(cell[2] if len(cell) > 2 else 1):
                                self.grids[grid][row][col] = cell[0]
                                col += 1
                    elif name == "grid_scroll":
                        grid, top, bottom, left, right, rows, cols = args
                        previous = [row[:] for row in self.grids[grid]]
                        for row in range(top, bottom):
                            for col in range(left, right):
                                source_row, source_col = row + rows, col + cols
                                self.grids[grid][row][col] = (
                                    previous[source_row][source_col]
                                    if top <= source_row < bottom and left <= source_col < right else " "
                                )
                    elif name == "flush" and 1 in self.grids:
                        self.frames.append("\n".join("".join(row) for row in self.grids[1]))


def test_first_visit_scroll_publishes_math_and_late_table_without_source_frames(document):
    n = document
    assert n.current.window.cursor[0] < 40
    frames = GridFrames()
    frames.consume(n)
    frames.frames.clear()
    for key, count in [("<C-e>", 150), ("<C-y>", 150)]:
        for _ in range(count):
            n.input(key)
            n.command("redraw!")
            frames.consume(n)
    assert frames.frames, "no actual UI frames were captured"
    assert all("$" not in frame for frame in frames.frames), "source math was published during reading"
    assert any("\U0010eeee" in frame for frame in frames.frames), "concealed blank rows are not rendered math"
    assert any("│" in frame and "Mass" in frame for frame in frames.frames), "the late table never appeared"
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_deliberate_edit_rebuilds_equation_and_preserves_native_source_motion(document):
    n = document
    n.current.window.cursor = (41, 0)
    n.command("normal! yy")
    assert n.funcs.getreg('"').rstrip("\n") == "a+b=c"
    n.input("i+")
    wait(n, "vim.fn.mode()=='i' and vim.api.nvim_get_current_line()=='+a+b=c'")
    assert n.current.line == "+a+b=c"
    n.input("<Esc>")
    wait(n, "require('custom.markdown.document').status(reading_fixture.buf).ready")
    assert n.exec_lua("return reading_fixture.table_rendered()")
    assert n.current.window.cursor[0] == 41
    assert n.current.line == "+a+b=c"
    n.input("2j")
    n.command("redraw!")
    assert n.current.window.cursor[0] == 43
    assert list(n.current.buffer)[40] == "+a+b=c"


def hold_discovery(n):
    n.exec_lua("""
      document_held={}
      document_hold=true
      local find=Snacks.image.doc.find
      Snacks.image.doc.find=function(buf,callback,opts)
        find(buf,function(items)
          if document_hold then document_held[#document_held+1]=function()callback(items)end else callback(items)end
        end,opts)
      end
    """)


def test_late_discovery_after_edit_cannot_restore_previous_source(document):
    n = document
    hold_discovery(n)
    n.exec_lua("reading_fixture.controller:update(true)")
    wait(n, "#document_held>0")
    n.exec_lua("""
      document_hold=false
      vim.api.nvim_buf_set_lines(reading_fixture.buf,40,41,false,{'replacement=answer'})
      reading_fixture.controller:update(true)
    """)
    # Discovery is serialized: release the obsolete request before the queued
    # current revision can parse. The obsolete callback must never publish.
    n.exec_lua("for _,callback in ipairs(document_held)do callback()end")
    wait(n, "require('custom.markdown.document').status(reading_fixture.buf).ready")
    assert n.exec_lua("return require('custom.markdown.document').status(reading_fixture.buf).ready")
    assert n.current.buffer[40] == "replacement=answer"
    assert n.exec_lua("""
      for _,p in pairs(reading_fixture.controller.imgs)do
        if p.opts.range[1]==40 then return table.concat(vim.fn.readfile(p.img.src),'\\n'):find('replacement=answer',1,true)~=nil end
      end
      return false
    """)


def test_closing_during_conversion_releases_interest_and_rejects_completion(document):
    n = document
    n.exec_lua("""
      reading_fixture.transport.hold=true
      vim.api.nvim_buf_set_lines(reading_fixture.buf,140,141,false,{'pending=closed'})
      reading_fixture.controller:update(true)
    """)
    wait(n, "#reading_fixture.transport.pending>0")
    buf = n.current.buffer.number
    n.command("enew!")
    n.api.buf_delete(buf, {"force": True})
    n.exec_lua("reading_fixture.transport.finish_all()")
    assert n.exec_lua("return reading_fixture.controller.closed==true")
    assert n.exec_lua("return vim.tbl_isempty(reading_fixture.controller.imgs)")
    assert n.exec_lua("""
      for _,img in pairs(reading_fixture.images)do
        if not vim.tbl_isempty(img.placements)then return false end
      end
      return true
    """)


def test_failed_equation_leaves_source_usable_after_scrolling(document):
    n = document
    n.exec_lua("""
      reading_fixture.transport.hold=true
      vim.api.nvim_buf_set_lines(reading_fixture.buf,140,141,false,{'broken=source'})
      reading_fixture.controller:update(true)
    """)
    wait(n, "#reading_fixture.transport.pending>0")
    n.exec_lua("reading_fixture.transport.finish_all(true)")
    wait(n, "require('custom.markdown.document').status(reading_fixture.buf).failed>0")
    n.current.window.cursor = (140, 0)
    n.command("normal! zt")
    for _ in range(5):
        n.input("<C-e>")
        n.command("redraw!")
    assert n.current.buffer[140] == "broken=source"
    n.current.window.cursor = (141, 0)
    n.input("i")
    wait(n, "vim.fn.mode()=='i'")
    assert n.current.line == "broken=source"


def test_late_conversion_cannot_restore_old_theme_after_new_revision_is_ready(document):
    n = document
    n.exec_lua("""
      reading_fixture.transport.hold=true
      vim.api.nvim_set_hl(0,'SnacksImageMath',{fg='#123456'})
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='document-old-theme'})
    """)
    wait(n, "#reading_fixture.transport.pending>0")
    n.exec_lua("""
      document_old_conversions=reading_fixture.transport.pending
      reading_fixture.transport.pending={}
      vim.api.nvim_set_hl(0,'SnacksImageMath',{fg='#ABCDEF'})
      vim.api.nvim_exec_autocmds('ColorScheme',{pattern='document-new-theme'})
    """)
    wait(n, "#reading_fixture.transport.pending>0")
    n.exec_lua("reading_fixture.transport.finish_all()")
    wait(n, "require('custom.markdown.document').status(reading_fixture.buf).ready")
    n.exec_lua("""
      reading_fixture.transport.pending=document_old_conversions
      reading_fixture.transport.finish_all()
    """)
    assert n.exec_lua("return require('custom.markdown.document').status(reading_fixture.buf).ready")
    assert n.exec_lua(r"""
      local count=0
      for src,img in pairs(reading_fixture.images)do
        if not vim.tbl_isempty(img.placements)then
          count=count+1
          local tex=table.concat(vim.fn.readfile(src),'\n')
          if not tex:find('\\color[HTML]{ABCDEF}',1,true)then return false end
        end
      end
      return count>0
    """)


def test_rapid_cached_style_and_refresh_republishes_retained_table(document):
    n = document
    for _ in range(3):
        # No palette or source changes: all assets are cached. Closely spaced
        # revisions must still complete the host/table publication handshake.
        n.exec_lua("""
          vim.api.nvim_exec_autocmds('ColorScheme',{pattern='document-cached-style'})
          reading_fixture.controller:update(true)
          reading_fixture.controller:update(true)
        """)
        wait(n, "require('custom.markdown.document').status(reading_fixture.buf).ready")
        assert n.exec_lua("return reading_fixture.table_rendered()")
    assert n.exec_lua("return reading_fixture.source_unchanged()")
