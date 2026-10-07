"""Vector detail, coordinate alignment, and cached navigation contracts."""

import pytest
from PIL import Image

pytestmark = [pytest.mark.fast, pytest.mark.python]


@pytest.fixture
def vector_detail(tmp_path):
    png, svg = tmp_path / "source.png", tmp_path / "source.svg"
    # Blank pixels: visible detail must come from vectors, not PNG upscaling.
    Image.new("RGB", (100, 100), "white").save(png)
    svg.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="white"/><path d="M0 0L100 100" stroke="black" stroke-width="0.15"/><text x="10" y="50" font-size="8">Vector text</text></svg>'
    )
    return png, svg


@pytest.fixture
def scaled_vector(tmp_path):
    # Vega PNGs can use 1.5x SVG dimensions; coordinates must still align.
    png, svg = tmp_path / "source.png", tmp_path / "source.svg"
    Image.new("RGB", (150, 150), "white").save(png)
    svg.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="white"/><rect x="20" y="40" width="10" height="10" fill="red"/></svg>'
    )
    return png, svg


@pytest.mark.parametrize("zoom", [1, 2, 32], ids=["fit", "2x", "32x"])
def test_vector_detail_at_physical_resolution(
    render_viewport, vector_detail, tmp_path, zoom
):
    png, svg = vector_detail
    output = tmp_path / "view.png"
    view = render_viewport(
        png, output, {"width": 3000, "height": 1800, "svg": str(svg), "zoom": zoom}
    )
    assert view["renderer"] == "vector"
    with Image.open(output) as image:
        assert image.size == (3000, 1800)
        x, y, width, height = view["image_rect"]
        crop = image.crop((x, y, x + width, y + height))
        assert len(crop.getcolors(10_000_000)) > 2  # antialiased detail
        assert crop.convert("L").getextrema()[0] < 100


@pytest.mark.parametrize(
    "cx,cy", [(-10, -10), (10, 10)], ids=["top-left", "bottom-right"]
)
def test_vector_pan_clamps_to_source_bounds(
    render_viewport, vector_detail, tmp_path, cx, cy
):
    png, svg = vector_detail
    view = render_viewport(
        png,
        tmp_path / "view.png",
        {"width": 600, "height": 400, "svg": str(svg), "zoom": 32, "cx": cx, "cy": cy},
    )
    left, top, right, bottom = view["crop"]
    assert 0 <= left < right <= 100
    assert 0 <= top < bottom <= 100


def test_vector_allocation_is_bounded(render_viewport, vector_detail, tmp_path):
    png, svg = vector_detail
    view = render_viewport(
        png, tmp_path / "view.png", {"width": 20000, "height": 20000, "svg": str(svg)}
    )
    assert view["width"] * view["height"] <= 24_000_000
    assert max(view["width"], view["height"]) <= 8192


def test_vector_navigation_preserves_svg(render_viewport, vector_detail, tmp_path):
    png, svg = vector_detail
    original = svg.read_bytes()
    for zoom, center in [(1, 0.5), (2, 0.5), (32, -10), (32, 10)]:
        render_viewport(
            png,
            tmp_path / "view.png",
            {
                "width": 600,
                "height": 400,
                "svg": str(svg),
                "zoom": zoom,
                "cx": center,
                "cy": center,
            },
        )
    assert svg.read_bytes() == original


@pytest.mark.parametrize(
    "options,pixel",
    [({}, (75, 135)), ({"zoom": 2, "cx": 0.4}, (60, 120))],
    ids=["fit", "zoom-and-pan"],
)
def test_scaled_png_and_svg_coordinates_align(
    render_viewport, scaled_vector, tmp_path, options, pixel
):
    png, svg = scaled_vector
    output = tmp_path / "view.png"
    render_viewport(
        png, output, {"width": 300, "height": 300, "svg": str(svg), **options}
    )
    with Image.open(output) as image:
        assert image.getpixel(pixel)[:3] == (255, 0, 0)


@pytest.fixture
def cached_vector(render_viewport, scaled_vector, tmp_path):
    png, svg = scaled_vector
    cache = tmp_path / "native.png"
    native = render_viewport(png, cache, {"width": 300, "height": 300, "svg": str(svg)})
    native["file"] = str(cache)
    svg.unlink()  # Cache navigation must work without reading the vector source.
    return png, {"width": 300, "height": 300, "svg": str(svg), "cache": native}


def test_cache_navigation_works_without_svg(render_viewport, cached_vector, tmp_path):
    png, options = cached_vector
    output = tmp_path / "view.png"
    view = render_viewport(png, output, {**options, "zoom": 2, "cx": 0.4})
    assert view["renderer"] == "cached"
    with Image.open(output) as image:
        assert image.getpixel((60, 120))[:3] == (255, 0, 0)


def test_cache_navigation_has_no_cumulative_resampling(
    render_viewport, cached_vector, tmp_path
):
    png, options = cached_vector
    output = tmp_path / "view.png"
    render_viewport(png, output, {**options, "zoom": 2, "cx": 0.4})
    original = output.read_bytes()
    render_viewport(png, output, {**options, "zoom": 10})
    render_viewport(png, output, {**options, "zoom": 2, "cx": 0.4})
    assert output.read_bytes() == original
