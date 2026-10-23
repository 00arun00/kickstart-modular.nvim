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
require('lazy').setup(require 'custom.plugins.catppuccin', {
  root = plugins,
  lockfile = vim.env.THEME_TEST_ROOT .. '/lazy-lock.json',
  install = { missing = false }, checker = { enabled = false },
  change_detection = { enabled = false },
})
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
