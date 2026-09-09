"""Notebook Markdown media integration; pass a disposable project, optionally --tmux.

Requires ImageMagick, tectonic and mmdc. PTY capture is not visual Ghostty QA.
"""

import base64
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

import nbformat
import pynvim
from PIL import Image

project = Path(sys.argv[1]).resolve()
use_tmux = "--tmux" in sys.argv
Image.new("RGB", (320, 160), "royalblue").save(project / "pde-md-image.png")
notebook = project / "pde-markdown-media.ipynb"
nbformat.write(
    nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_code_cell("value = 42"),
            nbformat.v4.new_markdown_cell(
                "# Image\n\n![sample](pde-md-image.png)\n\n![pasted](attachment:example.png)",
                attachments={
                    "example.png": {
                        "image/png": base64.b64encode(
                            (project / "pde-md-image.png").read_bytes()
                        ).decode()
                    }
                },
            ),
            nbformat.v4.new_markdown_cell("# Math\n\n$$x^2 + y^2 = z^2$$"),
            nbformat.v4.new_markdown_cell(
                "# Diagram\n\n```mermaid\ngraph LR\n  A --> B\n```"
            ),
        ]
    ),
    notebook,
)
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
        n.command("edit " + n.funcs.fnameescape(str(notebook)))
        wait(lambda: n.current.buffer.options["filetype"] == "python")
        n.current.window.cursor = (
            next(i for i, l in enumerate(n.current.buffer[:], 1) if l == "value = 42"),
            0,
        )
        n.exec_lua("require('custom.python.markdown').update()")
        wait(
            lambda: n.exec_lua(
                "local count=0; for _, p in ipairs(_G.plot_placements) do if not p.closed and p:ready() then count=count+1 end end return count >= 4"
            ),
            90,
        )
        wait(lambda: b"\x1b_G" in output)
        source = n.current.buffer[:]
        math_row = next(i for i, l in enumerate(source, 1) if l == "# # Math")
        n.current.window.cursor = (math_row, 0)
        n.exec_lua("require('custom.python.markdown').update()")
        wait(
            lambda: n.exec_lua(
                "local n=0; for _,p in ipairs(_G.plot_placements) do if not p.closed then n=n+1 end end return n==3"
            )
        )
        n.exec_lua("require('custom.python.markdown').toggle()")
        assert n.exec_lua(
            "for _,p in ipairs(_G.plot_placements) do if not p.closed then return false end end return true"
        )
        assert n.current.buffer[:] == source
        n.exec_lua("require('custom.python.markdown').toggle()")
        n.current.window.cursor = (
            next(i for i, l in enumerate(source, 1) if l == "value = 42"),
            0,
        )
        n.exec_lua("require('custom.python.markdown').update()")
        wait(
            lambda: n.exec_lua(
                "local n=0; for _,p in ipairs(_G.plot_placements) do if not p.closed and p:ready() then n=n+1 end end return n==4"
            )
        )
        n.command("bwipeout!")
        assert n.exec_lua(
            "for _,p in ipairs(_G.plot_placements) do if not p.closed then return false end end return true"
        )
        print(
            "PASS: notebook images, LaTeX and Mermaid through Snacks; active-cell reveal, toggle, source preservation and cleanup"
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
