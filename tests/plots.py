"""Verify actual project-kernel plot payloads and Molten notebook export."""

import base64
import io
import sys
import time
from pathlib import Path

import nbformat
import pynvim
from PIL import Image

project = Path(sys.argv[1]).resolve()
notebook = project / "pde-plots.ipynb"
nbformat.write(
    nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_code_cell(
                "import matplotlib.pyplot as plt\nplt.plot([1, 2, 3], [1, 4, 2])\nplt.show()"
            ),
            nbformat.v4.new_code_cell(
                "import seaborn as sns\nsns.scatterplot(x=[1, 2, 3], y=[3, 1, 4])\nplt.show()"
            ),
            nbformat.v4.new_code_cell(
                "import plotly.graph_objects as go\ngo.Figure(go.Scatter(x=[1, 2], y=[3, 4])).show(renderer='notebook')"
            ),
        ]
    ),
    notebook,
)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-i", "NONE", str(notebook)]
)
try:
    n.exec_lua(
        "_G.plot_messages = {}; vim.notify = function(m) table.insert(_G.plot_messages, m) end"
    )
    n.exec_lua("require('custom.python.notebook').init()")
    assert n.exec_lua(
        "return vim.wait(15000, function() return next(require('custom.python.notebook').ready) ~= nil end, 50)"
    )
    n.exec_lua("require('custom.python.notebook').run(true)")
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        time.sleep(0.5)
        n.exec_lua("require('custom.python.notebook').export()")
        nb = nbformat.read(notebook, as_version=4)
        outputs = [o for c in nb.cells for o in c.get("outputs", [])]
        errors = [o for o in outputs if o.output_type == "error"]
        assert not errors, errors
        pngs = [
            o.data["image/png"] for o in outputs if "image/png" in o.get("data", {})
        ]
        html = [
            o.data["text/html"] for o in outputs if "text/html" in o.get("data", {})
        ]
        if len(pngs) == 2 and any("Plotly.newPlot" in h for h in html):
            break
    else:
        raise AssertionError(n.exec_lua("return _G.plot_messages"))
    for png in pngs:
        with Image.open(io.BytesIO(base64.b64decode(png))) as image:
            assert image.width > 100 and image.height > 100
            image.verify()
    n.command("MoltenDeinit")
    print(
        "PASS: Matplotlib and Seaborn PNGs, Plotly HTML, Molten export through project .venv"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
