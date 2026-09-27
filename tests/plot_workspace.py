"""Real Neovim/kernel image viewer controls, output preservation and captures."""

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

project, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
(out / "export.svg").unlink(missing_ok=True)
n = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"])
client = None


def wait(fn, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError(
        "Timeout: "
        + "\n".join(n.current.buffer[:])
        + "\n"
        + str(n.api.exec2("messages", {"output": True}))
    )


def query(expression):
    mid = client.execute(
        "", silent=True, store_history=False, user_expressions={"v": expression}
    )
    while True:
        reply = client.get_shell_msg(timeout=20)
        if reply["parent_header"].get("msg_id") == mid:
            value = reply["content"]["user_expressions"]["v"]
            assert value["status"] == "ok", value
            return ast.literal_eval(value["data"]["text/plain"])


def image_data():
    return wait(lambda: n.current.buffer.vars.get("image_snapshot"))


def viewport(previous=None):
    return wait(
        lambda: (
            v
            if (v := n.current.buffer.vars.get("image_viewport"))
            and v["file"] != previous
            else None
        )
    )


def key(k):
    n.input(k)
    time.sleep(0.1)


def shot(name, width=150, height=48):
    n.exec_lua("require('noice').cmd('dismiss'); require('snacks').notifier.hide()")
    capture(n, out / name, width, height)


try:
    n.ui_attach(150, 48, rgb=True, ext_linegrid=True)
    path = project / "plot-review.ipynb"
    code = """import numpy as np
import pandas as pd
metrics = pd.DataFrame({'epoch': np.arange(10000), 'train': np.exp(-np.arange(10000)/2000), 'validation': np.exp(-np.arange(10000)/3000)+0.1})
print('plot output preserved')"""
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
    wait(lambda: query("'metrics' in get_ipython().user_ns"))
    count, names = (
        query("get_ipython().execution_count"),
        query("sorted(get_ipython().user_ns)"),
    )
    n.exec_lua("require('custom.python.variables').open('metrics')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("p")
    wait(lambda: n.current.buffer.vars.get("plot_schema"))
    panel = n.current.buffer.number
    n.exec_lua(
        "vim.ui.select=function(items,opts,cb) cb(table.remove(_G.choices,1)) end; vim.ui.input=function(opts,cb) cb(table.remove(_G.inputs,1)) end"
    )

    def select(k, choices):
        n.exec_lua("_G.choices = ...", choices)
        key(k)
        wait(lambda: n.exec_lua("return #_G.choices == 0"))

    def inputs(k, values):
        n.exec_lua("_G.inputs = ...", values)
        key(k)

    select("x", [0])
    select("y", [0, 1, 2, -1])
    inputs("l", ["Training and validation", "Epoch", "Loss"])
    inputs("s", ["500"])
    key("<CR>")
    snap = wait(lambda: n.current.buffer.vars.get("plot_snapshot"), 45)
    assert "500/10,000" in snap["caption"] and snap["settings"]["ys"] == [1, 2]
    shot("01-setup.png")
    for ext, file in snap["files"].items():
        (out / ("chart." + ext)).write_bytes(Path(file).read_bytes())
    n.exec_lua("vim.ui.open=function(path) vim.g.plot_opened=path end")
    key("b")
    assert n.vars["plot_opened"] == snap["files"]["html"]
    inputs("e", [str(out / "export.svg")])
    assert (out / "export.svg").read_bytes() == Path(snap["files"]["svg"]).read_bytes()
    (out / "export.svg").write_text("keep existing")
    inputs("e", [str(out / "export.svg")])
    assert (out / "export.svg").read_text() == "keep existing"
    n.exec_lua(
        "_G.plot_terminal_size = require('snacks.image.terminal').size; require('snacks.image.terminal').size = function() return {cell_width=16,cell_height=32,scale=2} end"
    )
    key("v")
    image_data()
    fitted = viewport()
    assert fitted["renderer"] == "vector"
    assert fitted["width"] == (n.current.window.width - 2) * 16
    assert fitted["height"] == (n.current.window.height - 5) * 32
    n.exec_lua(
        "require('snacks.image.terminal').size = function() return {cell_width=24,cell_height=48,scale=3} end"
    )
    key("0")
    fitted = viewport(fitted["file"])
    assert fitted["width"] == (n.current.window.width - 2) * 24
    (out / "sharp-viewport.png").write_bytes(Path(fitted["file"]).read_bytes())
    shot("09-sharp-preview.png")
    key("+")
    zoomed = viewport(fitted["file"])
    assert zoomed["zoom"] > fitted["zoom"]
    key("0")
    viewport(zoomed["file"])
    key("?")
    shot("02-preview-help.png")
    key("q")
    key("q")
    n.exec_lua("require('snacks.image.terminal').size = _G.plot_terminal_size")
    assert n.current.buffer.number == panel
    assert n.current.buffer.vars["plot_settings"]["ys"] == [1, 2]
    key("?")
    shot("03-help.png")
    key("q")
    inputs("r", ["100, 200"])
    assert not n.current.buffer.vars.get("plot_snapshot")
    select("t", ["histogram"])
    key("<CR>")
    wait(lambda: n.current.buffer.vars.get("plot_snapshot"), 45)
    shot("04-histogram.png")
    inputs("r", ["300, 200"])
    key("<CR>")
    wait(lambda: "nonempty row range" in "\n".join(n.current.buffer[:]))
    assert not n.current.buffer.vars.get("plot_snapshot")
    shot("05-error.png")
    inputs("r", ["0, 10000"])
    select("t", ["heatmap"])
    key("<CR>")
    wait(lambda: n.current.buffer.vars.get("plot_snapshot"), 45)
    n.ui_try_resize(70, 25)
    time.sleep(0.2)
    shot("06-narrow.png", 70, 25)
    n.ui_try_resize(150, 48)
    key("R")
    key("q")
    time.sleep(0.3)
    assert n.current.buffer.options["filetype"] == "molten-variables", (
        n.current.buffer.options["filetype"],
        n.current.buffer[:],
        n.api.exec2("messages", {"output": True}),
    )
    assert n.buffers[source][:] == original
    assert query("get_ipython().execution_count") == count
    assert query("sorted(get_ipython().user_ns)") == names
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.notebook').export()")
    saved = nbformat.read(path, as_version=4)
    assert "plot output preserved" in "".join(
        o.get("text", o.get("data", {}).get("text/plain", ""))
        for o in saved.cells[0].outputs
    )
    # Adversarial labels are valid DataFrame columns; the TUI must stay usable.
    query(
        "setattr(metrics, 'columns', ['epoch', 'loss\\ntrain', 'loss\\rvalidation']) or True"
    )
    n.exec_lua("require('custom.python.variables').open('metrics')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("p")
    wait(lambda: n.current.buffer.vars.get("plot_schema"))
    select("y", [0, 1, 2, -1])
    assert any("loss train" in line for line in n.current.buffer[:])
    key("<CR>")
    wait(lambda: n.current.buffer.vars.get("plot_snapshot"), 45)
    shot("07-labels.png")
    # Closing during a new draw must not resurrect the panel.
    key("<CR>")
    key("q")
    time.sleep(0.4)
    assert n.current.buffer.options["filetype"] == "molten-variables"
    key("p")
    wait(lambda: n.current.buffer.vars.get("plot_schema"))
    query("get_ipython().user_ns.pop('metrics') is not None")
    key("R")
    wait(lambda: "Variable no longer exists" in "\n".join(n.current.buffer[:]))
    assert not n.current.buffer.vars.get("plot_snapshot")
    shot("08-deleted-source.png")
    key("q")
    print(
        "PASS: real kernel full-source setup, multi-series, range/sampling, preview/zoom/fit, offline browser dispatch, export/no-overwrite, errors, resize, close during refresh, source/history/outputs preserved"
    )
finally:
    if client:
        client.stop_channels()
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
