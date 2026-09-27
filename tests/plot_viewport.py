"""Vector chart crops retain detail at physical-pixel resolution."""

import runpy
import tempfile
from pathlib import Path

from PIL import Image

render = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "scripts/image-viewport.py")
)["render"]
with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    png, svg, output = folder / "source.png", folder / "source.svg", folder / "view.png"
    # Deliberately blank PNG: visible detail must come from vectors, not upscaling.
    Image.new("RGB", (100, 100), "white").save(png)
    svg.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="white"/><path d="M0 0L100 100" stroke="black" stroke-width="0.15"/><text x="10" y="50" font-size="8">Vector text</text></svg>'
    )
    original = svg.read_bytes()
    for zoom in (1, 2, 32):
        v = render(
            png, output, {"width": 3000, "height": 1800, "svg": str(svg), "zoom": zoom}
        )
        assert Image.open(output).size == (3000, 1800)
        assert v["renderer"] == "vector"
        crop = Image.open(output).crop(
            (
                v["image_rect"][0],
                v["image_rect"][1],
                v["image_rect"][0] + v["image_rect"][2],
                v["image_rect"][1] + v["image_rect"][3],
            )
        )
        assert len(crop.getcolors(10_000_000)) > 2  # antialiased vector detail
        assert crop.convert("L").getextrema()[0] < 100
    for cx, cy in ((-10, -10), (10, 10)):
        v = render(
            png,
            output,
            {
                "width": 600,
                "height": 400,
                "svg": str(svg),
                "zoom": 32,
                "cx": cx,
                "cy": cy,
            },
        )
        assert 0 <= v["crop"][0] < v["crop"][2] <= 100
        assert 0 <= v["crop"][1] < v["crop"][3] <= 100
    v = render(png, output, {"width": 20000, "height": 20000, "svg": str(svg)})
    assert (
        v["width"] * v["height"] <= 24_000_000 and max(v["width"], v["height"]) <= 8192
    )
    assert svg.read_bytes() == original
    # Vega PNG uses 1.5x SVG dimensions: crop coordinates must still align.
    Image.new("RGB", (150, 150), "white").save(png)
    svg.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="white"/><rect x="20" y="40" width="10" height="10" fill="red"/></svg>'
    )
    render(png, output, {"width": 300, "height": 300, "svg": str(svg)})
    assert Image.open(output).getpixel((75, 135))[:3] == (255, 0, 0)
    render(
        png,
        output,
        {"width": 300, "height": 300, "svg": str(svg), "zoom": 2, "cx": 0.4},
    )
    assert Image.open(output).getpixel((60, 120))[:3] == (255, 0, 0)

print(
    "PASS: physical-resolution vector rendering, antialiased detail at 32x, bounded crops/allocation, unchanged SVG"
)
