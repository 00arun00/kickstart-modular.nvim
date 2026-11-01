"""Native reading layout: visible geometry, source ownership, and image continuity.

These tests use actual Neovim redraw grids and controlled image transport.
They run independently of the optional rich Markdown view and its toolchain.
"""

import json
import os
import re
import warnings
from pathlib import Path

import pynvim
import pytest

from test_markdown_document import GridFrames

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.python, pytest.mark.integration]


class ImageGridFrames(GridFrames):
    """Retain image-ID highlights alongside the existing native grid decoder."""

    def __init__(self):
        super().__init__()
        self.highlights = {}
        self.attrs = {}

    def consume(self, editor):
        messages = list(editor._session._pending_messages)
        super().consume(editor)
        for message in messages:
            if message.type != "notification" or message.name != "redraw":
                continue
            for event in message.args:
                for args in event[1:]:
                    if event[0] == "hl_attr_define":
                        self.attrs[args[0]] = args[1]
                    elif event[0] == "grid_resize":
                        grid, width, height = args
                        self.highlights[grid] = [[0] * width for _ in range(height)]
                    elif event[0] == "grid_clear":
                        grid = args[0]
                        self.highlights[grid] = [[0] * len(row) for row in self.highlights[grid]]
                    elif event[0] == "grid_line":
                        grid, row, column, cells = args[:4]
                        highlight = 0
                        for cell in cells:
                            if len(cell) > 1:
                                highlight = cell[1]
                            for _ in range(cell[2] if len(cell) > 2 else 1):
                                self.highlights[grid][row][column] = highlight
                                column += 1
                    elif event[0] == "grid_scroll":
                        grid, top, bottom, left, right, rows, columns = args
                        previous = [line[:] for line in self.highlights[grid]]
                        for row in range(top, bottom):
                            for column in range(left, right):
                                source_row, source_column = row + rows, column + columns
                                self.highlights[grid][row][column] = (
                                    previous[source_row][source_column]
                                    if top <= source_row < bottom and left <= source_column < right else 0
                                )

    def image_origins(self, positions):
        origins = {}
        for row, line in enumerate(self.grids[1]):
            for column, text in enumerate(line):
                if "\U0010eeee" not in text:
                    continue
                attr = self.attrs.get(self.highlights[1][row][column], {})
                key = attr.get("foreground"), attr.get("special")
                assert all(value is not None for value in key), "an image placeholder lost its encoded identity"
                marks = [positions[char] for char in text[1:] if char in positions]
                assert len(marks) >= 2, "an image placeholder lost its row/column ordinals"
                origins.setdefault(str(key), set()).add((row - marks[0], column - marks[1]))
        return origins



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



@pytest.mark.parametrize("columns", [100, 72])
def test_native_math_cells_keep_tall_images_and_compact_plain_rows(native_design_editor, columns, test_run_dir):
    editor, _ = native_design_editor
    source = [
        "# Native table line boxes", "", "| Kind | Equation | Meaning |", "| --- | --- | --- |",
        "| Plain | No equation | Compact prose |",
        r"| Matrix | Before $\begin{pmatrix}1&2\\3&4\end{pmatrix}$ after | A tall inline object |",
        "| Display | $$a=b$$ | A display object |", "", "The final source paragraph.",
    ]
    editor.exec_lua('''
      local source=...
      -- The shared controlled transport models ordinary inline math as a
      -- 22-pixel baseline canvas. Supply a genuinely tall matrix input here;
      -- its geometry must not change merely because it uses inline text style.
      local function tall_matrix(src,info)
        if table.concat(vim.fn.readfile(src),'\\n'):find('pmatrix',1,true)then
          info.size={width=140,height=80}
        end
      end
      local convert=Snacks.image.convert.convert
      Snacks.image.convert.convert=function(opts)
        local result=convert(opts)
        tall_matrix(opts.src,result.meta.info)
        return result
      end
      local image=Snacks.image.image.new
      Snacks.image.image.new=function(src)
        local result=image(src)
        tall_matrix(src,result.info)
        return result
      end
      native_cell_requests={}
      Snacks.image.terminal.request=function(request)native_cell_requests[#native_cell_requests+1]=request end
      vim.api.nvim_buf_set_lines(reading_fixture.buf,0,-1,false,source)
      vim.bo[reading_fixture.buf].modified=false
      reading_fixture.controller:update(true)
    ''', source)
    if columns != 100:
        editor.ui_try_resize(columns, 60)
    assert editor.exec_lua("return vim.wait(5000,function()return require('custom.markdown.document').status(reading_fixture.buf).ready end)")
    editor.command("redraw!")
    layout = editor.exec_lua('''
      local api=vim.api
      local rows={}
      local function text(chunks)
        local pieces={}
        for _,chunk in ipairs(chunks or {})do pieces[#pieces+1]=chunk[1]end
        return table.concat(pieces)
      end
      for _,mark in ipairs(api.nvim_buf_get_extmarks(reading_fixture.buf,require('custom.markdown.tables').ns,0,-1,{details=true}))do
        local row,d=mark[2]+1,mark[4]
        rows[row]=rows[row]or{}
        if d.priority==101 then
          rows[row].above={}
          for _,line in ipairs(d.virt_lines or {})do rows[row].above[#rows[row].above+1]=text(line)end
          rows[row].anchor=text(d.virt_text)
        else
          rows[row].below={}
          for _,line in ipairs(d.virt_lines or {})do rows[row].below[#rows[row].below+1]=text(line)end
        end
      end
      local heights={}
      for _,request in ipairs(native_cell_requests)do
        if request.a=='p'and request.r then heights[#heights+1]=request.r end
      end
      return {rows=rows,heights=heights}
    ''')
    rows = layout["rows"]

    def body_lines(row):
        value = rows[row - 1] if isinstance(rows, list) else rows.get(row, rows.get(str(row)))
        assert value and "anchor" in value, f"source row {row} has no retained table presentation"
        return [line for line in value.get("above", []) + [value["anchor"]] + value.get("below", []) if line.startswith("│")]

    assert len(body_lines(5)) == 1, "a prose-only row acquired unconditional empty padding rows"
    matrix = body_lines(6)
    assert len(matrix) > 1, "a tall inline matrix was squeezed into a single native row"
    assert any("Before" in line for line in matrix) and any("after" in line for line in matrix), "prose was lost around tall math"
    if columns == 100:
        assert any("Before" in line and "after" in line for line in matrix), "prose lost its shared line box despite enough width"
    assert any(height > 1 for height in layout["heights"]), "no multi-row image placement reached the native transport"
    for row in (5, 6, 7):
        assert all(line.count("│") == 4 for line in body_lines(row)), "an image displaced a native table border"
    frames = ImageGridFrames()
    placement_source = Path(editor.exec_lua("return debug.getinfo(Snacks.image.placement.render_grid,'S').source:sub(2)"))
    diacritics = re.search(r'local diacritics = vim.split\(\s*"([^\"]+)"', placement_source.read_text())[1]
    positions = {chr(int(value, 16)): index for index, value in enumerate(diacritics.split(','))}

    def check_native_frame():
        editor.command("redraw!")
        frames.consume(editor)
        visible = "\n".join("".join(line) for line in frames.grids[1])
        for label in ("Plain", "Matrix", "Display"):
            assert label in visible, f"source-anchor layout hid the {label} row label"
        origins = frames.image_origins(positions)
        assert origins, "no image placeholders reached the actual native grid"
        assert all(len(values) == 1 for values in origins.values()), (
            "one image placement has several visual origins: physical source wrapping split its image rows"
        )
        folder = test_run_dir / "markdown-view-design" / f"native-cells-{columns}cols"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "grid-origins.json").write_text(json.dumps({key: sorted(value) for key, value in origins.items()}, indent=2))

    check_native_frame()
    editor.input("<C-e>")
    editor.command("redraw!")
    check_native_frame()
    editor.input("<C-y>")
    editor.command("redraw!")
    check_native_frame()
    editor.current.window.cursor = (5, 0)
    editor.input("2j")
    editor.command("redraw!")
    assert editor.current.window.cursor[0] == 7, "native source-line motions changed with rendered row height"
    editor.current.window.cursor = (6, 0)
    editor.input("iEDITED ")
    assert editor.exec_lua("return vim.wait(5000,function()return vim.fn.mode()=='i'and vim.api.nvim_get_current_line():find('EDITED ',1,true)~=nil end)")
    assert not editor.exec_lua("return reading_fixture.table_rendered()"), "editing did not reveal table source"
    editor.input("<Esc>")
    editor.command("undo")
    assert editor.exec_lua("return vim.wait(5000,function()return require('custom.markdown.document').status(reading_fixture.buf).ready end)")
    check_native_frame()
    assert list(editor.current.buffer) == source
    assert not editor.current.buffer.options["modified"]
