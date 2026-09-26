"""Pixel-level contracts for complete image previews; run in a disposable project."""

import base64
import io
import runpy
from pathlib import Path

import numpy as np
import torch
from PIL import Image

inspect_value = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "scripts/inspect-namespace.py")
)["inspect_namespace"]


def preview(value, **options):
    data = inspect_value(
        {"x": value}, {"name": "x", "action": "image", "image_options": options}
    )
    assert "error" not in data, data
    return data["image"]


def pixels(result):
    return np.asarray(Image.open(io.BytesIO(base64.b64decode(result["png"]))))


x = torch.arange(64 * 28 * 28, dtype=torch.float32).reshape(64, 1, 28, 28)
before = x.clone()
r = preview(x, batch=63, normalize=True)
assert (r["width"], r["height"], r["batch"], r["batch_count"]) == (28, 28, 63, 64)
assert pixels(r).shape == (28, 28, 3)
assert pixels(r)[0, 0].tolist() == [0, 0, 0]
assert pixels(r)[-1, -1].tolist() == [255, 255, 255]
assert torch.equal(x, before)
assert preview(x, batch=999)["batch"] == 63
assert preview(np.zeros((3, 28, 3)))["choices"] == ["CHW", "HWC", "BHW"]
assert pixels(preview(np.zeros((3, 28, 3)), layout="CHW")).shape == (28, 3, 3)
assert pixels(preview(np.ones((2, 28, 28)), layout="BHW", batch=1)).max() == 255
rgb = np.zeros((18, 24, 3), dtype=np.uint8)
rgb[..., 0], rgb[..., 1], rgb[..., 2] = 255, 128, 7
assert np.array_equal(pixels(preview(rgb)), rgb)
assert pixels(preview(rgb, channel=1))[0, 0].tolist() == [128, 128, 128]
assert np.array_equal(pixels(preview(np.moveaxis(rgb, -1, 0), layout="CHW")), rgb)
assert "choices" in preview(np.zeros((3, 28, 28)))
assert np.array_equal(pixels(preview(np.stack([rgb, rgb]), batch=1)), rgb)
assert np.array_equal(pixels(preview(Image.fromarray(rgb))), rgb)
rgba = np.concatenate([rgb, np.full((18, 24, 1), 37, dtype=np.uint8)], axis=-1)
assert np.array_equal(pixels(preview(rgba)), rgba)
assert (pixels(preview(rgba, normalize=True))[..., 3] == 37).all()
palette = Image.new("P", (10, 10), 0)
palette.info["transparency"] = 0
assert (pixels(preview(palette))[..., 3] == 0).all()
assert pixels(preview(torch.ones((8, 8), dtype=torch.bool))).min() == 255
assert pixels(preview(torch.ones((8, 8), dtype=torch.bfloat16))).min() == 255
assert pixels(preview(np.full((8, 8), 3.0), normalize=True)).max() == 0
assert pixels(preview(np.array([[float("nan"), float("inf"), -1, 0.5, 2]])))[
    0, :, 0
].tolist() == [0, 0, 0, 128, 255]
assert pixels(preview(np.array([[-1e308, 1e308]]), normalize=True))[
    0, :, 0
].tolist() == [0, 255]
assert np.array_equal(pixels(preview(rgb[:, ::-1])), rgb[:, ::-1])
for bad in [
    np.zeros((0, 1)),
    np.zeros(8),
    np.ones((8, 8), dtype=complex),
    torch.empty(8, 8, device="meta"),
    np.broadcast_to(1, (4001, 1000)),
    "text",
]:
    assert "error" in inspect_value({"x": bad}, {"name": "x", "action": "image"})
assert "error" in inspect_value(
    {"x": rgb}, {"name": "x", "action": "image", "image_options": {"channel": 9}}
)
print(
    "PASS: complete 28x28 batch images, layout ambiguity, grayscale/RGB/RGBA/PIL, alpha, channels, float/bool/bfloat16, extremes/nonfinite/constant values, bounds, and no source mutation"
)
