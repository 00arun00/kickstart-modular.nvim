"""Encode one complete image without changing its source or importing plotting libraries."""

import base64
import struct
import sys
import zlib

MAX_PIXELS = 4_000_000


def preview(value, options):
    import numpy as np

    torch = sys.modules.get("torch")
    pil = sys.modules.get("PIL.Image")
    tensor = torch is not None and type(value) in (torch.Tensor, torch.nn.Parameter)
    is_pil = pil is not None and isinstance(value, pil.Image)
    if tensor:
        if (
            value.device.type == "meta"
            or value.is_quantized
            or str(value.layout) != "torch.strided"
        ):
            raise ValueError("Image viewing requires a dense, non-meta tensor")
    elif not is_pil and type(value) is not np.ndarray:
        raise ValueError(
            "Image viewing supports PyTorch tensors, NumPy arrays, and PIL images"
        )
    if is_pil:
        if value.width * value.height > MAX_PIXELS:
            raise ValueError(
                "Image exceeds the 4 million pixel preview limit; resize it in Python first"
            )
        value = np.asarray(
            value.convert(
                "RGBA"
                if "A" in value.getbands() or "transparency" in value.info
                else "RGB"
            )
        )
    shape = tuple(value.shape)
    layouts = {2: ["HW"], 3: ["CHW", "HWC", "BHW"], 4: ["NCHW", "NHWC"]}.get(
        len(shape), []
    )
    if not layouts or any(size == 0 for size in shape):
        raise ValueError("Choose a nonempty 2D, 3D, or 4D image array/tensor")
    layout = options.get("layout")
    if not layout:
        if len(shape) == 2:
            layout = "HW"
        elif is_pil:
            layout = "HWC"
        else:
            candidates = []
            if shape[-1] in (1, 3, 4):
                candidates.append("HWC" if len(shape) == 3 else "NHWC")
            if shape[-3] in (1, 3, 4):
                candidates.append("CHW" if len(shape) == 3 else "NCHW")
                if len(shape) == 3:
                    candidates.append("BHW")
            if len(shape) == 3 and not candidates:
                candidates = ["BHW"]
            if len(candidates) != 1:
                return {"choices": layouts, "shape": list(shape)}
            layout = candidates[0]
    if layout not in layouts:
        raise ValueError("Layout must be one of: " + ", ".join(layouts))
    batch_count = shape[0] if layout in ("BHW", "NCHW", "NHWC") else 1
    batch = max(0, min(int(options.get("batch", 0)), batch_count - 1))
    block = value[batch] if layout in ("BHW", "NCHW", "NHWC") else value
    channels = (
        block.shape[0]
        if layout in ("CHW", "NCHW")
        else (block.shape[-1] if layout in ("HWC", "NHWC") else 1)
    )
    height, width = block.shape[-2:] if layout in ("CHW", "NCHW") else block.shape[:2]
    if height * width > MAX_PIXELS:
        raise ValueError(
            "Image exceeds the 4 million pixel preview limit; resize it in Python first"
        )
    channel = options.get("channel", -1)
    channel = int(channel)
    if channel < 0 and channels not in (1, 3, 4):
        channel = 0
    if channel >= channels:
        raise ValueError(f"Channel must be between 0 and {channels - 1}")
    if channel >= 0:
        if layout in ("CHW", "NCHW"):
            block = block[channel]
        elif layout in ("HWC", "NHWC"):
            block = block[..., channel]
    if tensor:
        if block.is_complex():
            raise ValueError(
                "Complex tensors need an explicit real/imaginary conversion in Python"
            )
        # Select the image/channel before any device transfer.
        original_float = block.is_floating_point() or block.dtype == torch.bool
        block = block.detach().to(device="cpu", dtype=torch.float64).numpy()
    else:
        if block.dtype.kind not in "buif":
            raise ValueError("Image values must be real numbers or booleans")
        original_float = block.dtype.kind in "bf"
        block = block.astype(np.float64, copy=True)
    if channel < 0 and layout in ("CHW", "NCHW"):
        block = np.moveaxis(block, 0, -1)
    if block.ndim == 2:
        block = block[..., None]
    if block.shape[-1] == 1:
        block = np.repeat(block, 3, axis=-1)
    rgba = block.shape[-1] == 4
    color = block[..., :3]
    finite = np.isfinite(color)
    finite_values = color[finite]
    low = float(finite_values.min()) if finite_values.size else None
    high = float(finite_values.max()) if finite_values.size else None
    normalize = bool(options.get("normalize", False))
    upper = 1.0 if original_float else 255.0
    clipped = int(((color < 0) | (color > upper))[finite].sum())
    if normalize and low is not None:
        scale = max(abs(low), abs(high), 1.0)
        span = high / scale - low / scale
        color = (color / scale - low / scale) / span if span else np.zeros_like(color)
        mode = "Contrast: min/max → 0–255" + (" (constant → black)" if not span else "")
    else:
        color = color / upper
        mode = f"Original: 0–{upper:g} → 0–255; {clipped} clipped values"
    rgb = np.rint(np.clip(np.where(finite, color, 0), 0, 1) * 255).astype(np.uint8)
    if rgba:
        alpha = np.nan_to_num(block[..., 3:4] / upper, nan=0, posinf=1, neginf=0)
        rgb = np.concatenate(
            [rgb, np.rint(np.clip(alpha, 0, 1) * 255).astype(np.uint8)], axis=-1
        )

    # Minimal lossless PNG encoder; no Pillow dependency for arrays or tensors.
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row.tobytes() for row in rgb)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", width, height, 8, 6 if rgba else 2, 0, 0, 0),
        )
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )
    return {
        "png": base64.b64encode(png).decode("ascii"),
        "width": width,
        "height": height,
        "layout": layout,
        "choices": layouts,
        "batch": batch,
        "batch_count": batch_count,
        "channel": channel,
        "channels": channels,
        "normalize": normalize,
        "scaling": mode,
        "nonfinite": int((~finite).sum()),
        "min": low,
        "max": high,
    }
