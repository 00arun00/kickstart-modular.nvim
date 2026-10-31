"""Exercise real theme variants through the picker and shared palette consumers."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.integration, pytest.mark.lua]


def test_every_variant_previews_cancels_restores_and_exports(tmp_path):
    detected = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "--cmd",
         "lua io.stdout:write(vim.fn.stdpath('data')); vim.cmd('qa!')"],
        capture_output=True, text=True, check=True, timeout=10,
    )
    plugins = Path(os.environ.get(
        "NVIM_TEST_PLUGIN_ROOT", str(Path(detected.stdout) / "lazy")
    ))
    required = (
        "lazy.nvim", "telescope.nvim", "plenary.nvim", "catppuccin", "rose-pine",
        "tokyonight.nvim", "neovim-ayu", "onedarkpro.nvim", "vesper.nvim",
        "kanso.nvim", "vague.nvim", "flexoki", "kanagawa-paper.nvim",
        "melange-nvim", "oxocarbon.nvim", "evergarden", "lualine.nvim",
        "mellow.nvim", "oldworld.nvim", "mellifluous.nvim", "poimandres.nvim",
        "nightfox.nvim", "flow.nvim",
    )
    missing = [name for name in required if not (plugins / name).is_dir()]
    if missing:
        pytest.skip("Install theme plugins or set NVIM_TEST_PLUGIN_ROOT: " + ", ".join(missing))

    script = tmp_path / "theme-variants.lua"
    script.write_text(r"""
vim.go.loadplugins = true
vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)
local plugins = vim.env.THEME_TEST_PLUGINS
vim.opt.rtp:prepend(plugins .. '/lazy.nvim')
local exports = require 'custom.theme_sync'
local published = 0
package.loaded['custom.theme_sync'] = { publish = function() published = published + 1 end }
require('lazy').setup(require 'custom.plugins.catppuccin', {
  root = plugins,
  lockfile = vim.env.THEME_TEST_ROOT .. '/lazy-lock.json',
  install = { missing = false }, checker = { enabled = false },
  change_detection = { enabled = false },
})
-- Theme plugins ship their runtime; startup must not bootstrap LuaRocks or
-- build already installed themes. Keeping install.missing=false above makes
-- this assertion safe even when a newly added spec accidentally requests it.
local configured = require('lazy.core.config').plugins
assert(not configured.hererocks, 'theme setup requested an unnecessary LuaRocks bootstrap')
for name, plugin in pairs(configured) do
  assert(not plugin._.build, name .. ': installed theme still requires a startup build')
end
for _, name in ipairs { 'plenary.nvim', 'telescope.nvim', 'lualine.nvim' } do
  vim.opt.rtp:append(plugins .. '/' .. name)
end
require('telescope').setup {}
require('lualine').setup { options = { theme = 'auto' } }
local theme = require 'custom.theme'
local state = vim.fn.stdpath 'state' .. '/theme-choice'
local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
local function hex(value) return string.format('#%06x', value):lower() end
local function picker()
  theme.pick()
  local p = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
  assert(vim.wait(2000, function() return type(p.manager) == 'table' and p:get_selection() end, 10))
  return p
end
local function cancel(p) require('telescope.actions').close(p.prompt_bufnr) end
local queries = {}
local function preview(p, name)
  local completed = false
  p:register_completion_callback(function() completed = true end)
  p:set_prompt(queries[name])
  assert(vim.wait(2000, function() return completed end, 10), 'picker did not finish filtering ' .. name)
  -- Family prefixes such as "onedark" can match multiple variants. Navigate to
  -- the exact entry instead of assuming fuzzy ranking always selects it first.
  for entry in p.manager:iter() do
    if entry.value == name then p:set_selection(p:get_row(p.manager:find_entry(entry))) end
  end
  assert(p:get_selection() and p:get_selection().value == name, 'picker did not select ' .. name)
end
local function check_palette(name)
  local c = theme.palette()
  for _, role in ipairs {
    'base', 'mantle', 'text', 'surface0', 'surface1', 'overlay1', 'subtext0',
    'lavender', 'red', 'peach', 'yellow', 'blue', 'sky', 'teal', 'green',
    'task_active', 'task_quarter', 'task_half', 'task_three_quarters', 'task_done',
  } do
    assert(type(c[role]) == 'string' and c[role]:match '^#%x%x%x%x%x%x$', name .. ': invalid ' .. role)
  end
  assert(c.base:lower() == hex(hl('Normal').bg), name .. ': wrong background')
  assert(c.text:lower() == hex(hl('Normal').fg), name .. ': wrong foreground')
  assert(hex(hl('NeoTreeNormal').bg) == c.mantle:lower())
  assert(hex(hl('Folded').bg) == c.mantle:lower())
  assert(hex(hl('CustomBlameAccent').fg) == c.lavender:lower())
  assert(hex(hl('SnacksImageMath').fg) == c.teal:lower())
  assert(hex(hl('MarkdownTaskDone').fg) == c.task_done:lower())
  require('custom.project_home.volt.theme').apply()
  assert(hl('ProjectHomeVoltTitle').fg and hl('ProjectHomeVoltKey').bg)
  require('lualine').refresh { force = true }
  local terminal = {}
  for i = 0, 15 do terminal[i + 1] = vim.g['terminal_color_' .. i] end
  local output = exports.render(c, vim.o.background, terminal, { options = {}, fzf_base = '' }, require('custom.terminal_palette').highlights())
  assert(vim.tbl_contains(output.ghostty, 'background = ' .. c.base))
  assert(vim.tbl_contains(output.ghostty, 'foreground = ' .. c.text))
  assert(output.fzf[1]:find('bg:' .. c.base, 1, true))
  assert(#output.tmux > 0)
  for _, line in ipairs(output.ghostty) do
    if line:match '^palette = ' then assert(line:match '=#%x%x%x%x%x%x$') end
  end
  return c.base .. ':' .. c.text
end

local p = picker()
local names, available = {}, {}
for entry in p.manager:iter() do
  names[#names + 1] = entry.value
  available[entry.value] = true
  queries[entry.value] = entry.ordinal
end
cancel(p)
assert(#names == 60, 'expected 60 distinct picker variants, got ' .. #names)
local additions = {
  'vesper', 'kanso-zen', 'kanso-ink', 'kanso-mist', 'kanso-pearl', 'vague',
  'flexoki-dark', 'flexoki-light', 'kanagawa-paper-ink', 'kanagawa-paper-canvas',
  'melange-dark', 'melange-light', 'oxocarbon-dark', 'oxocarbon-light',
  'evergarden-winter', 'evergarden-fall', 'evergarden-spring', 'evergarden-summer',
  'mellow-dark', 'mellow-light', 'oldworld-default', 'oldworld-cooler', 'oldworld-oled',
  'mellifluous-dark', 'mellifluous-light', 'mellifluous-alduin', 'mellifluous-mountain',
  'mellifluous-tender', 'mellifluous-kanagawa_dragon', 'poimandres',
  'nightfox', 'dayfox', 'dawnfox', 'duskfox', 'nordfox', 'terafox', 'carbonfox',
  'flow-dark', 'flow-light', 'flow-mono-dark', 'flow-mono-light',
}
for _, name in ipairs(additions) do assert(available[name], 'missing variant: ' .. name) end

-- Preview each installed entry; cancel restores the confirmed palette and state.
assert(theme.select('catppuccin-mocha'))
local original = check_palette('catppuccin-mocha')
for _, name in ipairs(names) do
  local count = published
  p = picker()
  preview(p, name)
  check_palette(name)
  assert(published == count, 'preview published terminal changes')
  assert(vim.fn.readfile(state)[1] == 'catppuccin-mocha', 'preview saved state')
  cancel(p)
  assert(check_palette('cancel ' .. name) == original, 'cancel retained preview palette')
end

-- Confirm each new variant through Telescope, then restore it after switching away.
-- Reopen and cancel from that variant to exercise native family-name normalization.
for _, name in ipairs(additions) do
  local count = published
  p = picker()
  preview(p, name)
  local expected = check_palette(name)
  local background = vim.o.background
  require('telescope.actions').select_default(p.prompt_bufnr)
  assert(published == count + 1, 'confirmation did not publish exactly once')
  assert(vim.fn.readfile(state)[1] == name, 'confirmation lost exact variant')
  vim.cmd.colorscheme 'catppuccin-mocha'
  theme.restore()
  assert(vim.o.background == background and check_palette('restore ' .. name) == expected)
  p = picker()
  assert(p:get_selection().value == name, 'picker forgot selected variant ' .. name)
  preview(p, 'catppuccin-latte')
  cancel(p)
  assert(vim.o.background == background and check_palette('cancel to ' .. name) == expected)
end
print('PASS: 60 previews and palettes; 41 confirmations, restores, and cancellations; terminal exports')
vim.cmd 'qa!'
""")
    env = dict(
        os.environ, THEME_TEST_ROOT=str(ROOT), THEME_TEST_PLUGINS=str(plugins),
        XDG_STATE_HOME=str(tmp_path / "state"), XDG_CACHE_HOME=str(tmp_path / "cache"),
        XDG_DATA_HOME=str(tmp_path / "data"),
    )
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
        env=env, capture_output=True, text=True, check=False, timeout=90,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS:" in result.stdout + result.stderr
