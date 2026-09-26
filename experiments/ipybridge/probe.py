"""Exercise upstream namespace helpers/UI against a disposable Molten kernel.

Run with the editor host Python: probe.py PLUGIN_CHECKOUT DISPOSABLE_PROJECT.
The project's .venv needs ipykernel, numpy, pandas and torch. No plugin is installed.
"""

import ast
import json
import sys
import time
from pathlib import Path

import nbformat
import pynvim
from jupyter_client import BlockingKernelClient

plugin, project = (Path(p).resolve() for p in sys.argv[1:3])
connection = project / "probe-connection-path.txt"
connection.unlink(missing_ok=True)
path = project / "explorer-probe.ipynb"
code = f"""import numpy as np
import pandas as pd
import torch
from pathlib import Path
from ipykernel.connect import get_connection_file
sentinel = 'created by Molten'
array = np.arange(120).reshape(30, 4)
frame = pd.DataFrame(array, columns=['a', 'b', 'c', 'd'])
tensor = torch.arange(12, dtype=torch.float32).reshape(3, 4)
Path({str(connection)!r}).write_text(get_connection_file())
"""
nbformat.write(nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(code)]), path)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
)
client = None
try:
    n.ui_attach(150, 48, rgb=True)
    original = n.current.buffer[:]
    n.exec_lua("require('custom.python.notebook').init()")
    assert n.exec_lua(
        "return vim.wait(20000, function() return next(require('custom.python.notebook').ready) ~= nil end, 50)"
    )
    n.exec_lua("require('custom.python.notebook').run(true)")
    deadline = time.monotonic() + 90
    while not connection.exists() and time.monotonic() < deadline:
        n.eval("1")
        time.sleep(0.2)
    assert connection.exists(), "Molten fixture did not complete"
    client = BlockingKernelClient(connection_file=connection.read_text())
    client.load_connection_file()
    client.start_channels()
    client.wait_for_ready(timeout=15)

    def request(expression, setup=""):
        msg_id = client.execute(
            setup,
            silent=True,
            store_history=False,
            user_expressions={"result": expression},
        )
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            reply = client.get_shell_msg(timeout=15)
            if reply["parent_header"].get("msg_id") != msg_id:
                continue
            content = reply["content"]
            assert content["status"] == "ok", content
            result = content["user_expressions"]["result"]
            assert result["status"] == "ok", result
            return ast.literal_eval(result["data"]["text/plain"])
        raise AssertionError("Inspection timed out")

    # Load only the pure namespace helper, not upstream's debugger/bootstrap.
    setup = f"""import importlib.util as _probe_util
_probe_spec = _probe_util.spec_from_file_location('_probe_ns', {str(plugin / "python/ipybridge_ns.py")!r})
_probe_ns = _probe_util.module_from_spec(_probe_spec)
_probe_spec.loader.exec_module(_probe_ns)
"""
    assert request("sentinel", setup) == "created by Molten"
    count = request("get_ipython().execution_count")
    variables = request("_probe_ns.list_variables(get_ipython().user_ns)")
    assert variables["array"]["kind"] == "ndarray"
    assert variables["frame"]["kind"] == "dataframe"
    assert variables["tensor"]["type"] == "Tensor"
    # Upstream falls back to len(tensor), losing the remaining dimensions.
    assert variables["tensor"]["shape"] == [3]
    preview = request(
        "_probe_ns.preview_data('frame', get_ipython().user_ns, max_rows=5, row_offset=10)"
    )
    assert preview["rows"][0] == [40, 41, 42, 43]
    assert len(preview["rows"]) == 5
    tensor_preview = request("_probe_ns.preview_data('tensor', get_ipython().user_ns)")
    assert request("get_ipython().execution_count") == count
    # Check live state changes executed through Molten remain visible.
    n.command("MoltenEvaluateArgument sentinel = 'updated by Molten'")
    time.sleep(0.5)
    assert request("sentinel") == "updated by Molten"
    assert n.current.buffer[:] == original

    n.exec_lua(
        "vim.opt.rtp:append(...); require('ipybridge.var_explorer').open(false)",
        str(plugin),
    )
    n.exec_lua("require('ipybridge.var_explorer').on_vars(...)", variables)
    lines = n.current.buffer[:]
    assert any("tensor" in line and "Tensor" in line for line in lines), lines
    (project / "explorer-ui.txt").write_text("\n".join(lines))
    results = {
        "same_molten_kernel": True,
        "live_updates": True,
        "source_unchanged": True,
        "inspection_preserves_execution_count": True,
        "dataframe_paging": True,
        "tensor_entry": variables["tensor"],
        "tensor_preview": tensor_preview,
        "plugin_checkout": str(plugin),
    }
    (project / "results.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))
    print(
        "PASS: Molten sharing, live state, namespace UI, DataFrame paging, source/history preservation"
    )
finally:
    if client:
        client.stop_channels()
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
