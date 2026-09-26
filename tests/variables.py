"""Real Molten explorer integration. Pass a disposable project with torch/pandas/ipykernel."""

import ast
import json
import sys
import time
import uuid
from pathlib import Path

import nbformat
import pynvim
from jupyter_client import BlockingKernelClient

project = Path(sys.argv[1]).resolve()
n = pynvim.attach("child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"])
clients = []


def wait(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out")


def query(client, expression):
    mid = client.execute(
        "", silent=True, store_history=False, user_expressions={"v": expression}
    )
    while True:
        reply = client.get_shell_msg(timeout=15)
        if reply["parent_header"].get("msg_id") == mid:
            item = reply["content"]["user_expressions"]["v"]
            assert item["status"] == "ok", item
            return ast.literal_eval(item["data"]["text/plain"])


def new_notebook(filename, code):
    path = project / filename
    nbformat.write(
        nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(code)]), path
    )
    n.command("edit " + n.funcs.fnameescape(str(path)))
    buf = n.current.buffer.number
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
    client.start_channels()
    clients.append(client)
    n.exec_lua("require('custom.python.notebook').run(true)")
    wait(lambda: query(client, "'sentinel' in get_ipython().user_ns"), 60)
    return buf, original, client, kernel, registry


def open_explorer(buf, name=None):
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(buf)
    n.exec_lua("require('custom.python.variables').open(...)", name)
    assert n.current.buffer.options["filetype"] == "molten-variables"
    return snapshot()


def snapshot():
    return wait(lambda: n.current.buffer.vars.get("variable_snapshot"), 12)


try:
    n.ui_attach(150, 48, rgb=True, ext_linegrid=True)
    first, source, client, kernel, registry = new_notebook(
        "variables-one.ipynb",
        """import torch
import numpy as np
import pandas as pd
tensor = torch.arange(600., requires_grad=True).reshape(30, 20)
scalar = torch.tensor(4.)
empty = torch.empty(0, 3)
cube = torch.arange(24).reshape(2, 3, 4)
meta = torch.empty(2, 4, device='meta')
frame = pd.DataFrame(np.arange(600).reshape(30, 20))
array = np.arange(24).reshape(4, 6).T
repr_calls = 0
class Unfriendly:
    def __repr__(self):
        global repr_calls
        repr_calls += 1
        raise RuntimeError('must not inspect repr')
custom = Unfriendly()
sentinel = 'first kernel'
print('output intact')
""",
    )
    count = query(client, "get_ipython().execution_count")
    keys = query(client, "sorted(get_ipython().user_ns.keys())")
    data = open_explorer(first)
    entries = {v["name"]: v for v in data["entries"]}
    assert entries["tensor"]["shape"] == [30, 20]
    assert entries["tensor"]["dtype"] == "torch.float32"
    assert entries["tensor"]["device"] == "cpu"
    assert entries["tensor"]["requires_grad"] is True
    assert entries["sentinel"]["summary"] == "first kernel"
    if len(sys.argv) > 2:
        from capture_grid import capture

        n.exec_lua("require('noice').cmd('dismiss'); require('snacks').notifier.hide()")
        capture(n, sys.argv[2])
    # Exercise the actual Enter mapping, then row and column paging.
    row = next(
        i
        for i, line in enumerate(n.current.buffer[:], 1)
        if line.strip().startswith("tensor ")
    )
    n.current.window.cursor = (row, 0)
    n.input("\r")
    wait(
        lambda: (
            n.current.buffer.vars.get("variable_snapshot", {}).get("name") == "tensor"
        )
    )
    data = snapshot()
    assert len(data["rows"]) == 20 and 1 <= len(data["rows"][0]) <= 8
    assert data["rows"][0][0] == "0.0"
    n.input("]p")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot", {}).get("row") == 20)
    assert snapshot()["rows"][0][0] == "400.0"
    n.input("]c")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot", {}).get("col", 0) > 0)
    assert float(snapshot()["rows"][0][0]) == 400 + snapshot()["col"]
    assert open_explorer(first, "cube")["rows"][0] == ["0", "1", "2", "3"]
    assert open_explorer(first, "scalar")["rows"] == [["4.0"]]
    assert open_explorer(first, "empty")["rows"] == []
    assert "Metadata only" in open_explorer(first, "meta")["note"]
    assert open_explorer(first, "array")["rows"][0] == ["0", "6", "12", "18"]
    frame = open_explorer(first, "frame")
    assert frame["rows"][0] == [str(i) for i in range(len(frame["columns"]))]
    assert open_explorer(first, "custom")["children"] == []
    assert "no longer exists" in open_explorer(first, "missing")["error"]
    assert query(client, "repr_calls") == 0
    assert query(client, "get_ipython().execution_count") == count
    assert query(client, "sorted(get_ipython().user_ns.keys())") == keys
    assert n.buffers[first][:] == source
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(first)
    n.exec_lua("require('custom.python.notebook').export()")
    saved = nbformat.read(project / "variables-one.ipynb", as_version=4)
    assert (
        "".join(
            o.get("text", o.get("data", {}).get("text/plain", ""))
            for o in saved.cells[0].outputs
        )
        == "output intact\n"
    )
    # Normal re-execution after inspection still has its output and count.
    open_explorer(first)
    n.exec_lua(
        "vim.api.nvim_buf_call(..., function() require('custom.python.notebook').run(true) end)",
        first,
    )
    wait(lambda: query(client, "get_ipython().execution_count") == count + 1)
    time.sleep(0.5)
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(first)
    n.exec_lua("require('custom.python.notebook').export()")
    saved = nbformat.read(project / "variables-one.ipynb", as_version=4)
    assert saved.cells[0].execution_count == count
    assert (
        "".join(
            o.get("text", o.get("data", {}).get("text/plain", ""))
            for o in saved.cells[0].outputs
        )
        == "output intact\n"
    )
    second, _, client2, _, _ = new_notebook(
        "variables-two.ipynb", "sentinel = 'second kernel'"
    )
    assert n.exec_lua("return require('custom.python.notebook').ready[...]", kernel)
    assert (
        next(v for v in open_explorer(second)["entries"] if v["name"] == "sentinel")[
            "summary"
        ]
        == "second kernel"
    )
    assert (
        next(v for v in open_explorer(first)["entries"] if v["name"] == "sentinel")[
            "summary"
        ]
        == "first kernel"
    )
    # Busy inspection times out without interrupting user code.
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(first)
    n.command("MoltenEvaluateArgument import time; time.sleep(8)")
    time.sleep(0.3)
    assert (
        "busy" in open_explorer(first).get("error", "").lower()
        or "timed out" in snapshot().get("error", "").lower()
    )
    time.sleep(4)
    n.input("r")
    wait(lambda: "entries" in n.current.buffer.vars.get("variable_snapshot", {}))
    # Restart gets a new generation; old names disappear.
    old_generation = json.loads(Path(registry).read_text())["generation"]
    n.exec_lua(
        "vim.api.nvim_buf_call(..., function() vim.cmd.MoltenEvaluateArgument('time.sleep(2)') end)",
        first,
    )
    n.exec_lua("require('custom.python.variables').refresh()")
    n.exec_lua(
        "vim.api.nvim_buf_call(..., function() require('custom.python.notebook').restart() end)",
        first,
    )
    wait(
        lambda: n.exec_lua(
            "return require('custom.python.notebook').ready[...]", kernel
        )
    )
    assert json.loads(Path(registry).read_text())["generation"] != old_generation
    assert "error" in snapshot(), snapshot()
    assert not any(v["name"] == "tensor" for v in open_explorer(first)["entries"])
    # Stopping the source kernel cannot refresh from the other notebook's kernel.
    inspector = n.current.buffer.number
    n.exec_lua(
        "vim.api.nvim_buf_call(..., function() vim.cmd.MoltenDeinit() end)", first
    )
    n.exec_lua("require('custom.python.variables').refresh()")
    assert "stopped" in n.buffers[inspector].vars["variable_snapshot"]["error"]
    n.api.buf_delete(first, {"force": True})
    n.exec_lua("require('custom.python.variables').refresh()")
    assert "closed" in n.buffers[inspector].vars["variable_snapshot"]["error"]
    print(
        "PASS: tensor metadata/previews, scalar/empty/meta/3D/noncontiguous values, DataFrames, UI paging, output/rerun preservation, no repr/source/history changes, two kernels, busy timeout, restart, stop and buffer close"
    )
finally:
    for client in clients:
        client.stop_channels()
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
