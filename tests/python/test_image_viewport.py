"""Independent pixel and geometry contracts for raster viewport rendering."""

import pytest
from PIL import Image

pytestmark = [pytest.mark.fast, pytest.mark.python]


@pytest.fixture
def gradient(tmp_path):
    image = Image.new("RGB", (28, 28), "black")
    for x in range(28):
        for y in range(28):
            image.putpixel((x, y), (x * 9, y * 9, 255))
    source = tmp_path / "source.png"
    image.save(source)
    return source, image


def test_fit_preserves_nearest_neighbor_pixels(render_viewport, gradient, tmp_path):
    source, image = gradient
    target = tmp_path / "viewport.png"
    view = render_viewport(source, target, {"width": 280, "height": 280})
    assert view["scale"] == 10
    assert view["crop"] == [0, 0, 28, 28]
    assert not view["pan_x"] and not view["pan_y"]
    with Image.open(target) as output:
        assert output.getpixel((105, 205)) == image.getpixel((10, 20))
        assert set(output.get_flattened_data()) == set(image.get_flattened_data())


def test_zoom_out_below_fit(render_viewport, gradient, tmp_path):
    source, _ = gradient
    view = render_viewport(
        source, tmp_path / "view.png", {"width": 280, "height": 280, "zoom": 0.0625}
    )
    assert view["zoom"] == 0.0625
    assert max(view["image_rect"][2:]) == 18


def test_zero_zoom_clamps_to_one_pixel(render_viewport, gradient, tmp_path):
    source, _ = gradient
    view = render_viewport(
        source, tmp_path / "view.png", {"width": 280, "height": 280, "zoom": 0}
    )
    assert view["zoom"] > 0
    assert view["image_rect"][2:] == [1, 1]


def test_zoom_is_center_anchored(render_viewport, gradient, tmp_path):
    source, image = gradient
    target = tmp_path / "view.png"
    view = render_viewport(source, target, {"width": 280, "height": 280, "zoom": 2})
    assert view["crop"] == [7, 7, 21, 21]
    assert view["cx"] == view["cy"] == 0.5
    with Image.open(target) as output:
        assert output.getpixel((0, 0)) == image.getpixel((7, 7))


@pytest.mark.parametrize(
    "cx,cy",
    [(-20, -20), (-20, 20), (20, -20), (20, 20)],
    ids=["top-left", "bottom-left", "top-right", "bottom-right"],
)
def test_pan_clamps_to_source_bounds(render_viewport, gradient, tmp_path, cx, cy):
    source, _ = gradient
    target = tmp_path / "view.png"
    view = render_viewport(
        source, target, {"width": 280, "height": 280, "zoom": 32, "cx": cx, "cy": cy}
    )
    left, top, right, bottom = view["crop"]
    assert 0 <= left < right <= 28
    assert 0 <= top < bottom <= 28
    with Image.open(target) as output:
        assert output.size == (280, 280)


@pytest.mark.parametrize(
    "shape",
    [(200, 50), (50, 200), (1, 1), (1, 50)],
    ids=["wide", "tall", "single-pixel", "single-column"],
)
def test_fit_centers_each_aspect_ratio(render_viewport, tmp_path, shape):
    source, target = tmp_path / "source.png", tmp_path / "view.png"
    Image.new("RGB", shape, "red").save(source)
    view = render_viewport(
        source, target, {"width": 300, "height": 200, "cx": 100, "cy": -100}
    )
    x, y, width, height = view["image_rect"]
    assert abs((300 - width) / 2 - x) <= 0.5
    assert abs((200 - height) / 2 - y) <= 0.5
    assert view["cx"] == view["cy"] == 0.5
    with Image.open(target) as output:
        assert output.getpixel((150, 100)) == (255, 0, 0)


def test_transparency_uses_checkerboard(render_viewport, tmp_path):
    source, target = tmp_path / "source.png", tmp_path / "view.png"
    Image.new("RGBA", (8, 8), (255, 0, 0, 0)).save(source)
    render_viewport(source, target, {"width": 100, "height": 100})
    with Image.open(target) as output:
        assert set(output.get_flattened_data()) == {(69, 71, 90), (49, 50, 68)}


def test_raster_allocation_is_bounded(render_viewport, gradient, tmp_path):
    source, _ = gradient
    target = tmp_path / "view.png"
    render_viewport(source, target, {"width": 10000, "height": 1000})
    with Image.open(target) as output:
        assert output.size == (2048, 204)


def test_navigation_does_not_modify_source(render_viewport, gradient, tmp_path):
    source, _ = gradient
    original = source.read_bytes()
    for zoom, center in [
        (1, 0.5),
        (0.0625, 0.5),
        (0, 0.5),
        (2, 0.5),
        (32, -20),
        (32, 20),
    ]:
        render_viewport(
            source,
            tmp_path / "view.png",
            {"width": 280, "height": 280, "zoom": zoom, "cx": center, "cy": center},
        )
    assert source.read_bytes() == original
