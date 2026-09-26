"""Real-kernel workspace scenarios and review captures; disposable project only."""

import ast
import json
import sys
import time
import uuid
from pathlib import Path

import nbformat
import pynvim
from capture_grid import capture
from jupyter_client import BlockingKernelClient

project = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
n = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"])
client = None


def wait(fn, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("Timed out")


def snap():
    return wait(lambda: n.current.buffer.vars.get("variable_snapshot"))


def action(name, *args):
    buffer = n.current.buffer
    n.exec_lua('require("custom.python.variables")[...] (select(2,...))', name, *args)
    return wait(lambda: buffer.vars.get("variable_snapshot"))


def query(expression):
    mid = client.execute(
        "", silent=True, store_history=False, user_expressions={"v": expression}
    )
    while True:
        msg = client.get_shell_msg(timeout=15)
        if msg["parent_header"].get("msg_id") == mid:
            value = msg["content"]["user_expressions"]["v"]
            assert value["status"] == "ok", value
            return ast.literal_eval(value["data"]["text/plain"])


def shot(name, width=150, height=48):
    n.exec_lua("require('noice').cmd('dismiss'); require('snacks').notifier.hide()")
    capture(n, out / (name + ".png"), width, height)


def open_view(name=None):
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open(...)", name)
    return snap()


try:
    n.ui_attach(150, 48, rgb=True, ext_linegrid=True)
    code = """import torch
import numpy as np
import pandas as pd
features = torch.arange(120., requires_grad=True).reshape(2, 3, 4, 5)
metrics = pd.DataFrame({'step': range(60), 'loss': [1/(i+1) for i in range(60)], 'split': ['train' if i%2 else 'valid' for i in range(60)]})
series = pd.Series([3, 1, 2], name='score')
experiment = {'model': {'weights': features, 'labels': ['cat', 'dog']}, 42: {'answer': 'yes'}}
long_text = 'Long text: ' + 'abcdefghij'*100
class Record:
    def __init__(self): self.metrics = metrics
    @property
    def dangerous(self): raise RuntimeError('must not evaluate properties')
record = Record()
duplicate = pd.DataFrame([[2, 4], [1, 9]], columns=['x', 'x'])
__nvim_inspect_renderers__ = {'summary': lambda value: {'columns': ['metric', 'value'], 'rows': [['layers', 4], ['params', 120]], 'note': 'Model summary'}}
for _i in range(220): globals()['sample_'+str(_i)] = _i
print('workspace output intact')
"""
    path = project / "workspace-review.ipynb"
    nbformat.write(
        nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(code)]), path
    )
    n.command("edit " + n.funcs.fnameescape(str(path)))
    source = n.current.buffer.number
    original = n.current.buffer[:]
    n.exec_lua("require('custom.python.notebook').init()")
    kernel = n.funcs.MoltenRunningKernels(True)[0]
    wait(
        lambda: n.exec_lua(
            "return require('custom.python.notebook').ready[...]", kernel
        )
    )
    registry = n.exec_lua(
        "return require('custom.python.notebook').connections[...]", kernel
    )
    client = BlockingKernelClient(
        connection_file=json.loads(Path(registry).read_text())["connection"]
    )
    client.session.session = "nvim-inspector-" + uuid.uuid4().hex
    client.load_connection_file()
    client.start_channels(iopub=False, stdin=False, hb=False, control=False)
    n.exec_lua("require('custom.python.notebook').run(true)")
    assert query("'sample_219' in get_ipython().user_ns")
    target = next(
        i
        for i, line in enumerate(n.current.buffer[:], 1)
        if line.startswith("features =")
    )
    n.current.window.cursor = (target, 0)
    n.funcs.winrestview({"topline": target})
    count = query("get_ipython().execution_count")
    keys = query("sorted(get_ipython().user_ns)")
    data = open_view()
    assert data["total"] >= 227
    data = action("view", {"row": 200})
    assert len(data["entries"]) > 0
    data = action("filter", "metrics")
    assert [v["name"] for v in data["entries"]] == ["metrics"], data
    action("filter", "")
    shot("01-list")
    selected = next(
        i
        for i, line in enumerate(n.current.buffer[:], 1)
        if line.strip().startswith("metrics ")
    )
    n.current.window.cursor = (selected, 0)
    time.sleep(0.1)
    action("refresh")
    assert n.current.line.strip().startswith("metrics ")
    action("enter")
    action("back")
    assert n.current.line.strip().startswith("metrics ")
    data = open_view("experiment")
    assert len(data["children"]) == 2
    data = action("view", {"path": [{"kind": "key", "key": 42}]})
    assert data["children"][0]["summary"] == "yes"
    data = action("view", {"path": [{"kind": "key", "key": "model"}]})
    shot("02-nested")
    data = action(
        "view",
        {
            "path": [
                {"kind": "key", "key": "model"},
                {"kind": "key", "key": "weights"},
            ],
            "slice": [1, 2],
        },
    )
    assert data["rows"][0][0] == "100.0"
    shot("03-tensor")
    assert "error" in action("slice", "99, 0")
    shot("08-recover-slice")
    assert action("slice", "0, 1")["rows"][0][0] == "20.0"
    data = open_view("record")
    assert data["children"][0]["name"] == "metrics"
    data = open_view("metrics")
    assert len(data["rows"]) == 20
    assert "error" in action("filter", '> "bad"')
    assert len(action("filter", "")["rows"]) == 20
    data = action("filter", ">= 30")
    assert data["total_rows"] == 30
    data = action("sort")
    assert data["rows"][0][0] == "30"
    data = action("sort")
    assert data["rows"][0][0] == "59"
    shot("04-table")
    # Select the numeric loss column then generate a plot from this page.
    n.input("l")
    time.sleep(0.1)
    data = action("plot", "line")
    assert n.api.win_get_config(n.current.window)["relative"] == "editor"
    assert n.current.window.height >= 25
    shot("09-plot-viewer")
    # Plot creates a floating viewer; get the artifact from the inspector buffer.
    n.input("q")
    time.sleep(0.1)
    plot = n.current.buffer.vars["variable_plot"]
    (out / "plot.svg").write_text(Path(plot).read_text())
    assert "<svg" in Path(plot).read_text()
    png = wait(lambda: n.current.buffer.vars.get("variable_plot_image"))
    (out / "07-plot.png").write_bytes(Path(png).read_bytes())
    data = open_view("duplicate")
    data = action("view", {"sort_col": 1})
    assert data["rows"][0] == ["2", "4"]
    data = open_view("series")
    assert data["columns"] == ["score"]
    data = open_view("long_text")
    assert len(data["note"]) > 1000
    data = open_view("record")
    data = action("view", {"renderer": "summary"})
    assert data["rows"][0] == ["layers", "4"]
    shot("05-renderer")
    n.exec_lua("require('custom.python.variables').close()")
    n.ui_try_resize(86, 36)
    time.sleep(0.2)
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open('metrics')")
    snap()
    shot("06-narrow", 86, 36)
    assert n.current.window.width >= 80
    n.ui_try_resize(150, 48)
    time.sleep(0.2)
    snap()
    assert n.current.window.width < 100
    shot("10-resized-wide")
    assert n.buffers[source][:] == original
    assert query("get_ipython().execution_count") == count
    assert query("sorted(get_ipython().user_ns)") == keys
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.notebook').export()")
    saved = nbformat.read(path, as_version=4)
    assert "workspace output intact" in "".join(
        o.get("text", o.get("data", {}).get("text/plain", ""))
        for o in saved.cells[0].outputs
    )
    print(
        "PASS: >200 variables, filter, nested paths/non-string keys, object fields, slices/errors, DataFrame filter/sort, duplicate columns, Series, long text, custom renderer, plot SVG, narrow layout, source/history/output preservation"
    )
finally:
    if client:
        client.stop_channels()
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
