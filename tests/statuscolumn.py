"""Check rendered gutter ordering, buffer-wide sizing, collisions and window scope."""

import os
import tempfile

import pynvim


with tempfile.TemporaryDirectory(prefix="nvim-statuscolumn-") as directory:
    os.environ["XDG_STATE_HOME"] = directory
    n = pynvim.attach("child", argv=["nvim", "--embed", "--clean", "-n", "-i", "NONE"])
    try:
        n.ui_attach(100, 25, rgb=True)
        n.exec_lua("""
          vim.opt.rtp:prepend(vim.fn.getcwd())
          local plugins = vim.fn.stdpath('data') .. '/lazy/'
          vim.opt.rtp:append(vim.env.NVIM_STATUSCOL_DIR or plugins .. 'statuscol.nvim')
          vim.opt.rtp:append(plugins .. 'guttermarks.nvim')
          vim.opt.rtp:append(plugins .. 'nvim-dap')
          require('options')
          require('custom.plugins.statuscol')[1].config()
          require('guttermarks').setup(require('custom.plugins.guttermarks')[1].opts)
          vim.cmd('file statuscolumn-fixture.lua')
          vim.bo.filetype = 'lua'
          vim.wo.foldmethod = 'manual'
          vim.opt.fillchars = { foldopen = 'v', foldclose = '>', foldsep = ' ' }
          vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({'code'}, 100))
        """)

        def rendered(line=1):
            n.command("redraw!")
            return n.exec_lua("""
              return vim.api.nvim_eval_statusline(vim.wo.statuscolumn,
                {use_statuscol_lnum = ...}).str
            """, line)

        baseline = rendered()
        assert baseline.strip() == "1", baseline
        # Signs elsewhere in the buffer reserve exactly one cell each.
        n.exec_lua("""
          vim.api.nvim_buf_set_mark(0, 'b', 2, 0, {})
          require('guttermarks').refresh()
          git_ns = vim.api.nvim_create_namespace('gitsigns_signs_')
          vim.api.nvim_buf_set_extmark(0, git_ns, 1, 0,
            {sign_text = '+', sign_hl_group = 'DiffAdd', priority = 6})
          diagnostic_ns = vim.api.nvim_create_namespace('gutter-test-diagnostics')
          vim.diagnostic.config({virtual_text = false, severity_sort = true,
            signs = {priority = 10, text = {[vim.diagnostic.severity.ERROR] = 'E'}}})
          vim.diagnostic.set(diagnostic_ns, 0,
            {{lnum = 1, col = 0, message = 'fixture', severity = vim.diagnostic.severity.ERROR}})
        """)
        n.command("2,4fold")
        n.command("normal! zR")
        assert rendered(2).startswith("b+vE"), rendered(2)
        assert rendered(2).strip().endswith("1"), "relative numbers changed"
        n.command("normal! zM")
        assert rendered(2).startswith("b+>E"), rendered(2)
        n.command("normal! zR")
        assert len(rendered()) == len(baseline) + 4
        n.command("normal! 90Gzt")
        assert len(rendered(90)) == len(baseline) + 4, "columns moved when signs left viewport"
        n.command("normal! gg")
        # The real DAP sign priority must beat the diagnostic on the same line.
        n.exec_lua("""
          require('dap')
          vim.fn.sign_define('DapBreakpoint', {text = 'B', texthl = 'ErrorMsg'})
          require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 2)
        """)
        assert rendered(2).startswith("b+vB"), rendered(2)
        n.exec_lua("require('dap.breakpoints').clear()")
        assert rendered(2).startswith("b+vE"), rendered(2)
        n.exec_lua("vim.diagnostic.reset(diagnostic_ns)")
        assert rendered(2).startswith("b+v"), rendered(2)
        assert len(rendered()) == len(baseline) + 3
        # Unknown future test-sign namespaces land in the shared indicator slot.
        n.exec_lua("""
          test_ns = vim.api.nvim_create_namespace('future-test-signs')
          vim.api.nvim_buf_set_extmark(0, test_ns, 1, 0,
            {sign_text = 'T', sign_hl_group = 'Special', priority = 5})
        """)
        assert rendered(2).startswith("b+vT"), rendered(2)
        n.exec_lua("vim.api.nvim_buf_clear_namespace(0, test_ns, 0, -1)")
        n.exec_lua("require('guttermarks').toggle()")
        assert len(rendered()) == len(baseline) + 2
        n.exec_lua("vim.api.nvim_buf_clear_namespace(0, git_ns, 0, -1)")
        assert len(rendered()) == len(baseline) + 1
        n.command("set nofoldenable")
        assert len(rendered()) == len(baseline)
        n.command("set foldenable")
        assert len(rendered()) == len(baseline) + 1
        n.command("normal! zE")
        assert len(rendered()) == len(baseline)

        editor = n.current.window.handle
        n.exec_lua("""
          local buf = vim.api.nvim_create_buf(false, true)
          popup = vim.api.nvim_open_win(buf, true,
            {relative = 'editor', row = 2, col = 10, width = 30, height = 4})
        """)
        assert n.current.window.options["statuscolumn"] == "", "float got custom gutter"
        n.command("close")
        assert n.current.window.handle == editor
        n.command("vnew")
        assert n.current.window.options["statuscolumn"], "new editor missing gutter"
        assert len(rendered()) == len(baseline), "empty split inherited sign columns"
        n.command("setlocal buftype=nofile")
        assert n.current.window.options["statuscolumn"] == ""
        n.command("setlocal buftype=")
        assert n.current.window.options["statuscolumn"], "editor gutter not restored"
        n.command("setfiletype oil")
        assert n.current.window.options["statuscolumn"] == ""
        n.command("setfiletype lua")
        assert n.current.window.options["statuscolumn"]
        n.command("close")
        assert n.current.window.options["statuscolumn"]
        assert not n.command_output("messages").strip(), n.command_output("messages")
        print("PASS: gutter ordering, dynamic width, priority, scroll stability, and window isolation")
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()
