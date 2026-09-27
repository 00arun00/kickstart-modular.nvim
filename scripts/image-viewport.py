"""Render a bounded local image viewport; never contact the notebook kernel."""

import json
import sys

from PIL import Image, ImageDraw


def render(source, target, options):
    width = max(1, int(options["width"]))
    height = max(1, int(options["height"]))
    bound = min(1, 2048 / width, 2048 / height)
    width, height = max(1, int(width * bound)), max(1, int(height * bound))
    zoom = max(0.25, min(32, float(options.get("zoom", 1))))
    background = options.get("background", "#1e1e2e")
    with Image.open(source) as image:
        image = image.convert("RGBA")
        iw, ih = image.size
        fit = min(width / iw, height / ih)
        scale = fit * zoom
        # Coordinate system is source pixels, with the viewport centered at cx/cy.
        span_x, span_y = min(iw, width / scale), min(ih, height / scale)
        cx = float(options.get("cx", 0.5)) * iw
        cy = float(options.get("cy", 0.5)) * ih
        cx = max(span_x / 2, min(iw - span_x / 2, cx))
        cy = max(span_y / 2, min(ih - span_y / 2, cy))
        left, top = cx - span_x / 2, cy - span_y / 2
        dw, dh = (
            min(width, max(1, round(iw * scale))),
            min(height, max(1, round(ih * scale))),
        )
        x, y = (width - dw) // 2, (height - dh) // 2
        # Transform directly into the viewport; never allocate a huge zoomed image.
        tile = image.transform(
            (dw, dh),
            Image.Transform.AFFINE,
            (1 / scale, 0, left, 0, 1 / scale, top),
            resample=Image.Resampling.NEAREST,
        )
        canvas = Image.new("RGBA", (width, height), background)
        # A checkerboard makes transparent pixels distinguishable from black.
        if image.getextrema()[3][0] < 255:
            checker = ImageDraw.Draw(canvas)
            for yy in range(y, y + dh, 12):
                for xx in range(x, x + dw, 12):
                    fill = (
                        "#45475a"
                        if ((xx - x) // 12 + (yy - y) // 12) % 2
                        else "#313244"
                    )
                    checker.rectangle(
                        (xx, yy, min(xx + 11, x + dw - 1), min(yy + 11, y + dh - 1)),
                        fill=fill,
                    )
        canvas.alpha_composite(tile, (x, y))
        canvas.convert("RGB").save(target, dpi=(96, 96))
    return {
        "width": width,
        "height": height,
        "zoom": zoom,
        "scale": scale,
        "cx": cx / iw,
        "cy": cy / ih,
        "source_width": iw,
        "source_height": ih,
        "crop": [left, top, left + span_x, top + span_y],
        "pan_x": span_x < iw - 1e-6,
        "pan_y": span_y < ih - 1e-6,
        "image_rect": [x, y, dw, dh],
    }


if __name__ == "__main__":
    try:
        print(json.dumps(render(sys.argv[1], sys.argv[2], json.loads(sys.argv[3]))))
    except (ValueError, OSError, KeyError, IndexError) as exc:
        print(json.dumps({"error": str(exc)}))
        sys.exit(1)
