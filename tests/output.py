"""Real Molten output-window regression test; pass a disposable uv project."""

import sys
import time
from pathlib import Path

import pynvim

project = Path(sys.argv[1]).resolve()
source = project / "pde_output.py"
source.write_text(
    '# %%\nfor i in range(100):\n    print(f"row {i:03d}: " + "x" * 180)\n'
)
n = pynvim.attach(
    "child", argv=["nvim", "--embed", "--headless", "-i", "NONE", str(source)]
)


def wait(check, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(n.exec_lua("return _G.output_messages"))


def wait_output(text):
    # Observe Molten's available output text through its public command without
    # opening/focusing the window whose one-press behavior we are about to test.
    def available():
        n.command("silent MoltenYankOutput")
        return text in n.funcs.getreg('"')

    wait(available)


try:
    n.exec_lua(
        "_G.output_messages = {}; vim.notify = function(msg) table.insert(_G.output_messages, msg) end; vim.o.lines=60; vim.o.columns=160; vim.opt.clipboard={}"
    )
    n.exec_lua("require('custom.python.notebook').init()")
    wait(
        lambda: n.exec_lua(
            "return next(require('custom.python.notebook').ready) ~= nil"
        )
    )
    n.current.window.cursor = (2, 0)
    source_win = n.current.window.handle
    source_buf = n.current.buffer.handle
    original = n.current.buffer[:]
    n.exec_lua("require('custom.python.notebook').run()")
    wait_output("row 099:")
    n.exec_lua("require('custom.python.output').preview()")
    floating = [w for w in n.windows if n.api.win_get_config(w)["relative"] == "win"]
    assert len(floating) == 1
    preview = n.api.win_get_config(floating[0])
    assert "More Lines" in str(preview.get("footer", "")), preview
    n.exec_lua("require('custom.python.output').hide()")
    # One call must both open and focus the float.
    n.exec_lua("require('custom.python.output').enter()")
    assert n.current.window.handle != source_win
    output_buf = n.current.buffer
    wait(lambda: any("row 099:" in line for line in output_buf[:]))
    config = n.api.win_get_config(n.current.window)
    assert config["relative"] == "win"
    wait(
        lambda: (
            "MoltenOutputBorderSuccess"
            in str(n.api.win_get_config(n.current.window)["border"])
        )
    )
    assert config["height"] <= 24 and config["width"] <= 120, config
    assert not n.current.window.options["foldenable"]
    assert not n.current.window.options["wrap"]
    assert len(output_buf[:]) >= 100
    n.command("normal! G")
    assert n.current.window.cursor[0] == len(output_buf[:])
    n.input("gw")
    wait(lambda: n.current.window.options["wrap"])
    n.input("q")
    wait(lambda: n.current.window.handle == source_win)
    assert n.current.buffer.handle == source_buf
    n.exec_lua("require('custom.python.output').enter()")
    n.input(" jO")
    wait(
        lambda: (
            n.current.buffer.options["buftype"] == "nofile"
            and n.current.buffer.options["filetype"] == "molten_output"
        )
    )
    assert n.current.window.handle != source_win
    assert n.api.win_get_config(n.current.window)["relative"] == ""
    assert any("row 099:" in line for line in n.current.buffer[:])
    assert not n.current.buffer.options["modifiable"]
    assert not n.current.buffer.options["buflisted"]
    snapshot_buf = n.current.buffer.handle
    n.input(n.replace_termcodes("<Esc>", True, False, True))
    wait(lambda: n.current.window.handle == source_win)
    assert not n.api.buf_is_valid(snapshot_buf)
    assert n.current.buffer[:] == original
    # Closing and reopening output must retain the kernel and full results.
    n.exec_lua("require('custom.python.output').enter()")
    assert any("row 099:" in line for line in n.current.buffer[:])
    n.input("q")
    wait(lambda: n.current.window.handle == source_win)
    assert n.exec_lua("return #vim.fn.MoltenRunningKernels(true)") == 1
    n.current.buffer.append(["# %%", "raise RuntimeError('pde-output-error')"])
    n.current.window.cursor = (len(n.current.buffer[:]), 0)
    n.exec_lua("require('custom.python.notebook').run()")
    wait_output("pde-output-error")
    n.exec_lua("require('custom.python.output').enter()")
    assert "pde-output-error" in "\n".join(n.current.buffer[:])
    wait(
        lambda: (
            "MoltenOutputBorderFail"
            in str(n.api.win_get_config(n.current.window)["border"])
        )
    )
    n.input("q")
    wait(lambda: n.current.window.handle == source_win)
    # Entering output must work with the cell end off screen, whether or not
    # the installed upstream version still exhibits the original window bug.
    start = len(n.current.buffer[:]) + 2
    n.current.buffer.append(
        ["# %%", "value = 1"] + ["# padding"] * 80 + ["print('long-cell-output')"]
    )
    n.current.window.cursor = (start, 0)
    n.command("normal! zt")
    n.exec_lua("require('custom.python.notebook').run()")
    wait_output("long-cell-output")
    n.exec_lua("require('custom.python.output').enter()")
    assert n.current.window.handle != source_win, (
        n.exec_lua("return _G.output_messages"),
        n.current.window.cursor,
        n.funcs.winsaveview(),
    )
    assert "long-cell-output" in "\n".join(n.current.buffer[:])
    n.input("q")
    wait(lambda: n.current.window.handle == source_win)
    assert n.exec_lua("return #vim.fn.MoltenRunningKernels(true)") == 1
    n.command("botright 2split")
    tiny = n.current.window.handle
    n.exec_lua("require('custom.python.output').enter()")
    assert n.current.window.handle == tiny
    assert any(
        "Enlarge this split" in msg for msg in n.exec_lua("return _G.output_messages")
    )
    n.command("close")
    n.command("MoltenDeinit")
    print(
        "PASS: one-press entry, full 100-line output, dimensions, scrolling, wrapping, q/Esc, snapshot split/cleanup, source preservation, off-screen recovery, tiny-window fallback"
    )
finally:
    try:
        n.command("qa!")
    except (EOFError, OSError):
        pass
    n.close()
