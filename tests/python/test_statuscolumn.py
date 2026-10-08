"""Independent gutter contracts using real Neovim and the installed plugins."""

import warnings

import pynvim
import pytest

pytestmark = [pytest.mark.integration, pytest.mark.python]


@pytest.fixture
def nvim(tmp_path, monkeypatch, pytestconfig):
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "cache"))
    # pynvim's child transport still uses this deprecated asyncio API on 3.12.
    # Limit suppression to that exact warning during attachment, not the tests.
    with warnings.catch_warnings():
        warnings.filterwarnings(
            "ignore",
            message=r"'get_child_watcher' is deprecated as of Python 3\.12 and will be removed in Python 3\.14\.",
            category=DeprecationWarning,
            module=r"asyncio\.events",
        )
        n = pynvim.attach(
            "child", argv=["nvim", "--embed", "--clean", "-n", "-i", "NONE"]
        )
    try:
        n.ui_attach(100, 25, rgb=True)
        n.exec_lua(
            """
          vim.opt.rtp:prepend(...)
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
        """,
            str(pytestconfig.rootpath),
        )

        yield n
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()


def rendered(n, line=1):
    n.command("redraw!")
    return n.exec_lua(
        """
        return vim.api.nvim_eval_statusline(vim.wo.statuscolumn,
            {use_statuscol_lnum = ...}).str
    """,
        line,
    )


@pytest.fixture
def signed_gutter(nvim):
    n = nvim
    baseline = rendered(n)
    assert baseline.strip() == "1"
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
    return n, baseline


def test_indicator_order_and_scroll_stability(signed_gutter):
    n, baseline = signed_gutter
    assert rendered(n, 2).startswith("b+vE")
    assert rendered(n, 2)[4:].strip() == "1", "relative number"
    assert rendered(n)[4:].strip() == "1", "current absolute number"
    n.command("normal! zM")
    assert rendered(n, 2).startswith("b+>E")
    n.command("normal! zR")
    assert len(rendered(n)) == len(baseline) + 4
    n.command("normal! 90Gzt")
    assert len(rendered(n, 90)) == len(baseline) + 4, (
        "offscreen signs lost their columns"
    )
    assert rendered(n, 90)[4:].strip() == "90"
    assert rendered(n, 91)[4:].strip() == "1"


def test_breakpoint_priority_and_fallback(signed_gutter):
    n, _ = signed_gutter
    n.exec_lua("""
        require('dap')
        vim.fn.sign_define('DapBreakpoint', {text = 'B', texthl = 'ErrorMsg'})
        require('dap.breakpoints').set({}, vim.api.nvim_get_current_buf(), 2)
        test_ns = vim.api.nvim_create_namespace('future-test-signs')
        vim.api.nvim_buf_set_extmark(0, test_ns, 1, 0,
            {sign_text = 'T', sign_hl_group = 'Special', priority = 5})
    """)
    assert rendered(n, 2).startswith("b+vB")
    n.exec_lua("require('dap.breakpoints').clear()")
    assert rendered(n, 2).startswith("b+vE")
    n.exec_lua("vim.diagnostic.reset(diagnostic_ns)")
    assert rendered(n, 2).startswith("b+vT")
    n.exec_lua("vim.api.nvim_buf_clear_namespace(0, test_ns, 0, -1)")
    assert rendered(n, 2).startswith("b+v")


def test_empty_columns_collapse_and_folds_restore(signed_gutter):
    n, baseline = signed_gutter
    n.exec_lua("vim.diagnostic.reset(diagnostic_ns)")
    assert len(rendered(n)) == len(baseline) + 3
    n.exec_lua("require('guttermarks').toggle()")
    assert len(rendered(n)) == len(baseline) + 2
    n.exec_lua("vim.api.nvim_buf_clear_namespace(0, git_ns, 0, -1)")
    assert len(rendered(n)) == len(baseline) + 1
    before = n.current.window.options["foldcolumn"]
    n.command("set nofoldenable")
    assert len(rendered(n)) == len(baseline)
    n.command("set foldenable")
    assert n.current.window.options["foldcolumn"] == before
    assert len(rendered(n)) == len(baseline) + 1
    n.command("normal! zE")
    assert len(rendered(n)) == len(baseline)


def test_native_fold_commands_restore_column(nvim):
    n = nvim
    baseline = rendered(n)
    n.command("2,4fold")
    n.command("normal! zR")
    n.command("normal! zi")
    assert not n.current.window.options["foldenable"]
    assert len(rendered(n)) == len(baseline), "zi left an empty fold column"
    n.command("normal! zi")
    assert n.current.window.options["foldenable"]
    assert len(rendered(n)) == len(baseline) + 1
    n.command("setlocal nofoldenable")
    n.command("normal! 2Gza")
    assert n.current.window.options["foldenable"]
    assert n.current.window.options["foldcolumn"] == "auto:1"
    assert rendered(n, 2).startswith(">")


@pytest.mark.parametrize("split", ["vsplit", "split", "tab split"])
@pytest.mark.parametrize("foldcolumn", ["auto:1", "auto:2", "0"])
def test_split_preserves_disabled_fold_column(nvim, split, foldcolumn):
    n = nvim
    n.command("2,4fold")
    n.command("normal! zR")
    n.command(f"setlocal foldcolumn={foldcolumn} nofoldenable")
    n.command(split)
    n.command("setlocal foldenable")
    assert n.current.window.options["foldcolumn"] == foldcolumn
    if foldcolumn != "0":
        assert rendered(n, 2).startswith("v")
    n.command("close")
    assert not n.current.window.options["foldenable"]
    assert n.current.window.options["foldcolumn"] == "0"
    n.command("setlocal foldenable")
    assert n.current.window.options["foldcolumn"] == foldcolumn


def test_empty_split_does_not_inherit_active_columns(signed_gutter):
    n, baseline = signed_gutter
    source = n.current.window.handle
    assert len(rendered(n)) == len(baseline) + 4
    n.command("vnew")
    assert n.current.window.options["statuscolumn"]
    assert len(rendered(n)) == len(baseline), "empty split inherited source columns"
    n.command("close")
    assert n.current.window.handle == source
    assert rendered(n, 2).startswith("b+vE"), "source columns changed"


def test_float_excludes_an_ordinary_editing_buffer(signed_gutter):
    n, _ = signed_gutter
    source = n.current.window.handle
    buf = n.current.buffer
    assert buf.options["buftype"] == ""
    n.api.open_win(
        buf,
        True,
        {
            "relative": "editor",
            "row": 2,
            "col": 10,
            "width": 30,
            "height": 4,
        },
    )
    assert n.current.buffer == buf
    assert n.current.window.options["statuscolumn"] == ""
    n.command("close")
    assert n.current.window.handle == source
    assert rendered(n, 2).startswith("b+vE")


@pytest.mark.parametrize(
    "option,value",
    [
        ("buftype", "nofile"),
        ("filetype", "oil"),
        ("filetype", "neo-tree"),
        ("filetype", "help"),
        ("filetype", "lazy"),
        ("filetype", "mason"),
        ("filetype", "projecthome"),
    ],
)
def test_special_buffer_exclusion_and_restore(nvim, option, value):
    n = nvim
    original = n.current.buffer.options[option]
    n.current.buffer.options[option] = value
    assert n.current.window.options["statuscolumn"] == ""
    n.current.buffer.options[option] = original
    assert n.current.window.options["statuscolumn"]
