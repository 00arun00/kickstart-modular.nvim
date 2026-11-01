"""Native reading layout: visible geometry, source ownership, and image continuity.

These tests use actual Neovim redraw grids and controlled image transport.
They run independently of the optional rich Markdown view and its toolchain.
"""

import os
import re
import warnings
from pathlib import Path

import pynvim
import pytest

from test_markdown_document import GridFrames

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.python, pytest.mark.integration]


@pytest.fixture
def native_design_editor(tmp_path, monkeypatch):
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data /= os.environ.get("NVIM_APPNAME", "nvim")
    if not (data / "lazy/snacks.nvim").is_dir():
        pytest.skip("native design geometry needs installed Neovim plugins")
    for name in ("STATE", "CACHE", "DATA"):
        monkeypatch.setenv(f"XDG_{name}_HOME", str(tmp_path / name.lower()))
    source = [
        "# Native display alignment", "", "Inline $a+b=c$ stays in prose.", "",
        "$$", "a+b=c", "$$", "", "$$a+b=c$$", "",
        "> $$", r"> a+b=c\quad x>0", "> $$", "",
        "1. A list equation:", "", "   $$", "   a+b=c", "   $$", "", "Ending prose.",
        "", "Before $$a+b=c$$ after.",
    ]
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        editor = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        editor.ui_attach(100, 60, rgb=True, ext_linegrid=True)
        editor.exec_lua(
            "local root,data,source=...;assert(loadfile(root..'/tests/support/markdown_reading.lua'))(root,data,source)",
            str(ROOT), str(data), source,
        )
        assert editor.exec_lua("return vim.wait(5000,function()return require('custom.markdown.document').status(reading_fixture.buf).ready end)")
        yield editor, source
    finally:
        try:
            editor.command("qa!")
        except EOFError:
            pass
        editor.close()



@pytest.mark.parametrize("columns", [100, 72])
def test_native_display_placeholders_center_without_changing_source(native_design_editor, columns):
    editor, source = native_design_editor
    if columns != 100:
        editor.ui_try_resize(columns, 60)
    editor.command("redraw!")
    assert editor.exec_lua("return vim.wait(5000,function()return require('custom.markdown.document').status(reading_fixture.buf).ready end)")
    frames = GridFrames()
    frames.consume(editor)
    grid = frames.grids[1]
    geometry = editor.exec_lua('''
      local values={}
      for _,p in pairs(reading_fixture.controller.imgs)do
        local r=p.opts.range
        values[#values+1]={first=r[1],width=p._state.loc.width,offset=p._state.loc[2],src=p.img.src,inline=p.img.src:match('inline%-math%.tex$')~=nil}
      end
      local info=vim.fn.getwininfo(reading_fixture.win)[1]
      return {images=values,textoff=info.textoff,width=info.width}
    ''')
    text_width = geometry["width"] - geometry["textoff"]
    expected_insets = {5: 0, 9: 0, 11: 2, 17: 3}
    displays = [item for item in geometry["images"] if item["first"] in expected_insets]
    assert len(displays) == 4
    expected_offsets = []
    for item in displays:
        inset = expected_insets[item["first"]]
        expected = inset + (text_width - inset - item["width"]) // 2
        # Native terminal-cell rounding and a sign gutter that settles after
        # initial placement can differ by one column, never a paragraph width.
        assert abs(item["offset"] - expected) <= 1, f"source row {item['first']} is not centered in its native content area"
        expected_offsets.append(item["offset"] + geometry["textoff"])
    actual_offsets = [
        min(x for x, cell in enumerate(row) if "\U0010eeee" in cell)
        for row in grid if sum("\U0010eeee" in cell for cell in row) >= 20
    ]
    assert actual_offsets, "no rendered display placeholders reached the native UI"
    assert all(offset in actual_offsets for offset in expected_offsets), "centered state did not become centered visible decorations"
    inline = [item for item in geometry["images"] if item["inline"]]
    assert inline and all(item["offset"] < text_width / 3 for item in inline)
    quoted = next(item for item in displays if item["first"] == 11)
    tex = Path(quoted["src"]).read_text()
    assert not re.search(r"(?m)^\s*>\s*", tex), "a Markdown quote marker leaked into generated TeX"
    assert "x>0" in tex, "removing quote markers also removed a mathematical relation"
    assert list(editor.current.buffer) == source



@pytest.mark.xfail(strict=True, reason="native prose-adjacent display math needs a paragraph-fragment layout to center without covering prose")
def test_native_prose_adjacent_display_is_centered_with_its_prose_preserved(native_design_editor):
    editor, source = native_design_editor
    editor.command("redraw!")
    frames = GridFrames()
    frames.consume(editor)
    visible = "\n".join("".join(row) for row in frames.grids[1])
    assert "Before" in visible and "after." in visible
    assert list(editor.current.buffer) == source
    actual = editor.exec_lua('''
      local info=vim.fn.getwininfo(reading_fixture.win)[1]
      for _,p in pairs(reading_fixture.controller.imgs)do
        if p.opts.range[1]==23 then
          return {offset=p._state.loc[2],width=p._state.loc.width,available=info.width-info.textoff}
        end
      end
    ''')
    assert actual, "the source-adjacent display equation disappeared"
    assert abs(actual["offset"] + actual["width"] / 2 - actual["available"] / 2) <= 1

