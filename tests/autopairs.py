"""Exercise typed pairing with Blink and the notebook config loaded."""

import tempfile
import time
from pathlib import Path

import nbformat
import pynvim

with tempfile.TemporaryDirectory(prefix="nvim-autopairs-") as directory:
    root = Path(directory)
    notebook = root / "pairs.ipynb"
    nbformat.write(
        nbformat.v4.new_notebook(
            cells=[
                nbformat.v4.new_markdown_cell("Notes"),
                nbformat.v4.new_code_cell("pass"),
            ]
        ),
        notebook,
    )
    n = pynvim.attach(
        "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE"]
    )
    try:
        n.ui_attach(100, 45, rgb=True)

        def wait(check):
            until = time.monotonic() + 5
            while time.monotonic() < until:
                if check():
                    return
                time.sleep(0.02)
            raise AssertionError(
                ("input did not settle", n.current.buffer[:], n.funcs.mode())
            )

        for path in (root / "pairs.py", notebook):
            n.command("edit! " + str(path))
            wait(lambda: n.current.buffer.options["filetype"] == "python")
            source = n.current.buffer[:]
            prefix = source[:-1] if path == notebook else []
            # Trigger InsertEnter once so the lazy plugin mappings are ready.
            n.input("i")
            wait(lambda: n.funcs.mode() == "i")
            wait(lambda: n.exec_lua("return package.loaded['nvim-autopairs'] ~= nil"))
            n.input("\x1b")
            wait(lambda: n.funcs.mode() == "n")
            assert n.exec_lua("return require('nvim-autopairs').config.map_cr") is False
            cr = n.funcs.maparg("<CR>", "i", False, True)
            assert "autopairs" not in str(cr).lower(), cr
            assert n.current.buffer.options["indentexpr"] in (
                "python#GetIndent(v:lnum)",
                "GetPythonIndent(v:lnum)",
            )

            def check(typed, expected, initial="", prefix=prefix, path=path):
                n.current.buffer[:] = prefix + [initial]
                n.current.window.cursor = (len(prefix) + 1, max(0, len(initial) - 1))
                n.input("A" + typed + "\x1b")
                wait(lambda: n.funcs.mode() == "n" and n.current.buffer[-1] != initial)
                assert n.current.buffer[-1] == expected, (
                    path.suffix,
                    typed,
                    expected,
                    n.current.buffer[-1],
                )
                assert n.current.buffer[: len(prefix)] == prefix

            for opening, closing in [
                ("(", ")"),
                ("[", "]"),
                ("{", "}"),
                ('"', '"'),
                ("'", "'"),
            ]:
                check(opening, opening + closing)
                check(opening + closing, opening + closing)
                check(opening + "<BS>" + "x", "x")
            check("def foo(x: list[int]) -> str:", "def foo(x: list[int]) -> str:")
            check('f"{value}"', 'f"{value}"')
            # Triple delimiters are inserted automatically; move past them with End.
            check('"""docstring<End>', '"""docstring"""')
            check('"a\\"b"', '"a\\"b"')
            print(
                f"PASS {path.suffix}: pairs, closing skip, paired Backspace, annotations, f-strings, triple/escaped quotes; Enter untouched"
            )
            if path == notebook:
                prefix = source[: source.index("# Notes")]
                check("don't", "# don't", "# ", prefix=prefix)
                check("[label](url)", "# [label](url)", "# ", prefix=prefix)
                check("`value`", "# `value`", "# ", prefix=prefix)
                n.current.buffer[:] = source
                n.command("write")
                saved = nbformat.read(notebook, as_version=4)
                assert (
                    saved.cells[0].source == "Notes" and saved.cells[1].source == "pass"
                )
                print(
                    "PASS notebook Markdown: apostrophes, links, inline code and unchanged roundtrip"
                )
    finally:
        try:
            n.command("qa!")
        except (EOFError, OSError):
            pass
        n.close()
