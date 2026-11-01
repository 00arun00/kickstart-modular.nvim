"""Observable layout contracts for the directly openable reading-design corpus.

These checks inspect rendered PNG ink and actual typeset positions. A successful
compiler exit or a centered outer equation block does not prove centered glyphs.
"""

import json
import re
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


def page_images(result):
    """Reassemble actual PNG tiles without inventing a second renderer."""
    pages = {}
    for tile in result["tiles"]:
        match = re.search(r"tile-(\d+)-(\d+)\.png$", tile["file"])
        assert match
        page, offset = map(int, match.groups())
        with Image.open(tile["file"]) as image:
            pages.setdefault(page, []).append((offset * 20, image.convert("RGB")))
    output = {}
    for page, tiles in pages.items():
        height = max(offset + image.height for offset, image in tiles)
        image = Image.new("RGB", (result["pixel_width"], height), "white")
        for offset, tile in tiles:
            image.paste(tile, (0, offset))
        output[page] = image
    return output


def query_geometry(folder, found, selector, expression, measure_width=None):
    instrumented = folder / "design-geometry.typ"
    measurement = "measure(it)" if measure_width is None else f"measure(it, width:{measure_width}pt)"
    instrumented.write_text((folder / "document.typ").read_text() + f'''
#context {{
  let values = query({selector}).map(it => {{
    let p = it.location().position()
    let m = {measurement}
    ({expression})
  }})
  [#metadata(values)<design-geometry>]
}}
''')
    query = subprocess.run(
        [found["typst"], "eval", "query(<design-geometry>).map(it => it.value)",
         "--root", "/", "--in", str(instrumented)],
        cwd=folder, capture_output=True, text=True, timeout=20,
    )
    assert query.returncode == 0, query.stderr
    values = json.loads(query.stdout)[0]
    (folder / "design-geometry.json").write_text(json.dumps(values, indent=2))
    return values


@pytest.mark.parametrize("name", NOTES)
@pytest.mark.parametrize("mode", ["continuous", "paged"])
@pytest.mark.parametrize("columns", [48, 90, 150])
def test_corpus_renders_at_reading_widths(render_design, name, mode, columns):
    _, result, _ = render_design(name, mode, columns)
    assert result["tiles"] and result["points"]
    assert result["pixel_width"] == columns * 10
    if name == "05-pagination" and mode == "paged":
        assert result["pages"] >= 2, "the pagination fixture no longer exercises a page boundary"
    assert all(1 <= point["row"] <= result["rows"] for point in result["points"])
    for page in page_images(result).values():
        # A blank padded canvas would satisfy dimensions but not a reading view.
        assert min(page.convert("L").getextrema()) < 120


@pytest.mark.parametrize("mode", ["continuous", "paged"])
@pytest.mark.parametrize("columns", [48, 90, 150])
def test_display_math_glyphs_center_in_their_content_containers(render_design, mode, columns):
    folder, result, found = render_design("01-equation-layout", mode, columns)
    geometry = query_geometry(
        folder, found, "math.equation",
        "block:it.block,page:p.page,x:p.x.pt(),y:p.y.pt(),width:m.width.pt(),height:m.height.pt()",
    )
    displays = [equation for equation in geometry if equation["block"]]
    assert len(displays) == 8, "a display equation was lost or silently became inline"
    pages = page_images(result)
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14
    page_width = result["pixel_width"] / scale
    margin = 36 if mode == "paged" else 24
    measured = []
    for index, equation in enumerate(displays):
        page = pages[equation["page"]]
        top = max(0, int(equation["y"] * scale) - 1)
        bottom = min(page.height, int((equation["y"] + equation["height"]) * scale) + 2)
        strip = page.crop((0, top, page.width, bottom))
        # Include antialiased glyphs at the smallest page scale while excluding
        # the quote panel and its greener rule (green >= 173).
        pixels = strip.load()
        mask = Image.new("1", strip.size)
        selected = mask.load()
        for y in range(strip.height):
            for x in range(strip.width):
                r, g, b = pixels[x, y]
                selected[x, y] = r < 170 and g < 170 and b < 180
        bounds = mask.getbbox()
        assert bounds is not None, f"equation {index} has no visible mathematical ink"
        center = (bounds[0] + bounds[2]) / 2
        # The list has only a left indent. Quotes have symmetric panel insets.
        expected = ((equation["x"] + page_width - margin) / 2) * scale if index == 4 else page.width / 2
        measured.append({"index": index, "center_px": center, "expected_px": expected, "ink": bounds})
        assert abs(center - expected) <= max(3, scale * 2), (
            f"display {index} visibly centers at {center:.1f}px, expected {expected:.1f}px; "
            "the outer block position alone does not establish glyph alignment"
        )
    (folder / "display-centers.json").write_text(json.dumps(measured, indent=2))


@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_narrow_code_keeps_its_last_token_inside_the_reading_area(render_design, mode):
    folder, result, found = render_design("06-narrow-layout", mode, 48)
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14
    marker = '#show regex("estimated_scale"): it => text(fill:rgb("ff0000"),it)\n'
    original = (folder / "document.typ").read_text()
    instrumented = folder / "code-boundary.typ"
    instrumented.write_text(marker + original)
    reference = folder / "code-reference.typ"
    reference.write_text(
        marker + original.split('#include "content.typ"')[0]
        + '#set page(width:auto,height:auto,margin:0pt)\n#raw("estimated_scale",lang:"python")\n'
    )
    for source, output in [(instrumented, "marked-code-{p}.png"), (reference, "code-reference.png")]:
        compilation = subprocess.run(
            [found["typst"], "compile", "--root", "/", "--format", "png", "--ppi", str(scale * 72), str(source), str(folder / output)],
            cwd=folder, capture_output=True, text=True, timeout=20,
        )
        assert compilation.returncode == 0, compilation.stderr

    def red_pixels(path):
        with Image.open(path) as image:
            rgb = image.convert("RGB")
            pixels = rgb.load()
            return [(x, y) for y in range(rgb.height) for x in range(rgb.width)
                    if pixels[x, y][0] > pixels[x, y][1] + 60
                    and pixels[x, y][0] > pixels[x, y][2] + 60]

    reference_count = len(red_pixels(folder / "code-reference.png"))
    assert reference_count > 0
    marked = [pixel for page in folder.glob("marked-code-*.png") for pixel in red_pixels(page)]
    assert len(marked) >= reference_count * 0.65, "the end token is missing or substantially clipped"
    # Only the token's colour changes. No context/metadata wrapper can silently
    # reflow the code or mistake its paragraph origin for the actual glyphs.
    margin = 36 if mode == "paged" else 24
    assert all(margin * scale - 2 <= x <= result["pixel_width"] - margin * scale + 2 for x, _ in marked)


@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_narrow_math_stays_complete_inside_the_page_body(render_design, mode):
    folder, result, found = render_design("06-narrow-layout", mode, 48)
    equations = query_geometry(
        folder, found, "math.equation",
        "block:it.block,page:p.page,x:p.x.pt(),y:p.y.pt(),width:m.width.pt(),height:m.height.pt()",
    )
    assert len(equations) == 4
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14
    page_width = result["pixel_width"] / scale
    margin = 36 if mode == "paged" else 24
    pages = page_images(result)
    for equation in equations:
        assert equation["width"] <= page_width - 2 * margin, "a complete equation is wider than the available page body"
        if not equation["block"]:
            assert margin <= equation["x"] and equation["x"] + equation["width"] <= page_width - margin
            continue
        image = pages[equation["page"]]
        top = max(0, int(equation["y"] * scale) - 1)
        bottom = min(image.height, int((equation["y"] + equation["height"]) * scale) + 2)
        strip = image.crop((0, top, image.width, bottom))
        selected = Image.new("1", strip.size)
        mask = selected.load()
        pixels = strip.load()
        for y in range(strip.height):
            for x in range(strip.width):
                r, g, b = pixels[x, y]
                mask[x, y] = r < 170 and g < 170 and b < 180
        bounds = selected.getbbox()
        assert bounds is not None
        assert bounds[0] >= margin * scale - 2 and bounds[2] <= (page_width - margin) * scale + 2


@pytest.mark.parametrize("mode", ["continuous", "paged"])
@pytest.mark.parametrize("columns", [90, 150])
def test_compact_figures_keep_the_typesetters_intrinsic_scale(render_design, mode, columns):
    folder, result, found = render_design("04-figures-and-assets", mode, columns)
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14
    margin = 36 if mode == "paged" else 24
    body_width = result["pixel_width"] / scale - 2 * margin
    actual = query_geometry(
        folder, found, "image", "width:m.width.pt(),height:m.height.pt()", measure_width=body_width,
    )
    assert len(actual) == 3, "one of the valid figures disappeared alongside a failed asset"
    compact = CORPUS / "assets/compact-diagram.png"
    # Ask the same typesetter for its natural image size in the same available
    # width. Source pixel dimensions are not terminal pixel dimensions.
    reference = folder / "intrinsic-image.typ"
    reference.write_text(f'''#context {{
      let natural=measure(image({json.dumps(str(compact))}),width:{body_width}pt)
      [#metadata((width:natural.width.pt(),height:natural.height.pt()))<intrinsic-image>]
    }}
''')
    query = subprocess.run(
        [found["typst"], "eval", "query(<intrinsic-image>).map(it=>it.value)",
         "--root", "/", "--in", str(reference)],
        cwd=folder, capture_output=True, text=True, timeout=20,
    )
    assert query.returncode == 0, query.stderr
    natural = json.loads(query.stdout)[0]
    assert actual[0]["width"] <= natural["width"] + 0.5, "a small figure was forcibly enlarged to fill the whole column"
    assert abs(actual[0]["width"] - actual[2]["width"]) <= 0.5, "equivalent local embed syntaxes changed image scale"
    assert actual[1]["width"] > actual[0]["width"], "small and wide figures were both forced to the same full-column size"


@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_heading_levels_have_a_descending_visible_hierarchy(render_design, mode):
    folder, _, found = render_design("02-document-hierarchy", mode, 90)
    headings = query_geometry(folder, found, "heading", "level:it.level,height:m.height.pt()")
    heights = {level: next(heading["height"] for heading in headings if heading["level"] == level) for level in (1, 2, 3, 4)}
    assert heights[1] > heights[2] > heights[3] > heights[4], (
        "the actual typeset heading hierarchy collapses or reverses at a deeper level"
    )


@pytest.mark.parametrize("mode", ["continuous", "paged"])
def test_default_table_prose_is_left_aligned_and_explicit_numbers_stay_right(render_design, mode):
    folder, result, found = render_design("03-tables-and-math", mode, 90)
    pattern = r"Ordinary prose|A longer item name|249\.00|1,249\.50|12\.00"
    document = folder / "table-alignment.typ"
    document.write_text(f'''#show regex({json.dumps(pattern)}): it => context {{
      let p=here().position()
      let m=measure(it)
      [#metadata((token:it.text,page:p.page,x:p.x.pt(),y:p.y.pt(),width:m.width.pt(),height:m.height.pt()))<table-alignment>#it]
    }}
''' + (folder / "document.typ").read_text())
    query = subprocess.run(
        [found["typst"], "eval", "query(<table-alignment>).map(it=>it.value)",
         "--root", "/", "--in", str(document)],
        cwd=folder, capture_output=True, text=True, timeout=20,
    )
    assert query.returncode == 0, query.stderr
    values = {point["token"]: point for point in json.loads(query.stdout)}
    assert set(values) == {"Ordinary prose", "A longer item name", "249.00", "1,249.50", "12.00"}
    pages = page_images(result)
    scale = result["pixel_width"] / 595 if mode == "paged" else 20 / 14

    def visible_edges(tokens):
        # Metadata locates the cell paragraph, not its horizontally aligned
        # glyphs. Inspect the original rendered ink within that column instead.
        left = min(values[token]["x"] for token in tokens) * scale - 2
        right = left + max(values[token]["width"] for token in tokens) * scale + 5
        edges = []
        for token in tokens:
            point = values[token]
            top = point["y"] * scale - 1
            bottom = (point["y"] + point["height"]) * scale + 3
            crop = pages[point["page"]].crop((int(left), int(top), int(right), int(bottom))).convert("L")
            bounds = crop.point(lambda value: 255 if value < 170 else 0).getbbox()
            assert bounds is not None, f"table token {token} has no visible ink"
            edges.append((int(left) + bounds[0], int(left) + bounds[2]))
        return edges

    prose = visible_edges(["Ordinary prose", "A longer item name"])
    assert abs(prose[0][0] - prose[1][0]) <= 1.5, (
        "default prose cells inherit centered figure alignment instead of a stable left edge"
    )
    numeric = visible_edges(["249.00", "1,249.50", "12.00"])
    ends = [right for _, right in numeric]
    assert max(ends) - min(ends) <= 1.5, "explicitly right-aligned numeric cells lost their shared right edge"
