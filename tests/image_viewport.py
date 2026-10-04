"""Pixel and geometry contracts for local zoom/pan rendering."""

import runpy
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

render = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "lua/custom/python/helpers/image-viewport.py")
)["render"]
with tempfile.TemporaryDirectory() as folder:
    source, target = (
        str(Path(folder) / "source.png"),
        str(Path(folder) / "viewport.png"),
    )
    image = Image.new("RGB", (28, 28), "black")
    for x in range(28):
        for y in range(28):
            image.putpixel((x, y), (x * 9, y * 9, 255))
    image.save(source)
    original = Path(source).read_bytes()
    v = render(source, target, {"width": 280, "height": 280})
    assert v["scale"] == 10 and v["crop"] == [0, 0, 28, 28]
    out = Image.open(target)
    assert out.getpixel((105, 205)) == image.getpixel((10, 20))
    assert set(out.get_flattened_data()) == set(image.get_flattened_data())
    assert not v["pan_x"] and not v["pan_y"]
    small = render(source, target, {"width": 280, "height": 280, "zoom": 0.0625})
    assert small["zoom"] == 0.0625 and max(small["image_rect"][2:]) == 18
    smallest = render(source, target, {"width": 280, "height": 280, "zoom": 0})
    assert smallest["zoom"] > 0 and smallest["image_rect"][2:] == [1, 1]
    v = render(source, target, {"width": 280, "height": 280, "zoom": 2})
    assert v["crop"] == [7, 7, 21, 21] and v["cx"] == 0.5 and v["cy"] == 0.5
    assert Image.open(target).getpixel((0, 0)) == image.getpixel((7, 7))
    for cx in (-20, 20):
        for cy in (-20, 20):
            v = render(
                source,
                target,
                {"width": 280, "height": 280, "zoom": 32, "cx": cx, "cy": cy},
            )
            assert 0 <= v["crop"][0] < v["crop"][2] <= 28
            assert 0 <= v["crop"][1] < v["crop"][3] <= 28
            assert Image.open(target).size == (280, 280)
    assert Path(source).read_bytes() == original
    for shape in [(200, 50), (50, 200), (1, 1), (1, 50)]:
        Image.new("RGB", shape, "red").save(source)
        v = render(source, target, {"width": 300, "height": 200, "cx": 100, "cy": -100})
        x, y, w, h = v["image_rect"]
        assert abs((300 - w) / 2 - x) <= 0.5 and abs((200 - h) / 2 - y) <= 0.5
        assert v["cx"] == 0.5 and v["cy"] == 0.5
        assert Image.open(target).getpixel((150, 100)) == (255, 0, 0)
    Image.new("RGBA", (8, 8), (255, 0, 0, 0)).save(source)
    render(source, target, {"width": 100, "height": 100})
    colors = set(Image.open(target).get_flattened_data())
    assert colors == {(69, 71, 90), (49, 50, 68)}
    v = render(source, target, {"width": 10000, "height": 1000})
    assert Image.open(target).size == (2048, 204)
    if len(sys.argv) > 1:
        output = Path(sys.argv[1])
        output.mkdir(parents=True, exist_ok=True)
        for name, size in [("color-wide", (160, 64)), ("color-tall", (64, 160))]:
            color = Image.new("RGBA", size, (0, 0, 0, 0))
            draw = ImageDraw.Draw(color)
            for x in range(0, size[0], 8):
                for y in range(0, size[1], 8):
                    draw.rectangle(
                        (x, y, x + 6, y + 6),
                        fill=(
                            int(x / size[0] * 255),
                            int(y / size[1] * 255),
                            180,
                            255 if x < size[0] // 2 else 120,
                        ),
                    )
            color.save(source)
            render(source, str(output / (name + ".png")), {"width": 800, "height": 480})
print(
    "PASS: centered fit, nearest-neighbor pixels, center-anchored zoom, clamped pans, wide/tall/tiny images, alpha checkerboard, unchanged original"
)
