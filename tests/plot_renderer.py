"""Host-side chart rendering, artifacts, and offline HTML checks."""

import json
import runpy
import sys
from pathlib import Path

from PIL import Image

render = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "lua/custom/python/helpers/render-plot.py")
)["render"]
root = Path(sys.argv[1])
for style in ("line", "scatter", "histogram", "heatmap"):
    payload = json.loads((root / (style + ".json")).read_text())
    files = render(payload, root / style)
    assert Image.open(files["png"]).width > 1000
    assert "<svg" in Path(files["svg"]).read_text()
    html = Path(files["html"]).read_text()
    assert (
        "<script src=" not in html and "vegaEmbed(" in html and "editor:false" in html
    )
    assert (
        json.loads(Path(files["json"]).read_text())["data"]["values"]
        == payload["data"]["records"]
    )
payload["settings"]["title"] = "</script><script>alert(1)</script>"
files = render(payload, root / "escaped")
assert "</script><script>alert(1)" not in Path(files["html"]).read_text()
print(
    "PASS: four chart types, PNG/SVG/JSON artifacts, embedded offline browser assets, escaped labels"
)
