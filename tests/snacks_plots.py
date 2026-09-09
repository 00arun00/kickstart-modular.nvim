"""Real Molten/Snacks graphics test in a PTY, optionally through isolated tmux.

Run with editor host Python and a disposable project after tests/plots.py.
PTY capture validates graphics transmission, not visual Ghostty appearance.
"""

import fcntl
import os
import pty
import shlex
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from pathlib import Path

import pynvim

project = Path(sys.argv[1]).resolve()
use_tmux = "--tmux" in sys.argv
with tempfile.TemporaryDirectory(prefix="snacks-plots-") as temp:
    socket = str(Path(temp) / "nvim.sock")
    tmux_socket = str(Path(temp) / "tmux.sock")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 160, 1600, 1200))
    env = os.environ.copy()
    env.update(
        TERM="xterm-256color",
        TERM_PROGRAM="ghostty",
        SNACKS_GHOSTTY="true",
        GHOSTTY_RESOURCES_DIR="/Applications/Ghostty.app/Contents/Resources/ghostty",
    )
    env.pop("TMUX", None)
    env.pop("TMUX_PANE", None)
    command = [
        "nvim",
        "-n",
        "-i",
        "NONE",
        "--listen",
        socket,
        str(project / "pde-plots.ipynb"),
    ]
    if use_tmux:
        command = [
            "tmux",
            "-S",
            tmux_socket,
            "-f",
            "/dev/null",
            "new-session",
            "-s",
            "plots",
            shlex.join(command),
        ]
    process = subprocess.Popen(
        command, stdin=slave, stdout=slave, stderr=slave, env=env
    )
    os.close(slave)
    output = bytearray()

    def read():
        try:
            while chunk := os.read(master, 65536):
                output.extend(chunk)
        except OSError:
            pass

    threading.Thread(target=read, daemon=True).start()
    n = None

    def wait(check, seconds=25):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(0.1)
        raise AssertionError(
            (
                n.command_output("messages"),
                n.exec_lua(
                    "local t = {}; for _, p in ipairs(_G.plot_placements or {}) do table.insert(t, {closed=p.closed, ready=p:ready(), valid=p:valid(), state=vim.inspect(p._state), pos=p.opts.pos, lines=vim.api.nvim_buf_is_valid(p.buf) and vim.api.nvim_buf_line_count(p.buf)}) end return t"
                ),
            )
            if n
            else repr(bytes(output))
        )

    try:
        wait(lambda: Path(socket).exists())
        n = pynvim.attach("socket", path=socket)
        time.sleep(3)
        n.input("\r")
        wait(lambda: n.vars.get("molten_image_provider") == "snacks.nvim")
        n.exec_lua("""
          _G.plot_placements = {}
          local original = Snacks.image.placement.new
          Snacks.image.placement.new = function(...)
            local p = original(...)
            table.insert(_G.plot_placements, p)
            return p
          end
        """)
        n.exec_lua("require('custom.python.notebook').init()")
        wait(
            lambda: n.exec_lua(
                "return next(require('custom.python.notebook').ready) ~= nil"
            )
        )
        row = next(
            i
            for i, line in enumerate(n.current.buffer[:], 1)
            if line.startswith("import matplotlib")
        )
        n.current.window.cursor = (row, 0)
        n.command("normal! zz")
        n.exec_lua("require('custom.python.notebook').run()")
        wait(lambda: n.exec_lua("return #_G.plot_placements > 0"))
        n.exec_lua("require('custom.python.output').preview()")
        wait(lambda: n.exec_lua("return #_G.plot_placements >= 2"))
        wait(
            lambda: n.exec_lua(
                "for _, p in ipairs(_G.plot_placements) do if p:ready() and p._state and p._state.loc then return true end end return false"
            )
        )
        wait(lambda: b"\x1b_G" in output)
        if use_tmux:
            assert b"\x1bPtmux;" not in output, (
                "tmux must unwrap passthrough for the terminal"
            )
            options = subprocess.check_output(
                ["tmux", "-S", tmux_socket, "show", "-p", "allow-passthrough"],
                text=True,
            )
            assert "all" in options, options
        n.exec_lua("require('custom.python.output').hide()")
        n.exec_lua("require('custom.python.output').preview()")
        n.exec_lua("require('custom.python.output').hide()")
        before = n.exec_lua("return #_G.plot_placements")
        n.exec_lua("require('custom.python.notebook').run()")
        wait(lambda: n.exec_lua("return #_G.plot_placements") > before)
        n.command("MoltenDeinit")
        wait(
            lambda: n.exec_lua(
                "for _, p in ipairs(_G.plot_placements) do if not p.closed then return false end end return true"
            )
        )
        print(
            "PASS: Molten → Snacks graphics, inline/float, hide/reopen, rerun, kernel cleanup"
            + (" through tmux" if use_tmux else " without tmux")
        )
    finally:
        if n:
            try:
                n.command("qa!")
            except (EOFError, OSError):
                pass
            n.close()
        if use_tmux:
            subprocess.run(
                ["tmux", "-S", tmux_socket, "kill-server"],
                capture_output=True,
                check=False,
            )
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=10)
        os.close(master)
