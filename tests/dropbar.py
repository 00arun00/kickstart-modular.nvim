"""Exercise breadcrumb sources, notebook menus, fuzzy search, and split isolation."""

import faulthandler
import tempfile
import time
from pathlib import Path

import nbformat
import pynvim

faulthandler.dump_traceback_later(60)

with tempfile.TemporaryDirectory(prefix="nvim-dropbar-") as directory:
    root = Path(directory).resolve()
    path = root / "navigation.ipynb"
    nb = nbformat.v4.new_notebook(
        cells=[
            nbformat.v4.new_markdown_cell(
                "# Experiment\n\nA **rendered** introduction."
            ),
            nbformat.v4.new_code_cell(
                "class Model:\n    def forward(self, x: int) -> int:\n        return x + 1"
            ),
            nbformat.v4.new_markdown_cell("## Results\n\nCompare the output."),
            nbformat.v4.new_raw_cell("Reference notes"),
        ]
    )
    nbformat.write(nb, path)
    n = pynvim.attach(
        "child", argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", str(path)]
    )
    try:
        n.ui_attach(140, 55, rgb=True)

        def wait(check, stage):
            print(f"STAGE: {stage}", flush=True)
            until = time.monotonic() + 10
            mode = None
            while time.monotonic() < until:
                # This API is fast: it still responds when getchar()/a partial
                # Normal-mode command prevents ordinary RPC requests running.
                mode = n.api.get_mode()
                if not mode["blocking"] and check():
                    return
                time.sleep(0.05)
            details = (
                n.exec_lua("""
                return {win = vim.api.nvim_get_current_win(),
                    filetype = vim.bo.filetype, buffer = vim.api.nvim_buf_get_name(0)}
            """)
                if not mode["blocking"]
                else {}
            )
            raise AssertionError(
                f"Stage timed out: {stage}; Neovim mode={mode}; focus={details}; "
                f"messages={n.command_output('messages') if not mode['blocking'] else '<blocked>'}"
            )

        def close_menu():
            # Check focus and execute the actual buffer-local q mapping in one
            # editor call, without a queued key racing focus/refresh events.
            n.exec_lua("""
                assert(require('dropbar.utils').menu.get_current(), 'No focused menu')
                local mapping = vim.fn.maparg('q', 'n', false, true)
                assert(mapping.buffer == 1, 'Missing menu-local q mapping')
                vim.api.nvim_feedkeys('q', 'mx', false)
            """)
            wait(lambda: not menu(), "close keyboard picker")

        def bar(win=None):
            return n.exec_lua(
                "local w=...; local b=require('dropbar.utils').bar.get({win=w or vim.api.nvim_get_current_win()}); if not b then return {} end; local t={}; for _,s in ipairs(b.components) do table.insert(t,s._.opts.name or s.name) end return t",
                win or n.current.window.handle,
            )

        def menu():
            return n.exec_lua(
                "return _G.dropbar.menus ~= nil and require('dropbar.utils').menu.get_current() ~= nil"
            )

        wait(
            lambda: n.current.buffer.options["filetype"] == "python" and len(bar()) > 0,
            "notebook breadcrumbs ready",
        )
        source = n.current.buffer[:]
        code = next(i for i, s in enumerate(source, 1) if "return x" in s)
        notes = next(i for i, s in enumerate(source, 1) if s == "# ## Results")
        n.current.window.cursor = (code, 8)
        wait(lambda: any("forward" in s for s in bar()), "Python scope visible")
        labels = bar()
        assert any("02 Code" in s for s in labels), labels
        assert any("Model" in s for s in labels), labels
        firstwin = n.current.window.handle
        n.command("vsplit")
        secondwin = n.current.window.handle
        n.command("vertical resize 46")
        n.current.window.cursor = (notes, 0)
        wait(
            lambda: any("03 Markdown" in s and "Results" in s for s in bar()),
            "split context refreshed",
        )
        labels = bar()
        assert any("03 Markdown" in s and "Results" in s for s in labels), labels
        assert not any("forward" in s for s in labels), labels
        assert any("02 Code" in s for s in bar(firstwin)), bar(firstwin)
        assert any("03 Markdown" in s for s in bar(secondwin)), bar(secondwin)
        # Jump to current cell start through the normal breadcrumb API.
        n.exec_lua("require('dropbar.api').goto_context_start()")
        assert n.current.window.cursor[0] == notes - 1
        n.current.window.cursor = (1, 0)  # all-cells menu also works from metadata
        n.exec_lua("require('custom.navigation.notebook').pick_cells()")
        wait(menu, "notebook cell menu focused")
        assert (
            n.exec_lua("return #require('dropbar.utils').menu.get_current().entries")
            == 4
        )
        n.input("/")
        wait(
            lambda: n.exec_lua(
                "local m=require('dropbar.utils').menu.get_current(); return m and m.fzf_state ~= nil"
            ),
            "fuzzy search ready",
        )
        n.input("Results")
        wait(
            lambda: n.exec_lua("""
            local m = require('dropbar.utils').menu.get_current()
            return m and #m.entries == 1
                and vim.api.nvim_buf_get_lines(m.buf, 0, -1, false)[1]:find('Results', 1, true) ~= nil
        """),
            "fuzzy results filtered",
        )
        n.input("<CR>")
        wait(
            lambda: n.current.buffer.name == str(path) and not menu(),
            "fuzzy selection returns to notebook",
        )
        assert n.current.window.cursor[0] == notes - 1, n.current.window.cursor
        # The advertised keyboard picker opens a path menu and returns cleanly.
        bar()
        # Select the notebook path itself, not an arbitrary ancestor of the
        # host's temporary directory (whose contents vary between machines).
        n.exec_lua("""
            local bar = require('dropbar.utils').bar.get_current()
            local index = 0
            local pivot
            for _, component in ipairs(bar.components) do
                if component.on_click then
                    index = index + 1
                    if (component._.opts.name or component.name) == 'navigation.ipynb' then
                        pivot = require('dropbar.configs').opts.bar.pick.pivots:sub(index, index)
                        break
                    end
                end
            end
            assert(pivot and pivot ~= '', 'Notebook path has no keyboard pivot')
            assert(vim.fn.maparg(' ;', 'n') ~= '', 'Missing breadcrumb picker mapping')
            -- Reproduce a refresh already queued when the user opens the menu.
            -- A later timer proves the debounce has elapsed before we inspect it.
            bar:update()
            refresh_elapsed = false
            vim.defer_fn(function() refresh_elapsed = true end,
                require('dropbar.configs').opts.bar.update_debounce + 20)
            -- Open through the real mapping before the queued refresh can run.
            -- Supply its getchar() response in the same editor call.
            vim.api.nvim_feedkeys(' ;' .. pivot, 'mx', false)
        """)
        wait(menu, "keyboard path menu focused")
        wait(
            lambda: n.exec_lua("return refresh_elapsed"),
            "pending breadcrumb refresh elapsed",
        )
        assert menu(), "pending breadcrumb refresh closed the active menu"
        # An edit while the menu is open must be reflected after dismissal.
        source_buf = n.exec_lua(
            "return require('dropbar.utils').menu.get_current():root().prev_buf"
        )
        n.api.buf_set_lines(
            source_buf, notes - 1, notes, False, ["# ## Updated results"]
        )
        n.exec_lua("""
            local menu = require('dropbar.utils').menu.get_current():root()
            require('dropbar.utils').bar.get({win = menu.prev_win}):_update()
        """)
        assert menu(), "source edit closed the active menu"
        # A menu in one split must not freeze breadcrumbs in another split.
        n.api.win_set_cursor(firstwin, [notes, 0])
        # This inactive window did not receive a user CursorMoved event.
        # Request its normal debounced update explicitly; observation stays pure.
        n.exec_lua("require('dropbar.utils').bar.get({win = ...}):update()", firstwin)
        wait(
            lambda: any("Updated results" in label for label in bar(firstwin)),
            "other split refreshed",
        )
        assert menu(), "refreshing another split closed the active menu"
        close_menu()
        assert n.current.window.handle == secondwin
        wait(
            lambda: n.exec_lua("""
            local bar = require('dropbar.utils').bar.get_current()
            for _, component in ipairs(bar.components) do
                if (component._.opts.name or component.name):find('Updated results', 1, true) then
                    return true
                end
            end
            return false
        """),
            "deferred breadcrumb refresh after dismissal",
        )
        n.current.buffer[:] = source
        n.command("write")
        saved = nbformat.read(path, as_version=4)
        assert [(c.cell_type, c.source) for c in saved.cells] == [
            (c.cell_type, c.source) for c in nb.cells
        ]
        # Plain Markdown uses heading hierarchy, not notebook parsing.
        md = root / "notes.md"
        md.write_text("# Main\n\n## Detail\n\nText\n")
        n.command("edit " + str(md))
        n.current.window.cursor = (5, 0)
        wait(lambda: any("Detail" in s for s in bar()), "Markdown headings visible")
        assert any("Main" in s for s in bar()), bar()
        # Plain Python fallback works with its Tree-sitter parser even before LSP.
        py = root / "model.py"
        py.write_text("class Plain:\n    def method(self):\n        return 1\n")
        n.command("edit " + str(py))
        n.current.window.cursor = (3, 8)
        wait(lambda: any("method" in s for s in bar()), "plain Python scope visible")
        # Enter selects the named scope; l opens its child submenu.
        labels = bar()
        class_index = next(i for i, s in enumerate(labels, 1) if "Plain" in s)
        n.exec_lua("require('dropbar.api').pick(...)", class_index)
        wait(menu, "Python scope menu focused")
        n.input("l")
        wait(
            lambda: n.exec_lua(
                "local m=require('dropbar.utils').menu.get_current(); return m and m.prev_menu ~= nil"
            ),
            "Python child submenu focused",
        )
        n.input("<CR>")
        wait(lambda: not menu(), "submenu selection returns to source")
        assert n.current.buffer.name == str(py)
        assert n.current.window.cursor[0] == 2, (
            n.current.window.cursor,
            labels,
            n.command_output("messages"),
        )
        floatwin = n.api.open_win(
            n.current.buffer,
            False,
            {
                "relative": "editor",
                "row": 2,
                "col": 2,
                "width": 30,
                "height": 5,
                "style": "minimal",
            },
        )
        assert not n.exec_lua(
            "return require('dropbar.configs').opts.bar.enable(vim.api.nvim_get_current_buf(),...)",
            floatwin.handle,
        )
        n.api.win_close(floatwin, True)
        # A nofile output split and a floating source window must be excluded.
        scratch = n.api.create_buf(False, True)
        n.api.win_set_buf(0, scratch)
        assert not n.exec_lua(
            "return require('dropbar.configs').opts.bar.enable(vim.api.nvim_get_current_buf(),vim.api.nvim_get_current_win())"
        )
        assert n.current.window.options["winbar"] == "", n.current.window.options[
            "winbar"
        ]
        print(
            "PASS: Python scopes, Markdown headings, notebook types/titles, split independence, cell menu, fuzzy jump, cache invalidation, unchanged save and scratch exclusion"
        )
    finally:
        try:
            n.input("<Esc>")
            n.command("qa!", async_=True)
        except (EOFError, OSError):
            pass
        n.close()
