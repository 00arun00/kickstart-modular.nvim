"""Full-source extraction contracts; run with the disposable project's Python."""

import json
import runpy
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import torch

see = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "lua/custom/python/helpers/inspect-namespace.py")
)["inspect_namespace"]


def plot(value, **options):
    data = see(
        {"x": value}, {"name": "x", "action": "plot_data", "plot_options": options}
    )
    assert "error" not in data, data
    return data["plot"]


frame = pd.DataFrame(
    {
        "epoch": np.arange(10000),
        "train_loss": np.exp(-np.arange(10000) / 2200) + 0.05,
        "val_loss": np.exp(-np.arange(10000) / 2500) + 0.12,
    }
)
before = frame.copy()
r = plot(frame, x=0, ys=[1, 2], limit=500)
assert (
    r["source_rows"] == 10000 and r["emitted_rows"] == 500 and len(r["records"]) == 1000
)
assert r["records"][0]["x"] == 0 and r["records"][499]["x"] == 9999
assert "can miss spikes" in r["caption"]
exact = plot(frame, x=0, ys=[1, 2], start=100, stop=200)
assert not exact["sampled"] and len(exact["records"]) == 200
hist = plot(frame, style="histogram", ys=[1, 2], bins=40)
assert sum(v["y"] for v in hist["records"]) == 20000
assert hist["emitted_rows"] == 10000 and not hist["sampled"]
assert [(v["x"], v["x2"]) for v in hist["records"][:40]] == [
    (v["x"], v["x2"]) for v in hist["records"][40:]
]
dup = pd.DataFrame([[3, 10], [1, 20], [2, 30]], columns=["x", "x"])
rdup = plot(dup, x=0, ys=[1])
assert [r["x"] for r in rdup["records"]] == [3, 1, 2]
assert rdup["y_labels"] == ["x [1]"]
missing = plot(
    np.array([[0, 1, 10], [1, np.nan, 11], [2, 3, np.inf], [3, 4, 13]]), x=0, ys=[1, 2]
)
a = [r for r in missing["records"] if r["series"] == "1 [1]"]
assert [r["x"] for r in a] == [0, 2, 3] and a[0]["segment"] != a[1]["segment"]
assert missing["skipped"] == 2
assert plot(pd.Series([1, 2, 3]))["source_rows"] == 3
assert (
    plot(torch.arange(120).reshape(2, 3, 4, 5), slice=[1, 2], ys=[0])["records"][0]["y"]
    == 100
)
assert plot(np.ones(20), style="histogram")["records"]
assert (
    plot(np.arange(100).reshape(20, 5), style="heatmap", ys=list(range(5)), limit=10)[
        "emitted_rows"
    ]
    == 2
)
for value, options in [
    (np.array([-1e308, 1e308]), {"style": "histogram"}),
    (np.array([1e308]), {}),
    (frame, {"ys": []}),
    (frame, {"ys": [99]}),
    (frame, {"stop": 10001}),
    (frame, {"start": 2, "stop": 2}),
    (frame, {"limit": 1}),
    (np.empty((0, 2)), {}),
    (np.full((2, 2), np.nan), {}),
    (np.zeros((100001, 1)), {"style": "histogram"}),
    (torch.empty(2, 2, device="meta"), {}),
]:
    assert "error" in see(
        {"x": value}, {"name": "x", "action": "plot_data", "plot_options": options}
    )
pd.testing.assert_frame_equal(frame, before)
if len(sys.argv) > 1:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for style in ["line", "scatter", "histogram", "heatmap"]:
        data = plot(
            frame
            if style != "heatmap"
            else np.sin(np.arange(1200).reshape(60, 20) / 20),
            style=style,
            x=0,
            ys=[1, 2] if style != "heatmap" else list(range(20)),
            limit=1200,
        )
        (out / (style + ".json")).write_text(
            json.dumps(
                {
                    "data": data,
                    "settings": {
                        "title": "Training and validation"
                        if style != "heatmap"
                        else "Activation matrix",
                        "xlabel": "Epoch" if style in ("line", "scatter") else "",
                        "legend": True,
                    },
                }
            )
        )
print(
    "PASS: full-source ranges, deterministic bounded sampling, exact histograms, positional duplicate columns, missing-value alignment/gaps, tensor slicing, heatmaps, invalid/empty inputs, no mutation"
)
