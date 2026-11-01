"""Rich reader behavior with real typesetting and native image placement.

The terminal transport is captured: these tests check PNGs, source ownership,
navigation and lifecycle, rather than claiming to inspect decoded terminal pixels.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
import warnings
from pathlib import Path

import pynvim
import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORKER = ROOT / "lua/custom/markdown/view/render.py"
pytestmark = pytest.mark.python

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="240" height="80">
<rect x="10" y="10" width="220" height="60" fill="#ff00ff"/>
</svg>"""


def tools():
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data /= os.environ.get("NVIM_APPNAME", "nvim")
    found = {}
    for name in ("pandoc", "typst"):
        path = shutil.which(name) or str(data / "markdown-view/bin" / name)
        if not Path(path).is_file() or not os.access(path, os.X_OK):
            pytest.skip(f"rich reader integration needs {name} on PATH or in the editor data directory")
        found[name] = path
    return found


def request(tmp_path, text, origin, **extra):
    target = tmp_path / "render"
    target.mkdir(exist_ok=True)
    data = {
        "output": str(target),
        "origin": str(origin),
        "text": text,
        "mode": "continuous",
        "columns": 70,
        "cell_width": 10,
        "cell_height": 20,
        **extra,
    }
    path = tmp_path / "request.json"
    path.write_text(json.dumps(data))
    return path


def run_worker(path):
    result = subprocess.run(
        [sys.executable, str(WORKER), str(path)],
        text=True, capture_output=True, timeout=35,
    )
    output = json.loads(result.stdout)
    assert result.returncode == 0, output
    assert output["tiles"] and output["points"]
    for tile in output["tiles"]:
        with Image.open(tile["file"]) as image:
            assert image.width == output["pixel_width"]
            assert image.height > 0
            image.verify()
    return output


@pytest.fixture
def renderer():
    spec = importlib.util.spec_from_file_location("markdown_view_renderer", WORKER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.fast
@pytest.mark.parametrize("failure", ["timeout", "global-error", "killed"])
def test_global_compiler_failure_does_not_discard_healthy_assets(tmp_path, monkeypatch, renderer, failure):
    image = {"t": "Image", "c": [["", [], []], [{"t": "Str", "c": "A healthy figure"}], ["good.svg", ""]]}
    path = tmp_path / "good.svg"
    path.write_text(SVG)
    notices = []
    assets = renderer.Assets(tmp_path / "note.md", notices)
    assets.images[path] = [(image, "A healthy figure")]
    error = (
        TimeoutError("Render command timed out") if failure == "timeout"
        else renderer.CommandError("No space left on device" if failure == "global-error" else "Command killed", 1 if failure == "global-error" else -9)
    )

    def fail(*args, **kwargs):
        raise error

    monkeypatch.setattr(renderer, "run", fail)
    with pytest.raises(type(error), match=str(error)):
        assets.validate("typst", tmp_path)
    assert image["t"] == "Image", "a compiler failure was incorrectly attributed to the figure"
    assert notices == []


@pytest.mark.fast
def test_compiler_timeout_is_a_document_error(tmp_path, renderer):
    with pytest.raises(TimeoutError, match="timed out"):
        renderer.run([sys.executable, "-c", "import time;time.sleep(60)"], cwd=tmp_path, timeout=0.05)


@pytest.mark.integration
@pytest.mark.parametrize("bad_asset", ["missing.svg", "broken.svg", "broken.png"])
def test_asset_failure_preserves_document_and_other_figures(tmp_path, bad_asset):
    (tmp_path / "good.svg").write_text(SVG)
    if bad_asset != "missing.svg":
        (tmp_path / bad_asset).write_text("not an image")
    text = (
        "# Asset isolation\n\nBefore the figures.\n\n"
        "![A working figure](good.svg)\n\n"
        f"![An unavailable figure]({bad_asset})\n\n"
        "The final paragraph must remain readable.\n"
    )
    result = run_worker(request(tmp_path, text, tmp_path / "note.md", **tools()))
    assert bad_asset in "\n".join(result["warnings"])
    assert max(point["source"] for point in result["points"]) >= 9
    # A correctly rendered figure survives the unrelated asset failure.
    assert any(
        any(r > 200 and g < 80 and b > 200 for r, g, b in Image.open(tile["file"]).convert("RGB").get_flattened_data())
        for tile in result["tiles"]
    )


@pytest.mark.integration
def test_vault_image_embed_resolves_and_note_embed_falls_back(tmp_path):
    vault = tmp_path / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / "assets").mkdir()
    (vault / "notes").mkdir()
    (vault / "assets/curve.svg").write_text(SVG)
    (vault / "notes/another.md").write_text("A separate note.\n")
    text = (
        "# Vault note\n\n[[another|Related reading]]\n\n"
        "![[curve.svg]]\n\n![[another]]\n\nFinal paragraph.\n"
    )
    result = run_worker(request(tmp_path, text, vault / "notes/main.md", **tools()))
    assert result["warnings"], "unsupported note transclusion needs a visible diagnostic"
    converted = (tmp_path / "render/content.typ").read_text()
    assert "Related reading" in converted
    assert "curve.svg" in converted
    assert max(point["source"] for point in result["points"]) >= 9


@pytest.mark.integration
def test_empty_note_produces_a_usable_reading_view(tmp_path):
    result = run_worker(request(tmp_path, "", tmp_path / "empty.md", **tools()))
    assert result["rows"] > 0
    assert result["points"][0]["source"] == 1


@pytest.mark.integration
def test_unresolved_vault_and_heading_links_remain_readable(tmp_path):
    text = (
        "# Navigation\n\n[[Docker]]\n\n[[Docker|Containers]]\n\n"
        "[A missing section](#not-in-this-note)\n\nFollowing prose.\n"
    )
    result = run_worker(request(tmp_path, text, tmp_path / "note.md", **tools()))
    converted = (tmp_path / "render/content.typ").read_text()
    assert "Docker" in converted and "Containers" in converted
    assert max(point["source"] for point in result["points"]) >= 9


@pytest.mark.integration
def test_table_only_note_maps_reading_motion_across_source_rows(tmp_path):
    lines = ["| Number | Description |", "| --- | --- |"] + [
        f"| {index} | Corresponding source row {index}. |" for index in range(32)
    ]
    result = run_worker(request(tmp_path, "\n".join(lines) + "\n", tmp_path / "table.md", **tools()))
    first = min(result["points"], key=lambda point: point["source"])
    last = max(result["points"], key=lambda point: point["source"])
    assert first["source"] == 1
    assert last["source"] >= len(lines), "the end of the table has no source anchor"
    assert last["row"] > first["row"] + 10, "all reading rows map to the first source line"


def blocking_pandoc(tmp_path):
    """A process tree with observable startup, for deterministic cancellation."""
    executable = tmp_path / "held-pandoc"
    child_code = (
        "from pathlib import Path\nimport os,signal,time\n"
        f"root=Path({str(tmp_path)!r})\n"
        "def stop(signum,frame):\n"
        " (root/'grandchild.stopped').write_text(str(signum))\n"
        " raise SystemExit(0)\n"
        "signal.signal(signal.SIGTERM,stop)\n"
        "(root/'grandchild.pid').write_text(str(os.getpid()))\n"
        "deadline=time.monotonic()+60\n"
        "while time.monotonic()<deadline and not (root/'release').exists():time.sleep(.02)\n"
    )
    executable.write_text(
        f"#!{sys.executable}\n"
        "from pathlib import Path\nimport os, signal, subprocess, sys, time\n"
        f"root=Path({str(tmp_path)!r})\n"
        "def stop(signum,frame):\n"
        " (root/'child.stopped').write_text(str(signum))\n"
        " raise SystemExit(0)\n"
        "signal.signal(signal.SIGTERM,stop)\n"
        "(root/'child.pid').write_text(str(os.getpid()))\n"
        f"child=subprocess.Popen([sys.executable,'-c',{child_code!r}])\n"
        "child.wait()\n"
    )
    executable.chmod(0o755)
    return executable


def await_file(path, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file():
            return
        time.sleep(0.02)
    raise AssertionError(f"process did not publish {path}")


@pytest.mark.fast
@pytest.mark.skipif(os.name != "posix", reason="worker process-group cleanup is POSIX-specific")
def test_worker_cancellation_stops_descendants(tmp_path):
    executable = blocking_pandoc(tmp_path)
    path = request(tmp_path, "# Pending\n", tmp_path / "note.md", pandoc=str(executable), typst="unused")
    worker = subprocess.Popen(
        [sys.executable, str(WORKER), str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    try:
        await_file(tmp_path / "grandchild.pid")
        worker.terminate()  # Only the worker receives this signal from the test.
        worker.communicate(timeout=5)
        # Both descendants acknowledge SIGTERM and exit; the direct compiler
        # acknowledgement alone would miss an orphaned grandchild.
        await_file(tmp_path / "child.stopped", timeout=3)
        await_file(tmp_path / "grandchild.stopped", timeout=3)
    finally:
        (tmp_path / "release").touch()
        if worker.poll() is None:
            worker.terminate()
            try:
                worker.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                worker.kill()
                worker.communicate()


SOURCE = ["# Rich reading", "", "Opening prose with $x+y=z$.", ""]
for index in range(1, 19):
    SOURCE.extend([f"## Passage {index}", "", f"Passage {index}: native navigation and rich typography remain synchronized.", ""])
SOURCE.extend(["| Quantity | Meaning |", "| --- | --- |", "| $x$ | A value |", "", "Final passage."])


@pytest.fixture
def reader(tmp_path, monkeypatch):
    found = tools()
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data /= os.environ.get("NVIM_APPNAME", "nvim")
    if not (data / "lazy/snacks.nvim").is_dir():
        pytest.skip("native reader placement needs installed Snacks")
    for name in ("STATE", "CACHE", "DATA"):
        monkeypatch.setenv(f"XDG_{name}_HOME", str(tmp_path / name.lower()))
    toolbin = tmp_path / "bin"
    toolbin.mkdir()
    for name, path in found.items():
        (toolbin / name).symlink_to(path)
    monkeypatch.setenv("PATH", str(toolbin) + os.pathsep + os.environ["PATH"])
    origin = tmp_path / "A real source buffer.md"
    origin.write_text("\n".join(SOURCE) + "\n")
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        n.ui_attach(180, 45, rgb=True)
        n.exec_lua("""
          local root,data,python,origin=...
          vim.g.markdown_view_test_plugins=data..'/lazy'
          vim.opt.rtp:prepend(root)
          vim.opt.rtp:append(data..'/lazy/snacks.nvim')
          vim.opt.rtp:append(data..'/site')
          vim.g.mapleader=' ';vim.o.more=false;vim.o.cmdheight=3
          require('custom.python.host').executable=function()return python end
          require('snacks').setup({image={enabled=false,doc={enabled=false}}})
          local terminal=Snacks.image.terminal
          terminal.env=function()return {supported=true,placeholders=true}end
          terminal.size=function()return {cell_width=10,cell_height=20,scale=1}end
          markdown_view_requests={}
          terminal.request=function(r)markdown_view_requests[#markdown_view_requests+1]=r end
          require('custom.markdown.view').setup()
          vim.cmd('filetype on')
          vim.cmd('edit '..vim.fn.fnameescape(origin))
        """, str(ROOT), str(data), sys.executable, str(origin))
        yield n, origin
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()


def wait(n, condition, timeout=20000):
    assert n.exec_lua("return vim.wait(...,function()return " + condition + " end)", timeout), (
        condition, n.exec_lua("return require('custom.markdown.view').status()"),
    )


def ready(n):
    wait(n, "(function()local s=require('custom.markdown.view').session;return s and s.ready and s.manifest and s.manifest.tick==vim.api.nvim_buf_get_changedtick(s.source)end)()")


def status(n):
    return n.exec_lua("""
      local s=require('custom.markdown.view').session
      if not s then return nil end
      return {source=vim.api.nvim_win_get_cursor(s.source_win)[1],preview=vim.api.nvim_win_get_cursor(s.win)[1],
        active=vim.api.nvim_get_current_win(),source_win=s.source_win,win=s.win,buf=s.buf,
        tmp=s.tmp,mode=s.mode,rows=s.manifest and s.manifest.rows}
    """)


def wait_directory_absent(n, path):
    assert n.exec_lua("local path=...;return vim.wait(5000,function()return vim.fn.isdirectory(path)==0 end)", path)


@pytest.mark.integration
def test_tv_navigation_editing_and_generation_cleanup(reader):
    n, origin = reader
    original = origin.read_bytes()
    n.input(" Tv")
    n.command("redraw!")
    ready(n)
    initial = status(n)
    assert initial["active"] == initial["source_win"]
    assert not n.api.buf_get_option(initial["buf"], "modifiable")
    assert n.exec_lua("return vim.api.nvim_buf_get_lines(require('custom.markdown.view').session.buf,0,1,false)[1]:find(vim.fn.nr2char(0x10EEEE),1,true)~=nil")
    assert n.exec_lua("for _,r in ipairs(markdown_view_requests)do if r.f==100 then return true end end;return false")
    n.input("36G")
    n.command("redraw!")
    wait(n, f"vim.api.nvim_win_get_cursor(require('custom.markdown.view').session.win)[1]>{initial['preview']}")
    moved = status(n)
    assert moved["source"] == 36 and moved["preview"] > initial["preview"]
    assert moved["active"] == initial["source_win"]
    n.api.set_current_win(initial["win"])
    n.input("gg")
    n.command("redraw!")
    wait(n, "vim.api.nvim_win_get_cursor(require('custom.markdown.view').session.source_win)[1]<=2")
    n.input("20j")
    n.command("redraw!")
    wait(n, "vim.api.nvim_win_get_cursor(require('custom.markdown.view').session.source_win)[1]>2")
    assert status(n)["active"] == initial["win"]
    n.command("MarkdownView paged")
    ready(n)
    assert status(n)["mode"] == "paged"
    n.command("MarkdownView zoom")
    ready(n)
    assert status(n)["active"] == initial["win"]
    n.command("MarkdownView zoom")
    n.ui_try_resize(142, 40)
    wait(n, "(function()local s=require('custom.markdown.view').session;return s.ready and s.manifest.columns==vim.api.nvim_win_get_width(s.win)-2 end)()")
    n.api.set_current_win(initial["source_win"])
    n.current.window.cursor = (3, 0)
    n.input("iEDITED ")
    wait(n, "vim.fn.mode()=='i' and vim.api.nvim_get_current_line():find('EDITED ',1,true)~=nil")
    n.input("<Esc>")
    ready(n)
    assert n.current.line.startswith("EDITED ")
    n.command("undo")
    n.command("MarkdownView refresh")
    ready(n)
    assert list(n.current.buffer) == SOURCE
    n.input(" Tv")
    n.command("redraw!")
    wait(n, "require('custom.markdown.view').session==nil")
    wait_directory_absent(n, initial["tmp"])
    assert origin.read_bytes() == original
    assert list(n.current.buffer) == SOURCE


@pytest.mark.integration
def test_switching_source_buffer_closes_reader(reader):
    n, origin = reader
    n.command("MarkdownView")
    ready(n)
    opened = status(n)
    n.command("enew!")
    wait(n, "require('custom.markdown.view').session==nil")
    wait_directory_absent(n, opened["tmp"])
    assert n.current.buffer.name != str(origin)


@pytest.mark.integration
def test_late_worker_completion_cannot_replace_newer_presentation(reader):
    n, _ = reader
    n.command("MarkdownView")
    ready(n)
    n.exec_lua("""
      markdown_view_system=vim.system
      markdown_view_hold=true
      markdown_view_held={}
      vim.system=function(command,opts,callback)
        if not tostring(command[2]):match('/markdown/view/render%.py$')then
          return markdown_view_system(command,opts,callback)
        end
        return markdown_view_system(command,opts,function(result)
          if markdown_view_hold then
            markdown_view_held[#markdown_view_held+1]=function()callback(result)end
          else
            callback(result)
          end
        end)
      end
      local view=require('custom.markdown.view')
      vim.api.nvim_buf_set_lines(view.session.source,2,3,false,{'Obsolete worker contents.'})
      view.refresh()
    """)
    try:
        wait(n, "#markdown_view_held==1")
        n.exec_lua("""
          local view=require('custom.markdown.view')
          vim.api.nvim_buf_set_lines(view.session.source,2,3,false,{'Current worker contents.'})
          view.refresh()
          markdown_view_hold=false
        """)
        ready(n)
        current = status(n)
        pixels = n.api.buf_get_lines(current["buf"], 0, -1, False)
        n.exec_lua("for _,callback in ipairs(markdown_view_held)do callback()end;markdown_view_held={}")
        n.command("redraw!")
        ready(n)
        assert n.api.buf_get_lines(current["buf"], 0, -1, False) == pixels
        assert n.current.buffer[2] == "Current worker contents."
    finally:
        n.exec_lua("""
          markdown_view_hold=false
          for _,callback in ipairs(markdown_view_held)do callback()end
          markdown_view_held={}
          vim.system=markdown_view_system
        """)


@pytest.mark.integration
@pytest.mark.skipif(os.name != "posix", reason="worker process-group cleanup is POSIX-specific")
def test_closing_during_render_reaps_jobs_before_removing_files(reader, tmp_path):
    n, origin = reader
    original = origin.read_bytes()
    executable = blocking_pandoc(tmp_path)
    n.exec_lua("""
      local pandoc=...
      local view=require('custom.markdown.view')
      local dependencies=view.dependencies()
      dependencies.pandoc=pandoc
      view.dependencies=function()return dependencies end
      vim.cmd('MarkdownView')
    """, str(executable))
    try:
        await_file(tmp_path / "grandchild.pid")
        opened = status(n)
        n.command("MarkdownView close")
        wait(n, "require('custom.markdown.view').session==nil")
        wait_directory_absent(n, opened["tmp"])
        assert (tmp_path / "child.stopped").is_file()
        assert (tmp_path / "grandchild.stopped").is_file(), "session removed files before stopping compiler descendants"
        assert list(n.current.buffer) == SOURCE
        assert origin.read_bytes() == original
    finally:
        (tmp_path / "release").touch()
