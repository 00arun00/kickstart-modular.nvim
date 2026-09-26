"""Adversarial value/rendering contracts; run in the disposable project Python."""

import runpy
from pathlib import Path

import numpy as np
import pandas as pd
import torch

inspect_value = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "scripts/inspect-namespace.py")
)["inspect_namespace"]


def see(value, **request):
    return inspect_value({"x": value}, {"name": "x", **request})


class Record:
    def __init__(self):
        self.child = {"values": [1, 2]}

    @property
    def dangerous(self):
        raise AssertionError("property was evaluated")

    def __repr__(self):
        raise AssertionError("repr was evaluated")


record = Record()
assert see(record)["children"][0]["name"] == "child"
assert (
    see(
        record,
        path=[
            {"kind": "attr", "key": "child"},
            {"kind": "key", "key": "values"},
            {"kind": "index", "key": 1},
        ],
    )["note"]
    == "2"
)
assert "error" in see(record, path=[{"kind": "attr", "key": "dangerous"}])
assert see({None: 3}, path=[{"kind": "key", "key": None}])["note"] == "3"
assert see([2, 3])["children"][1]["path"] == [{"kind": "index", "key": 1}]
large_key = 2**70 + 1
path = see({large_key: "exact"})["children"][0]["path"]
assert path == [{"kind": "int_key", "key": str(large_key)}]
assert see({large_key: "exact"}, path=path)["note"] == "exact"
precise = see(pd.DataFrame({"value": ["000123", 9007199254740993, 1.2345678901]}))
assert precise["display_rows"] == [["000123"], ["9007199254740993"], ["1.23457"]]
assert precise["rows"][2] == ["1.2345678901"]
assert see("line one\nline two\tend")["note"] == "line one\nline two\tend"
assert "truncated at 10000" in see("x" * 10001)["note"]
assert see(torch.arange(120).reshape(2, 3, 4, 5), slice=[1, 2], cols=3)["rows"][0] == [
    "100",
    "101",
    "102",
]
assert "error" in see(torch.ones(2, 3), slice=[1])
assert "error" in see(np.arange(3), filter={"column": 0, "op": ">", "value": 0})
frame = pd.DataFrame({"x": [3, 1, 2], "text": ["long\ntext", "b", "c"]})
assert see(frame, sort_col=0)["rows"][0] == ["1", "b"]
assert see(frame, filter={"column": 0, "op": ">", "value": 1})["total_rows"] == 2
assert see(frame, row=999, col=999)["row"] == 2
assert see(frame, row=999, col=999)["col"] == 1
ns = {
    "x": record,
    "__nvim_inspect_renderers__": {
        "rows": lambda value: {
            "rows": [[i, i + 1] for i in range(35)],
            "columns": ["a", "b"],
        }
    },
}
rendered = inspect_value(ns, {"name": "x", "renderer": "rows", "row": 20, "cols": 1})
assert (
    rendered["total_rows"] == 35
    and len(rendered["rows"]) == 15
    and rendered["rows"][0] == ["20"]
)
ns["__nvim_inspect_renderers__"]["ragged"] = lambda v: {"rows": [[1, 2], [], [3]]}
assert (
    "<svg"
    in inspect_value(
        ns,
        {
            "name": "x",
            "renderer": "ragged",
            "action": "plot",
            "plot": "line",
            "selected_col": 1,
        },
    )["plot"]
)
ns["__nvim_inspect_renderers__"]["ragged"] = lambda v: {"rows": [[], [1, 2], [3]]}
assert (
    "<svg"
    in inspect_value(
        ns, {"name": "x", "renderer": "ragged", "action": "plot", "selected_col": 1}
    )["plot"]
)
for style in ("line", "histogram", "heatmap"):
    result = see(
        np.array([[1e308], [-1e308], [float("nan")]]), action="plot", plot=style
    )
    assert "plot" in result, result
    assert "nan" not in result["plot"].lower()
assert "error" in see(np.array([[float("nan")]]), action="plot")
assert "<svg" in see(np.array([[1.0], [float("nan")], [3.0]]), action="plot")["plot"]
assert "<svg" in see(np.ones((1, 1)), action="plot")["plot"]
assert see(torch.empty(2, 0, 3))["rows"] == []
print(
    "PASS: structural paths, properties/repr excluded, lossless/truncated text, dynamic columns/slices, unsupported controls, DataFrame views, renderer paging/ragged plots, extreme/nonfinite/constant/empty values"
)
