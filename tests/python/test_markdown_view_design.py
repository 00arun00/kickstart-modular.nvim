"""Render the review corpus and check public output/source-map contracts.

These are smoke checks, not typography or terminal-compositor assertions.
Use the corpus for visual review of alignment, hierarchy, and clipping.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest
from PIL import Image

from test_markdown_view import tools

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "tests/fixtures/markdown_view"
WORKER = ROOT / "lua/custom/markdown/view/render.py"
NOTES = sorted(path.stem for path in CORPUS.glob("[0-9][0-9]-*.md"))
pytestmark = [pytest.mark.python, pytest.mark.integration]


@pytest.fixture(scope="session")
def render_design(test_run_dir):
    found = tools()
    cached = {}

    def render(name, mode, columns):
        key = name, mode, columns
        if key in cached:
            return cached[key]
        source = CORPUS / f"{name}.md"
        original = source.read_bytes()
        folder = test_run_dir / "markdown-view-design" / name / f"{mode}-{columns}cols"
        folder.mkdir(parents=True, exist_ok=True)
        request = {
            "output": str(folder), "origin": str(source), "text": original.decode(),
            "mode": mode, "columns": columns, "cell_width": 10, "cell_height": 20,
            **found,
        }
        path = folder / "request.json"
        path.write_text(json.dumps(request))
        process = subprocess.run(
            [sys.executable, str(WORKER), str(path)],
            capture_output=True, text=True, timeout=35,
        )
        result = json.loads(process.stdout)
        assert process.returncode == 0, result
        assert source.read_bytes() == original, "rendering rewrote its Markdown fixture"
        (folder / "result.json").write_text(json.dumps(result, indent=2))
        cached[key] = folder, result, found
        return cached[key]

    return render

def check_render(result, columns):
    assert result["tiles"] and result["points"]
    assert result["pixel_width"] == columns * 10
    assert all(1 <= point["row"] <= result["rows"] for point in result["points"])
    visible = False
    for tile in result["tiles"]:
        with Image.open(tile["file"]) as image:
            assert image.width == result["pixel_width"] and image.height > 0
            visible |= any(low != high for low, high in image.convert("RGB").getextrema())
    assert visible, "a nonempty note produced only blank image tiles"


@pytest.mark.parametrize("name", NOTES)
@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_corpus_renders_without_rewriting_source(render_design, name, mode):
    _, result, _ = render_design(name, mode, 90)
    check_render(result, 90)
    if name == "05-pagination" and mode == "paged":
        assert result["pages"] >= 2, "the long note no longer exercises pagination"


@pytest.mark.parametrize("mode", ["continuous", "paged"])
@pytest.mark.parametrize("columns", [48, 150])
def test_reader_accepts_narrow_and_wide_panes(render_design, mode, columns):
    _, result, _ = render_design("06-narrow-layout", mode, columns)
    check_render(result, columns)
