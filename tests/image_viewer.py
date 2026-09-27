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
from PIL import Image

project, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
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
    path = project / "image-review.ipynb"
    code = """import torch
import numpy as np
from PIL import Image
X = torch.zeros(64, 1, 28, 28)
X[0, 0, 4:24, 8:20] = 1
X[1, 0, 8:20, 4:24] = 0.5
rgb = np.zeros((24, 32, 3), dtype=np.uint8)
rgb[:, :16, 0] = 255
rgb[:, 16:, 1] = 180
ambiguous = np.zeros((3, 28, 3), dtype=np.uint8)
pil_image = Image.fromarray(rgb)
bundle = {'image': rgb}
print('image output preserved')"""
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
    wait(lambda: query("'pil_image' in get_ipython().user_ns"))
    count, names = (
        query("get_ipython().execution_count"),
        query("sorted(get_ipython().user_ns)"),
    )
    n.exec_lua("require('custom.python.variables').open('X')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    inspector = n.current.buffer.number
    key("i")
    first = image_data()
    assert (first["width"], first["height"], first["batch_count"]) == (28, 28, 64)
    assert Image.open(first["file"]).getpixel((8, 4)) == (255, 255, 255)
    (out / "complete-image.png").write_bytes(Path(first["file"]).read_bytes())
    fitted = viewport()
    assert fitted["zoom"] == 1 and fitted["scale"] > 1
    (out / "fit-canvas.png").write_bytes(Path(fitted["file"]).read_bytes())
    shot("01-complete.png")
    # Exercise terminal-branch placement and delayed detection without pretending
    # a headless capture proves physical terminal rendering.
    n.exec_lua("""
      _G.image_native = {status=require('custom.python.images').status,
        detect=require('snacks.image.terminal').detect,
        supports=require('snacks').image.supports_terminal,
        placement=require('snacks.image.placement').new}
      _G.image_detect_callbacks = {}
      vim.g.image_places, vim.g.image_closes = 0, 0
      require('custom.python.images').status = function() return true end
      require('snacks').image.supports_terminal = function() return true end
      require('snacks.image.terminal').detect = function(cb) table.insert(_G.image_detect_callbacks, cb) end
      require('snacks.image.placement').new = function(buf, file, opts)
        vim.g.image_places = vim.g.image_places + 1; vim.g.image_placement_opts = opts
        return { close = function() vim.g.image_closes = vim.g.image_closes + 1 end }
      end
    """)
    key("+")
    pending = viewport(fitted["file"])
    key("?")
    n.exec_lua("for _, cb in ipairs(_G.image_detect_callbacks) do cb() end")
    assert n.vars["image_places"] == 0  # late detection cannot draw over help
    key("q")
    pending = viewport(pending["file"])
    n.exec_lua("for _, cb in ipairs(_G.image_detect_callbacks) do cb() end")
    assert n.vars["image_places"] == 1
    placement = n.vars["image_placement_opts"]
    assert (
        placement["pos"] == [5, 1]
        and placement["width"] > 100
        and placement["height"] > 20
    )
    key("0")
    fitted = viewport(pending["file"])
    n.exec_lua("for _, cb in ipairs(_G.image_detect_callbacks) do cb() end")
    assert n.vars["image_places"] == 2 and n.vars["image_closes"] >= 1
    n.exec_lua("""
      require('custom.python.images').status = _G.image_native.status
      require('snacks.image.terminal').detect = _G.image_native.detect
      require('snacks').image.supports_terminal = _G.image_native.supports
      require('snacks.image.placement').new = _G.image_native.placement
    """)
    n.exec_lua(
        "_G.image_system = vim.system; vim.g.image_kernel_calls = 0; vim.system = function(cmd, ...) if cmd[2]:find('inspect-kernel.py', 1, true) then vim.g.image_kernel_calls = vim.g.image_kernel_calls + 1 end; return _G.image_system(cmd, ...) end"
    )
    key("++")
    zoomed = viewport(fitted["file"])
    assert abs(zoomed["zoom"] - 2) < 0.001
    assert zoomed["cx"] == 0.5 and zoomed["cy"] == 0.5
    (out / "zoom-canvas.png").write_bytes(Path(zoomed["file"]).read_bytes())
    shot("05-zoom.png")
    key("3l")
    panned = viewport(zoomed["file"])
    assert panned["cx"] > zoomed["cx"]
    (out / "pan-canvas.png").write_bytes(Path(panned["file"]).read_bytes())
    for _ in range(18):
        old = viewport()["file"]
        key("l" if _ % 2 else "h")
        viewport(old)
    assert Path(first["file"]).exists()  # viewport cache must not evict the original
    n.input("llllllllllllllllhhhhhhhhhhhhhhhh")
    time.sleep(0.4)
    edge = viewport()
    assert 0 <= edge["crop"][0] < edge["crop"][2] <= 28
    key("0")
    reset = viewport(edge["file"])
    assert reset["zoom"] == 1 and reset["cx"] == 0.5
    key("?")
    assert "IMAGE VIEWER" in "\n".join(n.current.buffer[:])
    shot("06-help.png")
    key("q")
    viewport(reset["file"])
    before_resize = viewport()["file"]
    n.ui_try_resize(70, 25)
    time.sleep(0.2)
    viewport(before_resize)
    shot("07-narrow.png", 70, 25)
    key("?")
    key("20j")
    assert n.current.window.cursor[0] > 15
    shot("08-help-scroll.png", 70, 25)
    key("q")
    n.ui_try_resize(28, 12)
    time.sleep(0.2)
    assert "Enlarge window" in "\n".join(n.current.buffer[:])
    n.ui_try_resize(150, 48)
    time.sleep(0.2)
    viewport()
    assert n.vars["image_kernel_calls"] == 0
    n.exec_lua("vim.system = _G.image_system")
    key("]")
    second = image_data()
    assert second["batch"] == 1
    assert Image.open(second["file"]).getpixel((4, 8)) == (128, 128, 128)
    key("n")
    contrast = image_data()
    assert contrast["normalize"]
    assert Image.open(contrast["file"]).getpixel((4, 8)) == (255, 255, 255)
    shot("02-contrast.png")
    key("[")
    assert image_data()["batch"] == 0
    key("q")
    assert n.current.buffer.number == inspector
    # Exercise picker callbacks deterministically without depending on a UI provider.
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open('rgb')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("i")
    assert image_data()["layout"] == "HWC"
    n.exec_lua(
        "vim.g.image_test_select = 0; _G.image_test_ui = vim.ui.select; vim.ui.select = function(items, opts, cb) cb(vim.g.image_test_select) end"
    )
    key("c")
    assert image_data()["channel"] == 0
    n.exec_lua("vim.ui.select = _G.image_test_ui")
    key("q")
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open('ambiguous')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    n.exec_lua(
        "vim.ui.select = function(items, opts, cb) vim.g.image_layout_choices = items; cb('CHW') end"
    )
    key("i")
    assert image_data()["layout"] == "CHW"
    assert n.vars["image_layout_choices"] == ["CHW", "HWC", "BHW"]
    n.exec_lua("vim.ui.select = _G.image_test_ui")
    key("q")
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open('bundle')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("i")
    assert image_data()["width"] == 32
    assert 'bundle["image"]' in str(n.api.win_get_config(n.current.window)["title"])
    key("q")
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.variables').open('pil_image')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("i")
    assert image_data()["width"] == 32
    shot("03-pil.png")
    # Closing while refresh is queued must not reopen or update a dead viewer.
    key("r")
    key("q")
    time.sleep(0.3)
    assert n.current.buffer.options["filetype"] == "molten-variables"
    assert n.buffers[source][:] == original
    assert query("get_ipython().execution_count") == count
    assert query("sorted(get_ipython().user_ns)") == names
    assert query("float(X[1,0,8,4])") == 0.5
    n.exec_lua("require('custom.python.variables').close()")
    n.api.set_current_buf(source)
    n.exec_lua("require('custom.python.notebook').export()")
    saved = nbformat.read(path, as_version=4)
    assert "image output preserved" in "".join(
        o.get("text", o.get("data", {}).get("text/plain", ""))
        for o in saved.cells[0].outputs
    )
    n.exec_lua("require('custom.python.variables').open('pil_image')")
    wait(lambda: n.current.buffer.vars.get("variable_snapshot"))
    key("i")
    image_data()
    query("(get_ipython().user_ns.pop('pil_image'), True)[1]")
    key("r")
    wait(lambda: "Variable no longer exists" in "\n".join(n.current.buffer[:]))
    n.exec_lua(
        "_G.image_test_open = vim.ui.open; vim.ui.open = function() vim.g.opened_stale_image = true end"
    )
    key("o")
    assert not n.vars.get("opened_stale_image")
    n.exec_lua("vim.ui.open = _G.image_test_open")
    shot("04-recovery.png")
    key("?")
    assert "IMAGE VIEWER" in "\n".join(n.current.buffer[:])
    key("q")
    assert "Variable no longer exists" in "\n".join(n.current.buffer[:])
    key("q")
    print(
        "PASS: complete PNG pixels, batch/channel/contrast/layout/PIL controls, close during refresh, no source/namespace/history/output mutation"
    )
finally:
    if client:
        client.stop_channels()
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
