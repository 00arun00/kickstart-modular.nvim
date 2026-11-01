"""Theme colours and publication lifecycles, measured through real rendering."""

import hashlib
import json
import os
import subprocess
import sys
import warnings
from collections import Counter
from pathlib import Path

import pynvim
import pytest
from PIL import Image

from test_markdown_view import reader as base_reader, tools, wait
from test_markdown_view_design import page_images, query_geometry

ROOT = Path(__file__).resolve().parents[2]
WORKER = ROOT / "lua/custom/markdown/view/render.py"
NOTE = ROOT / "tests/fixtures/markdown_view/07-theme-material.md"
pytestmark = pytest.mark.python

DARK = {
    "background": "#171b24", "foreground": "#e5e9f0", "muted": "#9ca8be",
    "heading": "#7dcfff", "link": "#88c0d0", "math": "#c9a7ff",
    "panel": "#232938", "header": "#2b3448", "border": "#506078",
    "code": "#e5e9f0", "figure_background": "#ffffff",
    "syntax": {"keyword": "#dd88bb", "string": "#66cc99", "function": "#77bbff",
               "type": "#ddbb77", "constant": "#dd9977", "operator": "#66bbcc",
               "punctuation": "#b0b0c0", "tag": "#dd7777", "comment": "#9ca8be"},
}
LIGHT = {
    "background": "#f7f4ed", "foreground": "#282b36", "muted": "#626b7c",
    "heading": "#255b80", "link": "#236879", "math": "#7c4d9b",
    "panel": "#e9e6df", "header": "#dbdfdf", "border": "#8b939e",
    "code": "#282b36", "figure_background": "#ffffff",
    "syntax": {"keyword": "#9d3370", "string": "#287044", "function": "#255c99",
               "type": "#805a14", "constant": "#9c4822", "operator": "#24717d",
               "punctuation": "#555969", "tag": "#9f3434", "comment": "#626b7c"},
}


def rgb(color):
    return tuple(int(color[index:index + 2], 16) for index in (1, 3, 5))


def near_count(counts, color, tolerance=8):
    target = rgb(color)
    return sum(count for pixel, count in counts.items() if max(abs(a - b) for a, b in zip(pixel, target)) <= tolerance)


@pytest.fixture(scope="session")
def themed_render(test_run_dir):
    cached = {}
    found = tools()

    def render(name, mode):
        key = name, mode
        if key in cached:
            return cached[key]
        palette = DARK if name == "dark" else LIGHT
        folder = test_run_dir / "markdown-view-theme" / f"{name}-{mode}"
        folder.mkdir(parents=True, exist_ok=True)
        original = NOTE.read_bytes()
        request = {"output": str(folder), "origin": str(NOTE), "text": original.decode(),
                   "mode": mode, "columns": 90, "cell_width": 10, "cell_height": 20,
                   "palette": palette, **found}
        path = folder / "request.json"
        path.write_text(json.dumps(request))
        process = subprocess.run([sys.executable, str(WORKER), str(path)], text=True, capture_output=True, timeout=35)
        result = json.loads(process.stdout)
        assert process.returncode == 0, result
        assert NOTE.read_bytes() == original
        (folder / "result.json").write_text(json.dumps(result, indent=2))
        cached[key] = folder, result, found
        return cached[key]

    return render


@pytest.mark.integration
@pytest.mark.parametrize("mode", ["continuous", "paged"])
@pytest.mark.parametrize("name,palette", [("dark", DARK), ("light", LIGHT)])
def test_actual_page_code_and_math_pixels_use_selected_roles(themed_render, name, palette, mode):
    folder, result, found = themed_render(name, mode)
    counts = Counter()
    for tile in result["tiles"]:
        with Image.open(tile["file"]) as source:
            image = source.convert("RGB")
            assert image.getpixel((0, 0)) == rgb(palette["background"])
            assert image.getpixel((0, image.height - 1)) == rgb(palette["background"]), "terminal-row padding leaked a white stripe"
            counts.update(image.get_flattened_data())
    for role in ("foreground", "heading", "link", "math", "panel", "header"):
        assert near_count(counts, palette[role]) > 0, f"the actual raster did not use the selected {role} colour"
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14
    margin = 36 if mode == "paged" else 24
    body = result["pixel_width"] / scale - 2 * margin
    blocks = query_geometry(folder, found, "raw.where(block:true)",
                            "page:p.page,x:p.x.pt(),y:p.y.pt(),height:m.height.pt()", measure_width=body)
    assert len(blocks) == 1
    code_counts = Counter()
    for block in blocks:
        image = page_images(result)[block["page"]]
        crop = image.crop((int((block["x"] - 12) * scale), max(0, int((block["y"] - 12) * scale)),
                           int(result["pixel_width"] - margin * scale),
                           min(image.height, int((block["y"] + block["height"] + 12) * scale))))
        code_counts.update(crop.get_flattened_data())
    for role in ("keyword", "string", "function", "comment"):
        # Small glyphs are antialiased (observed channel differences 1–5), so
        # inspect near-colour ink in the actual code region, not exact RGB or
        # a matching hue elsewhere in the document.
        assert near_count(code_counts, palette["syntax"][role]) > 0, f"code {role} colour exists in the palette but not rendered glyphs"


@pytest.mark.integration
@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_theme_changes_preserve_layout_and_authored_figure_pixels(themed_render, mode):
    dark_folder, dark, found = themed_render("dark", mode)
    light_folder, light, _ = themed_render("light", mode)
    assert (dark["rows"], dark["pages"], dark["points"]) == (light["rows"], light["pages"], light["points"]), "colour-only rendering changed document geometry"
    scale = dark["pixel_width"] / 595 if mode == "paged" else 20 / 14
    margin = 36 if mode == "paged" else 24
    body = dark["pixel_width"] / scale - 2 * margin
    expression = "page:p.page,x:p.x.pt(),y:p.y.pt(),width:m.width.pt(),height:m.height.pt()"
    dark_images = query_geometry(dark_folder, found, "image", expression, measure_width=body)
    light_images = query_geometry(light_folder, found, "image", expression, measure_width=body)
    assert dark_images == light_images and len(dark_images) == 1
    pages = page_images(dark), page_images(light)
    position = dark_images[0]
    bounds = (int(position["x"] * scale) + 2, int(position["y"] * scale) + 2,
              int((position["x"] + position["width"]) * scale) - 2,
              int((position["y"] + position["height"]) * scale) - 2)
    crops = [group[position["page"]].crop(bounds) for group in pages]
    assert crops[0].tobytes() == crops[1].tobytes(), "theme following recoloured or inverted an authored figure"
    pixels = Counter(crops[0].get_flattened_data())
    assert pixels[(255, 255, 255)] > crops[0].width * crops[0].height / 2, "transparent dark labels lost their light paper backing"
    assert pixels[(211, 77, 82)] > 10, "the authored red curve colour was lost"
    assert near_count(pixels, "#1f2937") > 10, "dark authored labels were recoloured"


@pytest.mark.fast
def test_live_unknown_highlights_outrank_cached_named_palette(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    monkeypatch.setenv("MARKDOWN_THEME_TEST_ROOT", str(ROOT))
    source = tmp_path / "theme.lua"
    source.write_text('''
vim.opt.rtp:prepend(vim.env.MARKDOWN_THEME_TEST_ROOT)
vim.g.colors_name='an-unknown-theme'
package.loaded['custom.theme']={palette=function()error('stale named palette was consulted')end}
vim.api.nvim_set_hl(0,'Normal',{fg=0x182838,bg=0xf1f2f3})
vim.api.nvim_set_hl(0,'Title',{fg=0x124578})
vim.api.nvim_set_hl(0,'Comment',{fg=0x657687})
vim.api.nvim_set_hl(0,'WinSeparator',{fg=0x8798a9})
vim.api.nvim_set_hl(0,'SnacksImageMath',{fg=0x765432})
vim.api.nvim_set_hl(0,'Keyword',{fg=0x934578})
local theme=require('custom.markdown.view.theme')
local first=theme.capture()
assert(first.background=='#f1f2f3'and first.foreground=='#182838')
assert(first.heading=='#124578'and first.muted=='#657687'and first.border=='#8798a9')
assert(first.math=='#765432'and first.syntax.keyword=='#934578')
local hash=theme.fingerprint(first)
vim.api.nvim_set_hl(0,'Normal',{fg=0xeeeeee,bg=0x102030})
local second=theme.capture()
assert(first.background=='#f1f2f3'and second.background=='#102030','snapshots share mutable colour state')
assert(theme.fingerprint(second)~=hash)
vim.api.nvim_set_hl(0,'Normal',{fg=0x102030,bg=0xf1f2f3,reverse=true})
local reversed=theme.capture()
assert(reversed.background=='#102030'and reversed.foreground=='#f1f2f3','reverse highlights lost their visible role')
vim.cmd 'qa!'
''')
    process = subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(source), str(ROOT)], capture_output=True, text=True, timeout=10)
    assert process.returncode == 0, process.stdout + process.stderr


@pytest.mark.fast
def test_surface_pairs_remain_readable_when_float_colors_use_the_opposite_polarity(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    monkeypatch.setenv("MARKDOWN_THEME_TEST_ROOT", str(ROOT))
    source = tmp_path / "surface.lua"
    source.write_text('''
vim.opt.rtp:prepend(vim.env.MARKDOWN_THEME_TEST_ROOT)
vim.o.background='dark'
vim.api.nvim_set_hl(0,'Normal',{fg=0xeeeeee,bg=0x181818})
vim.api.nvim_set_hl(0,'NormalFloat',{fg=0x181818,bg=0xf0f0f0})
vim.api.nvim_set_hl(0,'Title',{fg=0xffffff})
vim.api.nvim_set_hl(0,'CursorLine',{bg=0xf0f0f0})
io.stdout:write(vim.json.encode(require('custom.markdown.view.theme').capture()))
vim.cmd 'qa!'
''')
    process = subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(source)], capture_output=True, text=True, timeout=10)
    assert process.returncode == 0, process.stdout + process.stderr
    palette = json.loads(process.stdout)

    def luminance(color):
        channels = [value / 255 for value in rgb(color)]
        linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
        return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))

    def contrast(a, b):
        light, dark = sorted((luminance(a), luminance(b)), reverse=True)
        return (light + 0.05) / (dark + 0.05)

    assert palette["foreground"] == "#eeeeee" and palette["heading"] == "#ffffff", "pairing guard changed selected text hues"
    assert contrast(palette["foreground"], palette["panel"]) >= 4.5
    assert contrast(palette["heading"], palette["header"]) >= 4.5


@pytest.fixture
def theme_reader(base_reader):
    editor, origin = base_reader
    editor.exec_lua('''
      function qa_apply_theme(p,name)
        vim.o.background=name=='qa-light'and'light'or'dark'
        vim.g.colors_name=name
        local groups={Normal={fg=p.foreground,bg=p.background},NormalFloat={fg=p.foreground,bg=p.panel},
          Title={fg=p.heading},Comment={fg=p.muted},WinSeparator={fg=p.border},CursorLine={bg=p.header},
          SnacksImageMath={fg=p.math},Underlined={fg=p.link},['@markup.link']={fg=p.link},
          Keyword={fg=p.syntax.keyword},String={fg=p.syntax.string},Function={fg=p.syntax['function']},
          Type={fg=p.syntax.type},Constant={fg=p.syntax.constant},Operator={fg=p.syntax.operator},
          Delimiter={fg=p.syntax.punctuation},Tag={fg=p.syntax.tag}}
        for group,value in pairs(groups)do vim.api.nvim_set_hl(0,group,value)end
        vim.api.nvim_exec_autocmds('ColorScheme',{pattern=name})
      end
    ''')
    editor.exec_lua("qa_apply_theme(...)", DARK, "qa-dark")
    yield editor, origin


def ready_theme(editor, background):
    wait(editor, "(function()local s=require('custom.markdown.view').session;return s and s.ready and not s.theme_pending and s.frame_palette and s.frame_palette.background=="
         + json.dumps(background) + " and s.palette_hash==s.frame_palette_hash end)()")


def views(editor):
    return editor.exec_lua('''
      local s=require('custom.markdown.view').session
      local function view(win)return vim.api.nvim_win_call(win,vim.fn.winsaveview)end
      return {active=vim.api.nvim_get_current_win(),source=view(s.source_win),preview=view(s.win)}
    ''')


def background(editor):
    return editor.exec_lua("return vim.api.nvim_get_hl(0,{name='MarkdownViewNormal',link=false}).bg")


def hold_workers(editor):
    editor.exec_lua('''
      qa_original_system=vim.system;qa_hold_workers=true;qa_worker_results={}
      vim.system=function(command,opts,callback)
        if not tostring(command[2]):match('/markdown/view/render%.py$')then return qa_original_system(command,opts,callback)end
        return qa_original_system(command,opts,function(result)
          if qa_hold_workers then qa_worker_results[#qa_worker_results+1]=function()callback(result)end else callback(result)end
        end)
      end
    ''')


def release_workers(editor):
    editor.exec_lua('''
      qa_hold_workers=false
      for _,callback in ipairs(qa_worker_results)do callback()end
      qa_worker_results={};vim.system=qa_original_system
    ''')


@pytest.mark.integration
@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_color_publication_is_atomic_and_preserves_latest_view(theme_reader, mode):
    editor, origin = theme_reader
    original = origin.read_bytes()
    editor.command("MarkdownView " + mode)
    ready_theme(editor, DARK["background"])
    editor.exec_lua("vim.api.nvim_set_current_win(require('custom.markdown.view').session.win)")
    editor.input("24G3l<C-e>")
    editor.command("redraw!")
    hold_workers(editor)
    try:
        editor.exec_lua("qa_apply_theme(...)", LIGHT, "qa-light")
        wait(editor, "#qa_worker_results==1")
        assert background(editor) == int(DARK["background"][1:], 16), "new background appeared behind old pixels"
        editor.input("6j2l<C-e>")
        editor.command("redraw!")
        latest = views(editor)
        release_workers(editor)
        ready_theme(editor, LIGHT["background"])
        assert views(editor) == latest, "colour-only publication reset the latest cursor, viewport, or focus"
        assert background(editor) == int(LIGHT["background"][1:], 16)
        assert origin.read_bytes() == original
    finally:
        editor.exec_lua("if qa_original_system then vim.system=qa_original_system end")


@pytest.mark.integration
def test_theme_epoch_rejects_completion_before_deferred_palette_capture(theme_reader):
    editor, _ = theme_reader
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    initial = editor.exec_lua("local s=require('custom.markdown.view').session;return{epoch=s.theme_epoch,frame=s.frame_task.version}")
    hold_workers(editor)
    editor.command("MarkdownView refresh")
    wait(editor, "#qa_worker_results==1")
    try:
        state = editor.exec_lua('''
          qa_original_schedule=vim.schedule;qa_palette_callbacks={}
          vim.schedule=function(callback)qa_palette_callbacks[#qa_palette_callbacks+1]=callback end
          qa_apply_theme(...)
          vim.schedule=qa_original_schedule
          local s=require('custom.markdown.view').session
          return{epoch=s.theme_epoch,pending=s.theme_pending}
        ''', LIGHT, "qa-light")
        assert state["epoch"] > initial["epoch"] and state["pending"]
        release_workers(editor)
        editor.command("redraw!")
        assert editor.exec_lua("return require('custom.markdown.view').session.frame_task.version") == initial["frame"], "an obsolete result published in the epoch/capture gap"
        assert background(editor) == int(DARK["background"][1:], 16)
        editor.exec_lua("for _,callback in ipairs(qa_palette_callbacks)do qa_original_schedule(callback)end;qa_palette_callbacks={}")
        ready_theme(editor, LIGHT["background"])
    finally:
        editor.exec_lua("if qa_original_schedule then vim.schedule=qa_original_schedule end;if qa_original_system then vim.system=qa_original_system end")


@pytest.mark.integration
def test_palette_capture_waits_for_later_colorscheme_handlers(theme_reader):
    editor, _ = theme_reader
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    editor.exec_lua('''
      vim.api.nvim_create_autocmd('ColorScheme',{once=true,callback=function()
        vim.api.nvim_set_hl(0,'Normal',{fg=0x182838,bg=0xddeeff})
      end})
      qa_apply_theme(...)
    ''', LIGHT, "qa-light")
    ready_theme(editor, "#ddeeff")


@pytest.mark.integration
def test_failed_theme_render_retains_frame_and_waits_for_explicit_retry(theme_reader):
    editor, _ = theme_reader
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    original_frame = editor.exec_lua("return require('custom.markdown.view').session.frame_task.version")
    editor.exec_lua('''
      qa_original_system=vim.system
      vim.system=function(command,opts,callback)
        if not tostring(command[2]):match('/markdown/view/render%.py$')then return qa_original_system(command,opts,callback)end
        return qa_original_system(command,opts,function()callback({code=1,stdout='{"error":"controlled theme failure"}',stderr=''})end)
      end
      qa_apply_theme(...)
    ''', LIGHT, "qa-light")
    try:
        wait(editor, "require('custom.markdown.view').session.phase=='failed'")
        assert editor.exec_lua("return require('custom.markdown.view').session.frame_task.version") == original_frame
        assert background(editor) == int(DARK["background"][1:], 16)
        version = editor.exec_lua("return require('custom.markdown.view').session.version")
        editor.exec_lua('''
          local defer=vim.defer_fn;local callbacks={}
          vim.defer_fn=function(callback,delay)if delay==150 then callbacks[#callbacks+1]=callback else return defer(callback,delay)end end
          local s=require('custom.markdown.view').session
          vim.api.nvim_set_current_win(s.win);vim.api.nvim_set_current_win(s.source_win)
          vim.defer_fn=defer
          for _,callback in ipairs(callbacks)do callback()end
        ''')
        assert editor.exec_lua("return require('custom.markdown.view').session.version") == version
    finally:
        editor.exec_lua("vim.system=qa_original_system")
    editor.command("MarkdownView refresh")
    ready_theme(editor, LIGHT["background"])


@pytest.mark.integration
def test_hidden_preview_uses_latest_theme_after_restore(theme_reader):
    editor, origin = theme_reader
    original = origin.read_bytes()
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    before = views(editor)
    editor.command("MarkdownView zoom")
    editor.exec_lua("qa_apply_theme(...)", LIGHT, "qa-light")
    wait(editor, "not require('custom.markdown.view').session.theme_pending")
    assert views(editor)["active"] == before["active"]
    editor.command("MarkdownView zoom")
    ready_theme(editor, LIGHT["background"])
    assert views(editor)["active"] == before["active"]
    assert origin.read_bytes() == original


@pytest.mark.integration
def test_explicit_refresh_captures_manual_highlight_changes_without_colorscheme_event(theme_reader):
    editor, origin = theme_reader
    original = origin.read_bytes()
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    editor.exec_lua("vim.api.nvim_set_current_win(require('custom.markdown.view').session.win)")
    editor.input("25G2l<C-e>")
    editor.command("redraw!")
    previous = views(editor)
    old_hash = editor.exec_lua("return require('custom.markdown.view').session.frame_palette_hash")
    editor.exec_lua('''
      vim.api.nvim_set_hl(0,'Normal',{fg=0x182838,bg=0xe1e7ef})
      vim.api.nvim_set_hl(0,'Title',{fg=0x754321})
    ''')
    editor.command("MarkdownView refresh")
    ready_theme(editor, "#e1e7ef")
    assert editor.exec_lua("return require('custom.markdown.view').session.frame_palette.heading") == "#754321"
    assert editor.exec_lua("return require('custom.markdown.view').session.frame_palette_hash") != old_hash
    assert views(editor) == previous
    assert origin.read_bytes() == original


@pytest.mark.integration
def test_source_edit_during_theme_conversion_rejects_the_old_source_map(theme_reader):
    editor, origin = theme_reader
    original = origin.read_bytes()
    editor.command("MarkdownView")
    ready_theme(editor, DARK["background"])
    hold_workers(editor)
    try:
        editor.exec_lua("qa_apply_theme(...)", LIGHT, "qa-light")
        wait(editor, "#qa_worker_results==1")
        editor.exec_lua('''
          local s=require('custom.markdown.view').session
          vim.api.nvim_buf_set_lines(s.source,2,3,false,{'THEMEEDITCURRENT survives obsolete conversion.'})
        ''')
        release_workers(editor)
        ready_theme(editor, LIGHT["background"])
        assert editor.exec_lua('''
          local s=require('custom.markdown.view').session
          return s.manifest.tick==vim.api.nvim_buf_get_changedtick(s.source)
        '''), "the themed frame used a pre-edit source map"
        assert editor.exec_lua('''
          local s=require('custom.markdown.view').session
          return table.concat(vim.fn.readfile(s.frame_task.folder..'/content.typ'),'\\n'):find('THEMEEDITCURRENT',1,true)~=nil
        '''), "the themed frame used the pre-edit document"
        assert origin.read_bytes() == original
    finally:
        editor.exec_lua("if qa_original_system then vim.system=qa_original_system end")


@pytest.mark.integration
def test_real_theme_picker_preview_and_cancel_keep_source_view_and_exports_isolated(tmp_path, monkeypatch, test_run_dir):
    tools()
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / os.environ.get("NVIM_APPNAME", "nvim")
    real_state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / os.environ.get("NVIM_APPNAME", "nvim")
    watched = [real_state / name for name in ("theme-choice", "terminal-theme/ghostty.conf", "terminal-theme/tmux.conf",
               "terminal-theme/fzf.conf", "terminal-theme/enabled", "terminal-theme/installation.json")]

    def state_hashes():
        return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None for path in watched}

    real_state_before = state_hashes()
    if not all((data / "lazy" / name).is_dir() for name in ("telescope.nvim", "catppuccin")):
        pytest.skip("actual ThemePicker integration requires installed Telescope and Catppuccin")
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    source = tmp_path / "Theme picker source.md"
    original = "# Theme picker source\n\n" + "\n\n".join(
        f"## Passage {index}\n\nReading a stable passage while the selected theme changes should preserve location and focus."
        for index in range(20)
    ) + "\n"
    source.write_text(original)
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        editor = pynvim.attach("child", argv=[
            "nvim", "--embed", "--cmd", "lua vim.opt.rtp:prepend(" + json.dumps(str(ROOT)) + ");vim.lsp.start=function()return nil end",
            "-u", str(ROOT / "init.lua"), "-n", "-i", "NONE",
        ])
    try:
        editor.ui_attach(180, 45, rgb=True)
        editor.exec_lua('''
          local source=...
          pcall(function()require('noice').disable()end)
          local terminal=Snacks.image.terminal
          terminal.env=function()return{supported=true,placeholders=true}end
          terminal.size=function()return{cell_width=10,cell_height=20,scale=1}end
          terminal.request=function()end
          vim.o.background='dark';vim.cmd.colorscheme('catppuccin-mocha')
          vim.cmd('edit '..vim.fn.fnameescape(source))
          vim.cmd 'MarkdownView'
        ''', str(source))
        wait(editor, "(function()local s=require('custom.markdown.view').session;return s and s.ready end)()")
        editor.exec_lua("vim.api.nvim_set_current_win(require('custom.markdown.view').session.win)")
        editor.input("28G3l<C-e>")
        editor.command("redraw!")
        previous = views(editor)
        old_background = editor.exec_lua("return require('custom.markdown.view').session.frame_palette.background")
        editor.exec_lua('''
          qa_picker_commands={};qa_picker_system=vim.system
          vim.system=function(command,...)
            qa_picker_commands[#qa_picker_commands+1]=command[1]
            return qa_picker_system(command,...)
          end
        ''')
        editor.command("ThemePicker")
        wait(editor, "vim.bo.filetype=='TelescopePrompt'")
        picker_win = editor.current.window.handle
        prompt = editor.current.buffer.number
        editor.exec_lua('''
          local picker=require('telescope.actions.state').get_current_picker(...)
          picker:set_selection(0)
        ''', prompt)
        wait(editor, "vim.g.colors_name=='catppuccin-latte'")
        selected = editor.exec_lua('''
          local s=require('custom.markdown.view').session
          return vim.api.nvim_win_call(s.source_win,function()
            return string.format('#%06x',vim.api.nvim_get_hl(0,{name='Normal',link=false}).bg)
          end)
        ''')
        assert selected != old_background
        ready_theme(editor, selected)
        assert editor.current.window.handle == picker_win, "a themed frame stole focus from ThemePicker"
        assert views(editor)["preview"] == previous["preview"]
        selected_view = views(editor)
        editor.exec_lua("require('telescope.actions').close(...)", prompt)
        wait(editor, "vim.g.colors_name=='catppuccin-mocha'")
        ready_theme(editor, old_background)
        assert views(editor) == previous, "cancelling the real theme picker lost the reading position"
        state = Path(editor.funcs.stdpath("state"))
        assert state.is_relative_to(tmp_path / "state")
        assert not (state / "theme-choice").exists(), "a cancelled preview persisted a theme selection"
        assert not (state / "terminal-theme/enabled").exists()
        assert not (state / "terminal-theme/installation.json").exists()
        assert source.read_text() == original
        assert editor.exec_lua("return vim.api.nvim_buf_get_lines(require('custom.markdown.view').session.source,0,-1,false)") == original.splitlines()
        commands = editor.exec_lua("return qa_picker_commands")
        assert not any(Path(command).name.lower() in {"pkill", "tmux", "ghostty"} for command in commands), "theme preview invoked an external terminal update"
        assert state_hashes() == real_state_before, "isolated theme preview changed the user's real theme state"
        artifact = test_run_dir / "markdown-view-theme" / "real-theme-picker"
        artifact.mkdir(parents=True, exist_ok=True)
        (artifact / "preview-cancel.json").write_text(json.dumps({
            "initial_background": old_background, "preview_background": selected,
            "restored_background": editor.exec_lua("return require('custom.markdown.view').session.frame_palette.background"),
            "initial_views": previous, "picker_views": selected_view, "restored_views": views(editor),
            "source_sha256_before": source_hash, "source_sha256_after": hashlib.sha256(source.read_bytes()).hexdigest(),
            "isolated_state": str(state), "real_state_before": real_state_before, "real_state_after": state_hashes(),
            "spawned_commands": commands, "cancelled_choice_persisted": False,
        }, indent=2))
    finally:
        try:
            editor.command("qa!")
        except EOFError:
            pass
        editor.close()
