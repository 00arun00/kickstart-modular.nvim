"""A confirmed choice is shared; previews never publish to terminal apps."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.integration, pytest.mark.lua]


def test_preview_is_local_and_other_sessions_pull_latest_choice(tmp_path):
    script = tmp_path / "theme-selection.lua"
    script.write_text("""
vim.go.loadplugins = true
vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)
local plugins = vim.env.THEME_TEST_PLUGINS
vim.opt.rtp:prepend(plugins .. '/lazy.nvim')
local published = {}
package.loaded['custom.theme_sync'] = { publish = function()
  published[#published + 1] = vim.g.colors_name
end }
-- Keep the real filesystem watcher, but capture its callback so the preview
-- regression can explicitly deliver an event before closing the picker.
local new_fs_event = vim.uv.new_fs_event
local selection_event
vim.uv.new_fs_event = function()
  local handle = new_fs_event()
  return {
    start = function(_, path, options, callback)
      selection_event = callback
      return handle:start(path, options, callback)
    end,
    stop = function() return handle:stop() end,
    close = function() return handle:close() end,
  }
end
require('lazy').setup(require 'custom.plugins.catppuccin', {
  root = plugins,
  lockfile = vim.env.THEME_TEST_ROOT .. '/lazy-lock.json',
  install = { missing = false }, checker = { enabled = false },
  change_detection = { enabled = false },
})
vim.uv.new_fs_event = new_fs_event
for _, name in ipairs { 'plenary.nvim', 'telescope.nvim' } do vim.opt.rtp:append(plugins .. '/' .. name) end
require('telescope').setup {}
local theme = require 'custom.theme'
local path = vim.fn.stdpath 'state' .. '/theme-choice'
theme.select('catppuccin-mocha')
assert(#published == 1)
assert(vim.fn.maparg('<leader>Tt', 'n') == '<Cmd>ThemePicker<CR>' or
  vim.fn.maparg('<leader>Tt', 'n') == '<cmd>ThemePicker<CR>')
vim.cmd 'ThemePicker'
local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
picker:set_prompt('rose-pine-dawn')
assert(vim.wait(2000, function()
  return picker:get_selection() and picker:get_selection().value == 'rose-pine-dawn'
    and vim.g.colors_name == 'rose-pine'
end, 10))
assert(#published == 1, 'preview published external changes')
assert(vim.fn.readfile(path)[1] == 'catppuccin-mocha')
require('telescope.actions').close(picker.prompt_bufnr)
assert(#published == 1 and vim.g.colors_name == 'catppuccin-mocha')
-- Simulate a selection saved by another Neovim instance.
vim.fn.writefile({ 'ayu-mirage' }, path)
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(vim.g.colors_name == 'ayu' and require('ayu.config').mirage)
assert(#published == 1, 'pulling a selection should not republish it')
-- Atomic replacement must update an idle instance without a focus event.
local function external_choice(name)
  local temporary = path .. '.external'
  vim.fn.writefile({ name }, temporary)
  assert(vim.uv.fs_rename(temporary, path))
end
external_choice('rose-pine-dawn')
assert(vim.wait(2000, function()
  return vim.g.colors_name == 'rose-pine' and vim.o.background == 'light'
end, 10), 'watcher did not adopt atomic replacement')
assert(#published == 1, 'watcher republished terminal colors')
-- A picker preview must survive incoming state, then reconcile on cancel.
theme.pick()
picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
external_choice('catppuccin-latte')
selection_event(nil, 'theme-choice')
-- The watcher schedules its handler first. This sentinel is queued after it,
-- so the assertion runs only after the application has handled the event.
local handled = false
vim.schedule(function() handled = true end)
assert(vim.wait(2000, function() return handled end, 10))
assert(vim.g.colors_name ~= 'catppuccin-latte', 'incoming choice interrupted picker')
require('telescope.actions').close(picker.prompt_bufnr)
assert(vim.g.colors_name == 'catppuccin-latte', 'cancel did not adopt latest shared choice')
assert(#published == 1)
-- Repeated setup replaces the watcher and still observes subsequent writes.
theme.setup()
external_choice('catppuccin-frappe')
assert(vim.wait(2000, function() return vim.g.colors_name == 'catppuccin-frappe' end, 10))
assert(#published == 1)
-- Reopening the picker also pulls the shared state without a focus event.
vim.fn.writefile({ 'tokyonight-day' }, path)
theme.pick()
picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
assert(vim.wait(2000, function() return picker:get_selection() and picker:get_selection().value == 'tokyonight-day' end, 10))
require('telescope.actions').select_default(picker.prompt_bufnr)
assert(#published == 2 and published[2] == 'tokyonight-day')
assert(vim.fn.readfile(path)[1] == 'tokyonight-day')
print('PASS: previews local; confirmation published; shared selection pulled')
vim.cmd 'qa!'
""")
    detected = subprocess.run(
        [
            "nvim",
            "--headless",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "--cmd",
            "lua io.stdout:write(vim.fn.stdpath('data')); vim.cmd('qa!')",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    plugins = Path(
        os.environ.get("NVIM_TEST_PLUGIN_ROOT", str(Path(detected.stdout) / "lazy"))
    )
    required = (
        "lazy.nvim",
        "telescope.nvim",
        "plenary.nvim",
        "catppuccin",
        "rose-pine",
        "tokyonight.nvim",
        "neovim-ayu",
        "onedarkpro.nvim",
    )
    missing = [name for name in required if not (plugins / name).is_dir()]
    if missing:
        pytest.skip(
            "Install theme plugins or set NVIM_TEST_PLUGIN_ROOT: " + ", ".join(missing)
        )
    env = dict(
        os.environ,
        THEME_TEST_ROOT=str(ROOT),
        THEME_TEST_PLUGINS=str(plugins),
        XDG_STATE_HOME=str(tmp_path / "state"),
        XDG_CACHE_HOME=str(tmp_path / "cache"),
        XDG_DATA_HOME=str(tmp_path / "data"),
    )
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-l", str(script)],
        env=env,
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS:" in result.stdout + result.stderr


def test_inactive_tmux_pane_redraws_after_another_instance_selects_theme(tmp_path):
    """SessionX's capture must see the new theme without focusing the pane."""
    import shlex
    import shutil
    import time
    import tempfile

    if not shutil.which("tmux"):
        pytest.skip("tmux is not installed")
    runtime = tmp_path / "runtime"
    (runtime / "colors").mkdir(parents=True)
    # Minimal colorschemes isolate theme synchronization from plugin behavior;
    # the test above exercises the installed theme plugins and picker.
    for name, background in [("catppuccin-mocha", "#221133"), ("catppuccin-latte", "#eeddcc")]:
        (runtime / "colors" / f"{name}.lua").write_text(
            f"vim.g.colors_name = '{name}'\n"
            f"vim.api.nvim_set_hl(0, 'Normal', {{ fg = '#668899', bg = '{background}' }})\n"
        )
    init = tmp_path / "init.lua"
    init.write_text("""
vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)
vim.opt.rtp:prepend(vim.env.THEME_TEST_RUNTIME)
package.loaded['custom.theme_sync_setup'] = { commands = function() end }
package.loaded['custom.theme_sync'] = { publish = function() end }
local theme = require 'custom.theme'
theme.apply_highlights = function() end
vim.o.termguicolors = true
vim.o.laststatus = 2
vim.o.statusline = '%{g:colors_name}'
theme.setup()
theme.restore()
""")
    env = dict(os.environ, THEME_TEST_ROOT=str(ROOT), THEME_TEST_RUNTIME=str(runtime),
               XDG_STATE_HOME=str(tmp_path / "state"), XDG_CACHE_HOME=str(tmp_path / "cache"),
               XDG_DATA_HOME=str(tmp_path / "data"))
    # macOS Unix-domain socket paths have a short length limit.
    socket_dir = tempfile.TemporaryDirectory(prefix="nvim-theme-", dir="/tmp")
    socket = str(Path(socket_dir.name) / "tmux.sock")

    def tmux(*args):
        return subprocess.run(["tmux", "-S", socket, *args], env=env,
                              capture_output=True, text=True, check=True, timeout=10).stdout

    def await_screen(name):
        deadline = time.monotonic() + 5
        screen = ""
        while time.monotonic() < deadline:
            screen = tmux("capture-pane", "-ep", "-t", "recipient:0.0")
            if name in screen:
                return screen
            time.sleep(0.025)
        pytest.fail(f"Inactive pane did not render {name}: {screen!r}")

    try:
        command = shlex.join(["nvim", "-u", str(init), "-i", "NONE"])
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "recipient", "-x", "90", "-y", "24", command)
        await_screen("catppuccin-mocha")
        # A second Neovim confirms the new choice. No focus events or keys are
        # sent to the recipient, and neither process touches the user's state.
        subprocess.run(["nvim", "--headless", "-u", str(init), "-i", "NONE",
                        "+lua require('custom.theme').select('catppuccin-latte')", "+qa!"],
                       env=env, capture_output=True, text=True, check=True, timeout=10)
        screen = await_screen("catppuccin-latte")
        assert "48;2;238;221;204" in screen, "captured pane retained old RGB background"
        assert "48;2;34;17;51" not in screen
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], env=env,
                       capture_output=True, timeout=10)
        socket_dir.cleanup()
