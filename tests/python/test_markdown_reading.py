"""Shared reading mode against an attached Neovim UI and real plugin controllers."""

import os
import warnings
from pathlib import Path

import pynvim
import pytest

pytestmark = [pytest.mark.integration, pytest.mark.python]


@pytest.fixture
def nvim(tmp_path, monkeypatch, pytestconfig, request):
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    data /= os.environ.get("NVIM_APPNAME", "nvim")
    for name in ("STATE", "CACHE", "DATA"):
        monkeypatch.setenv(f"XDG_{name}_HOME", str(tmp_path / name.lower()))
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message=".*get_child_watcher.*", category=DeprecationWarning)
        n = pynvim.attach("child", argv=["nvim", "--embed", "-u", "NONE", "-n", "-i", "NONE"])
    try:
        n.ui_attach(120, 48, rgb=True)
        n.exec_lua(
            "local root,data,source=...; assert(loadfile(root..'/tests/support/markdown_reading.lua'))(root,data,source)",
            str(pytestconfig.rootpath),
            str(data),
            getattr(request, "param", None),
        )
        # Tables now instantiate placements only in view. Bring the fixture's
        # first table into view rather than assuming off-screen rendering.
        first_table = next(i + 1 for i, line in enumerate(n.current.buffer) if line.startswith("|"))
        n.current.window.cursor = (max(1, first_table - 1), 0)
        n.command("normal! zt")
        n.exec_lua("require('render-markdown').render{buf=vim.api.nvim_get_current_buf()}")
        wait(n, "reading_fixture.table_rendered()")
        yield n
    finally:
        try:
            n.command("qa!")
        except EOFError:
            pass
        n.close()


def wait(n, expression):
    assert n.exec_lua(f"return vim.wait(5000, function() return {expression} end)"), expression


def move(n, line):
    n.current.window.cursor = (line, 0)
    n.exec_lua("vim.api.nvim_exec_autocmds('CursorMoved',{buffer=vim.api.nvim_get_current_buf()})")


def test_normal_navigation_insert_and_escape(nvim):
    n = nvim
    move(n, 7)
    wait(n, "reading_fixture.table_rendered()")
    n.command("normal! k")
    wait(n, "reading_fixture.table_rendered()")
    n.input("i")
    wait(n, "vim.fn.mode()=='i' and not reading_fixture.table_rendered()")
    n.input("\x1b")
    wait(n, "vim.fn.mode()=='n' and reading_fixture.table_rendered()")
    n.input("R")
    wait(n, "vim.fn.mode()=='R' and not reading_fixture.table_rendered()")
    n.input("\x1b")
    wait(n, "vim.fn.mode()=='n' and reading_fixture.table_rendered()")
    for line, kind in ((10, "math"), (14, "chart")):
        move(n, line)
        wait(n, f"reading_fixture.image_hidden('{kind}')==false")
        n.input("i")
        wait(n, f"vim.fn.mode()=='i' and reading_fixture.image_hidden('{kind}')==true")
        n.input("\x1b")
        wait(n, f"vim.fn.mode()=='n' and reading_fixture.image_hidden('{kind}')==false")
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_toggle_restores_cursor_reveal(nvim):
    n = nvim
    move(n, 7)
    n.input(" Tr")
    wait(n, "not require('custom.markdown_reading').is_enabled() and not reading_fixture.table_rendered()")
    move(n, 10)
    wait(n, "reading_fixture.image_hidden('math')==true")
    move(n, 14)
    wait(n, "reading_fixture.image_hidden('chart')==true")
    n.input(" Tr")
    wait(n, "require('custom.markdown_reading').is_enabled() and reading_fixture.image_hidden('chart')==false")
    move(n, 7)
    wait(n, "reading_fixture.table_rendered()")
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_image_finishing_after_insert_reveals_source(nvim):
    n = nvim
    move(n, 10)
    n.exec_lua("""
      hold_reading_images=true
      vim.api.nvim_buf_set_lines(0,9,10,false,{'d/e=f'})
      reading_fixture.controller:update()
    """)
    wait(n, "(function() for _,p in pairs(reading_fixture.controller.imgs) do if p.opts.type=='math' and p.img.pending then return true end end return false end)()")
    n.input("i")
    wait(n, "vim.fn.mode()=='i'")
    n.exec_lua("""
      hold_reading_images=false
      for _,img in pairs(reading_fixture.images) do
        if img.pending then
          img.pending=false
          for _,p in pairs(img.placements) do p:update() end
        end
      end
    """)
    wait(n, "reading_fixture.image_hidden('math')==true")
    n.input("\x1b")
    wait(n, "vim.fn.mode()=='n' and reading_fixture.image_hidden('math')==false")


def test_editing_mode_in_a_split_restores_source_reveal(nvim):
    n = nvim
    n.command("vsplit")
    assert n.current.window.options["concealcursor"] == "nvc"
    move(n, 14)
    n.input(" Tr")
    wait(n, "not require('custom.markdown_reading').is_enabled() and reading_fixture.image_hidden('chart')==true")
    assert n.current.window.options["concealcursor"] == ""
    n.input(" Tr")
    wait(n, "require('custom.markdown_reading').is_enabled() and reading_fixture.image_hidden('chart')==false")
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_reading_controls_diagnostics_lists_and_single_indicator(nvim):
    n = nvim
    n.exec_lua("""
      vim.diagnostic.config({virtual_text=true,signs={text={[1]='D'}}})
      reading_fixture.diag_ns=vim.api.nvim_create_namespace('reading-diagnostics')
      vim.diagnostic.set(reading_fixture.diag_ns,0,{{lnum=2,col=0,message='fixture diagnostic',severity=1}})
      function reading_fixture.diagnostics_drawn()
        for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,-1,0,-1,{details=true})) do
          if m[4].sign_text and m[4].sign_text:match('^D') then return true end
        end
        return false
      end
      function reading_fixture.jump_float_count()
        local original,count=vim.diagnostic.open_float,0
        vim.diagnostic.open_float=function() count=count+1 end
        vim.diagnostic.config().jump.on_jump(nil,vim.api.nvim_get_current_buf())
        vim.diagnostic.open_float=original
        return count
      end
    """)
    assert "  on" in n.exec_lua("return reading_fixture.status()")
    assert "" not in n.exec_lua("return reading_fixture.status()")
    assert n.exec_lua("return vim.fn.maparg(' Td','n')") == ""
    assert not n.exec_lua("return vim.diagnostic.is_enabled({bufnr=0})")
    assert not n.exec_lua("return reading_fixture.diagnostics_drawn()")
    assert n.exec_lua("return reading_fixture.jump_float_count()") == 0
    assert n.exec_lua("return #vim.diagnostic.get(0)") == 1
    n.exec_lua("""
      vim.diagnostic.set(reading_fixture.diag_ns,0,{{lnum=2,col=0,message='updated while reading',severity=1}})
      vim.diagnostic.setqflist({open=false})
      vim.diagnostic.setloclist({open=false})
    """)
    assert not n.exec_lua("return reading_fixture.diagnostics_drawn()")
    assert n.funcs.getqflist()[0]["text"] == "updated while reading"
    assert n.funcs.getloclist(0)[0]["text"] == "updated while reading"
    n.input(" Tr")
    wait(n, "vim.diagnostic.is_enabled({bufnr=0}) and reading_fixture.diagnostics_drawn()")
    assert "  off" in n.exec_lua("return reading_fixture.status()")
    assert "" not in n.exec_lua("return reading_fixture.status()")
    assert n.exec_lua("return reading_fixture.jump_float_count()") == 1
    n.input(" Tr")
    wait(n, "require('custom.markdown_reading').is_enabled() and not reading_fixture.diagnostics_drawn()")
    assert not n.exec_lua("return vim.diagnostic.is_enabled({bufnr=0})")
    n.input(" Tr")
    wait(n, "vim.diagnostic.is_enabled({bufnr=0}) and reading_fixture.diagnostics_drawn()")
    assert n.exec_lua("return vim.fn.maparg(' Td','n')") == ""
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_new_buffers_scope_window_restore_and_scratch_footer(nvim):
    n = nvim
    original = n.current.buffer.number
    n.command("enew")
    n.current.buffer.options["filetype"] = "markdown"
    assert n.exec_lua("return vim.fn.maparg(' Tr','n',false,true).buffer") == 1
    assert "  on" in n.exec_lua("return reading_fixture.status()")
    assert n.exec_lua("return vim.fn.maparg(' Td','n')") == ""
    second = n.current.buffer.number
    n.input(" Tr")
    wait(n, "not require('custom.markdown_reading').is_enabled()")
    assert n.exec_lua("local a,b=...; return vim.diagnostic.is_enabled({bufnr=a}) and vim.diagnostic.is_enabled({bufnr=b})", original, second)
    n.input(" Tr")
    wait(n, "require('custom.markdown_reading').is_enabled()")
    assert not n.exec_lua("return vim.diagnostic.is_enabled({bufnr=0})")
    n.command("enew")
    n.current.buffer.options["filetype"] = "python"
    assert n.exec_lua("return vim.fn.maparg(' Tr','n')") == ""
    assert n.exec_lua("return vim.diagnostic.is_enabled({bufnr=0})")
    assert "" not in n.exec_lua("return reading_fixture.status()")
    assert n.current.window.options["concealcursor"] == ""
    n.current.buffer = n.buffers[original]
    n.exec_lua("require('custom.navigation.scratch').toggle('global')")
    footer = "".join(chunk[0] for chunk in n.api.win_get_config(0)["footer"])
    assert "  on" in footer and "" not in footer
    n.input(" Tr")
    wait(n, "not require('custom.markdown_reading').is_enabled()")
    footer = "".join(chunk[0] for chunk in n.api.win_get_config(0)["footer"])
    assert "  off" in footer and "" not in footer


# A short source table expands into a tall image/text layout near the viewport
# boundary. This is the shape that trapped upward movement with scrolloff=10.
TABLE_SOURCE = (
    [f"Prose before {i}" for i in range(45)]
    + [
        "| Branch | Quantity $p$ | Governing equation |",
        "| --- | --- | --- |",
        "| **Mass** | Density $r$ | **Continuity**<br>$$a/b=c$$ |",
        "| **Momentum** | Momentum $rv$ | **Navier Stokes**<br>$$rv=f$$ |",
        "| **Energy** | Energy $e$ | **Energy equation**<br>$$e=q+s$$ |",
    ]
    + [""]
    + [f"Prose after {i}" for i in range(65)]
)


def press(n, keys):
    n.input(keys)
    # Exercise native scrolling/cursor correction before checking positions.
    n.command("redraw")


@pytest.mark.parametrize("nvim", [TABLE_SOURCE], indirect=True)
def test_table_native_motions_counts_arrows_and_operators(nvim):
    n = nvim
    n.current.window.options["scrolloff"] = 10
    move(n, 45)
    for keys, target in [("j", 46), ("5j", 51), ("2k", 49), ("<Down>", 50), ("<Up>", 49), ("3k", 46)]:
        press(n, keys)
        assert n.current.window.cursor[0] == target
        assert n.exec_lua("return reading_fixture.table_rendered()")
    # Operators and Visual mode use the same source-line units as navigation.
    press(n, "48G")
    press(n, "yj")
    assert n.funcs.getreg('"').splitlines() == TABLE_SOURCE[47:49]
    press(n, "Vj")
    assert n.exec_lua("return math.abs(vim.fn.line('.')-vim.fn.line('v'))") == 1
    n.input("<Esc>")
    n.command("redraw")
    for key in ["j", "k", "<Up>", "<Down>", "<C-e>", "<C-y>"]:
        assert n.exec_lua("return vim.fn.maparg(...,'n')", key) == ""
    assert n.current.window.options["scrolloff"] == 10
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize("nvim", [TABLE_SOURCE], indirect=True)
def test_table_upward_navigation_resize_edit_and_reading_off(nvim):
    n = nvim
    n.ui_try_resize(120, 40)
    n.current.window.options["scrolloff"] = 10
    n.current.window.options["relativenumber"] = True
    move(n, 90)
    n.command("normal! zt")
    for target in range(89, 39, -1):
        press(n, "k")
        assert n.current.window.cursor[0] == target
    press(n, "49G")
    n.ui_try_resize(80, 32)
    n.exec_lua("require('render-markdown').render{buf=vim.api.nvim_get_current_buf()}")
    wait(n, "reading_fixture.table_rendered()")
    assert n.current.window.cursor[0] == 49
    n.input("i")
    wait(n, "vim.fn.mode()=='i' and not reading_fixture.table_rendered()")
    assert "Momentum" in n.current.line
    n.input("<Esc>")
    wait(n, "vim.fn.mode()=='n' and reading_fixture.table_rendered()")
    n.input(" Tr")
    wait(n, "not require('custom.markdown_reading').is_enabled()")
    move(n, 90)
    n.command("normal! zt")
    for target in range(89, 34, -1):
        press(n, "k")
        assert n.current.window.cursor[0] == target
    assert n.current.window.options["scrolloff"] == 10
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize("nvim", [TABLE_SOURCE], indirect=True)
def test_table_native_scrolling_preserves_rendering(nvim):
    n = nvim
    n.ui_try_resize(120, 24)
    n.current.window.options["scrolloff"] = 0
    press(n, "48G")
    n.command("normal! zz")
    before = n.exec_lua("return vim.fn.winsaveview()")
    press(n, "<C-e>")
    after = n.exec_lua("return vim.fn.winsaveview()")
    assert (after["topline"], after["topfill"], after["skipcol"]) != (before["topline"], before["topfill"], before["skipcol"])
    press(n, "<C-y>")
    restored = n.exec_lua("return vim.fn.winsaveview()")
    assert (restored["topline"], restored["topfill"], restored["skipcol"]) == (before["topline"], before["topfill"], before["skipcol"])
    assert n.exec_lua("return reading_fixture.table_rendered()")
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize("nvim", [TABLE_SOURCE[45:50]], indirect=True)
def test_table_native_motions_at_buffer_boundaries(nvim):
    n = nvim
    press(n, "1G999j")
    assert n.current.window.cursor[0] == 5
    press(n, "yy")
    assert n.funcs.getreg('"').rstrip("\n") == TABLE_SOURCE[49]
    press(n, "999k")
    assert n.current.window.cursor[0] == 1
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize("nvim", [TABLE_SOURCE], indirect=True)
def test_table_native_positions_across_splits(nvim):
    n = nvim
    press(n, "48G")
    first_win = n.current.window
    n.command("split")
    press(n, "j")
    assert n.current.window.cursor[0] == 49
    n.current.window = first_win
    n.command("redraw")
    assert n.current.window.cursor[0] == 48
    assert n.exec_lua("return reading_fixture.table_rendered()")
    n.current.buffer.options["filetype"] = "text"
    assert n.exec_lua("return vim.fn.maparg('j','n')") == ""


@pytest.mark.parametrize("nvim", [TABLE_SOURCE, ["Prefix", ""] * 7 + TABLE_SOURCE], indirect=True)
def test_table_source_jumps_search_and_editing(nvim):
    n = nvim
    lines = list(n.current.buffer)
    first = next(i + 1 for i, line in enumerate(lines) if line.startswith("| Branch"))
    for offset, label in enumerate(["Branch", "─", "Mass", "Momentum", "Energy"]):
        target = first + offset
        press(n, f"{target}G")
        assert n.current.window.cursor[0] == target
        assert n.exec_lua("""
          local target,label=...
          for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,require('render-markdown.core.ui').ns,0,-1,{details=true})) do
            if m[2]==target-1 and m[4].conceal=='' then
              local text={} for _,chunk in ipairs(m[4].virt_text) do text[#text+1]=chunk[1] end
              return table.concat(text):find(label,1,true)~=nil
            end
          end
          return false
        """, target, label)
    press(n, f"{first - 1}G")
    press(n, "/Momentum<CR>")
    assert n.current.window.cursor[0] == first + 3
    n.input("i")
    wait(n, "vim.fn.mode()=='i' and not reading_fixture.table_rendered()")
    assert n.current.window.cursor[0] == first + 3
    assert "Momentum" in n.current.line
    n.input("<Esc>")
    wait(n, "vim.fn.mode()=='n' and reading_fixture.table_rendered()")
    press(n, f"{first - 1}G")
    for target in range(first, first + 6):
        press(n, "j")
        assert n.current.window.cursor[0] == target
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize("nvim", [["| Header $x$ |", "| --- |"]], indirect=True)
def test_header_only_math_table(nvim):
    n = nvim
    press(n, "2G")
    assert n.current.window.cursor[0] == 2
    press(n, "k")
    assert n.current.window.cursor[0] == 1
    press(n, "j")
    assert n.current.window.cursor[0] == 2
    assert n.exec_lua("return reading_fixture.source_unchanged()")


@pytest.mark.parametrize(
    "nvim",
    [["Intro", "", ""] + [line.ljust(360) for line in TABLE_SOURCE[45:50]] + ["", "After"]],
    indirect=True,
)
def test_wrapped_table_source_has_continuous_borders(nvim):
    n = nvim
    n.ui_try_resize(120, 90)
    n.current.window.options["wrap"] = True
    n.current.window.options["number"] = True
    n.current.window.options["relativenumber"] = True
    n.current.window.options["breakindent"] = True
    n.exec_lua("require('render-markdown').render{buf=vim.api.nvim_get_current_buf()}")
    wait(n, "reading_fixture.table_rendered()")

    def check_grid():
        n.command("redraw!")
        grid = n.exec_lua("""
          local info=vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
          local rows={}
          for r=1,info.height do
            local text=''
            for col=info.textoff+1,info.width do text=text..vim.fn.screenstring(r,col) end
            rows[#rows+1]=text
          end
          return rows
        """)
        first = next(i for i, row in enumerate(grid) if row.startswith("┌"))
        last = next(i for i, row in enumerate(grid) if row.startswith("└"))
        for row in grid[first : last + 1]:
            assert row[0] in "┌│├└", repr(row)
            assert row.rstrip()[-1] in "┐│┤┘", repr(row)
        # Continuation decoration must not repeat row labels or equations.
        for label in ["Branch", "Mass", "Momentum", "Energy equation"]:
            assert sum(label in row for row in grid) == 1

    check_grid()
    press(n, "3G")
    press(n, "3j")
    check_grid()
    n.ui_try_resize(100, 90)
    n.exec_lua("require('render-markdown').render{buf=vim.api.nvim_get_current_buf()}")
    wait(n, "reading_fixture.table_rendered()")
    check_grid()
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def setup_math_theme_test(n):
    n.exec_lua("""
      local plugins
      for _,path in ipairs(vim.api.nvim_list_runtime_paths())do
        if path:match('/catppuccin$')then plugins=vim.fs.dirname(path) end
      end
      for _,name in ipairs{'rose-pine','tokyonight.nvim','onedarkpro.nvim','neovim-ayu'}do
        vim.opt.rtp:append(plugins..'/'..name)
      end
      require('catppuccin').setup{}
      vim.api.nvim_create_autocmd('ColorScheme',{callback=require('custom.theme').apply_highlights})
      function reading_fixture.math_has_current_color()
        local color=Snacks.util.color('SnacksImageMath'):sub(2):upper()
        local count=0
        for src,img in pairs(reading_fixture.images)do
          if src:match('%.tex$') and not vim.tbl_isempty(img.placements)then
            count=count+1
            local tex=table.concat(vim.fn.readfile(src),'\\n')
            if not tex:find('\\\\color[HTML]{'..color..'}',1,true)then return false end
          end
        end
        return count>=2
      end
    """)


def test_math_color_follows_all_supported_theme_palettes(nvim):
    n = nvim
    setup_math_theme_test(n)
    themes = [
        ("catppuccin-latte", "light"), ("catppuccin-frappe", "dark"),
        ("catppuccin-macchiato", "dark"), ("catppuccin-mocha", "dark"),
        ("rose-pine-main", "dark"), ("rose-pine-moon", "dark"), ("rose-pine-dawn", "light"),
        ("onedark", "dark"), ("onelight", "light"), ("onedark_vivid", "dark"),
        ("onedark_dark", "dark"), ("vaporwave", "dark"),
        ("ayu-dark", "dark"), ("ayu-mirage", "dark"), ("ayu-light", "light"),
        ("tokyonight-night", "dark"), ("tokyonight-storm", "dark"),
        ("tokyonight-moon", "dark"), ("tokyonight-day", "light"),
    ]
    colors = set()
    for theme, background in themes:
        n.options["background"] = background
        n.command("colorscheme " + theme)
        wait(n, "reading_fixture.math_has_current_color()")
        color = n.exec_lua("return Snacks.util.color('SnacksImageMath')")
        assert color == n.exec_lua("return require('custom.theme').palette().teal").lower()
        assert color != n.exec_lua("return Snacks.util.color('Normal')")
        colors.add(color)
    assert len(colors) > 5
    assert n.exec_lua("return reading_fixture.source_unchanged()")


def test_theme_refresh_discards_old_async_math_and_queued_updates(nvim):
    n = nvim
    setup_math_theme_test(n)
    n.command("colorscheme catppuccin-mocha")
    wait(n, "reading_fixture.math_has_current_color()")
    wait(n, "(function() for _,p in pairs(reading_fixture.controller.imgs)do if p.opts.type=='chart' then return p._state~=nil end end return false end)()")
    n.exec_lua("""
      for _,p in pairs(reading_fixture.controller.imgs)do
        if p.opts.type=='math'then old_math=p elseif p.opts.type=='chart'then old_chart=p end
      end
      local find=Snacks.image.doc.find
      held_math={}
      hold_math=true
      Snacks.image.doc.find=function(buf,callback,opts)
        find(buf,function(items)
          if hold_math then held_math[#held_math+1]=function()callback(items)end else callback(items)end
        end,opts)
      end
      reading_fixture.controller:update()
    """)
    wait(n, "#held_math>0")
    n.exec_lua("hold_math=false")
    n.options["background"] = "light"
    n.command("colorscheme catppuccin-latte")
    wait(n, "reading_fixture.math_has_current_color()")
    # Deliver the old-theme parse AFTER the new-theme images have appeared.
    n.exec_lua("""
      for _,callback in ipairs(held_math)do callback()end
      Snacks.image.placement.update(old_math)
    """)
    assert n.exec_lua("return old_math.closed and not old_math:ready()")
    assert n.exec_lua("return reading_fixture.math_has_current_color()")
    assert n.exec_lua("return reading_fixture.controller.imgs[old_chart.id]==old_chart")
    assert n.exec_lua("return reading_fixture.source_unchanged()")
