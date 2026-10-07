"""Generate wide/tall viewport examples: python tests/capture_image_viewport.py OUTPUT_DIR."""

import argparse
import runpy
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
output = parser.parse_args().output
output.mkdir(parents=True, exist_ok=True)
render = runpy.run_path(
    str(
        Path(__file__).resolve().parents[1]
        / "lua/custom/python/helpers/image-viewport.py"
    )
)["render"]
with tempfile.TemporaryDirectory() as folder:
    source = str(Path(folder) / "source.png")
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
