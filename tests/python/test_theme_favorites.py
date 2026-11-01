"""Favorites stay independent of preview/apply and preserve other editors' edits."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def run_lua(tmp_path, source, *, plugins=False):
    env = dict(os.environ, THEME_TEST_ROOT=str(ROOT),
               XDG_STATE_HOME=str(tmp_path / "state"),
               XDG_CACHE_HOME=str(tmp_path / "cache"))
    if plugins:
        detected = subprocess.check_output(
            ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "--cmd",
             "lua io.stdout:write(vim.fn.stdpath('data')); vim.cmd('qa!')"],
            text=True, timeout=10,
        )
        env["THEME_TEST_PLUGINS"] = os.environ.get("NVIM_TEST_PLUGIN_ROOT", str(Path(detected) / "lazy"))
    env["XDG_DATA_HOME"] = str(tmp_path / "data")
    script = tmp_path / "favorites.lua"
    script.write_text("vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)\n" + source + "\nvim.cmd 'qa!'\n")
    result = subprocess.run(["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
                            env=env, capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.fast
@pytest.mark.lua
def test_favorite_storage_merges_variant_edits_and_failed_writes(tmp_path):
    run_lua(tmp_path, r"""
local store = require 'custom.theme_favorites'
assert(vim.tbl_isempty(store.read()))
assert(store.read_scope() == nil)
store.save_scope('all')
assert(store.read_scope() == 'all')
store.set('oldworld-cooler', true)
local stale_snapshot = store.read()
store.set('flow-mono-dark', true)
store.set('mellow-light', true)
store.set('oldworld-cooler', false)
local saved = store.read()
assert(not saved['oldworld-cooler'] and saved['flow-mono-dark'] and saved['mellow-light'])
assert(stale_snapshot['oldworld-cooler'] and not stale_snapshot['flow-mono-dark'])
assert(not pcall(store.set, '../escape', true))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function() return nil, 'forced rename failure' end
assert(not pcall(store.set, 'vague', true))
vim.uv.fs_rename = rename
assert(vim.deep_equal(saved, store.read()), 'failed write changed favorites')
-- A fresh editor sees the same markers and cannot overwrite unrelated favorites.
local child = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ "vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)",
  "local s = require 'custom.theme_favorites'; assert(s.read_scope() == 'all'); s.save_scope('favorites'); s.set('kanso-ink', true)" }, child)
local result = vim.system({ 'nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', child }, { text = true }):wait()
assert(result.code == 0, result.stderr)
saved = store.read()
assert(saved['kanso-ink'] and saved['flow-mono-dark'] and saved['mellow-light'])
assert(store.read_scope() == 'favorites', 'view did not persist across instances')
vim.fn.delete(child)
""")


@pytest.mark.integration
@pytest.mark.lua
def test_picker_favorites_filters_markers_cancel_and_external_updates(tmp_path):
    run_lua(tmp_path, r"""
vim.go.loadplugins = true
local plugins = vim.env.THEME_TEST_PLUGINS
vim.opt.rtp:prepend(plugins .. '/lazy.nvim')
local published = 0
package.loaded['custom.theme_sync'] = { publish = function() published = published + 1 end }
require('lazy').setup(require 'custom.plugins.catppuccin', {
  root = plugins, lockfile = vim.env.THEME_TEST_ROOT .. '/lazy-lock.json',
  install = { missing = false }, checker = { enabled = false }, change_detection = { enabled = false },
})
for _, name in ipairs { 'plenary.nvim', 'telescope.nvim', 'telescope-fzf-native.nvim' } do vim.opt.rtp:append(plugins .. '/' .. name) end
require('telescope').setup {}
require('telescope').load_extension 'fzf'
local theme, store = require 'custom.theme', require 'custom.theme_favorites'
local actions = require 'telescope.actions'
local function wait_for(p, action)
  local done = false
  p:register_completion_callback(function() done = true end)
  action()
  assert(vim.wait(2000, function() return done end, 10), 'picker refresh did not complete')
end
local function open(scope)
  local p = theme.pick { scope = scope }
  assert(vim.wait(2000, function() return type(p.manager) == 'table' end, 10))
  return p
end
local function key(p, key, mode)
  local mapping = vim.fn.maparg(key, mode or 'i', false, true)
  assert(type(mapping.callback) == 'function', 'missing mapping ' .. key)
  wait_for(p, mapping.callback)
end
local function search(p, text) wait_for(p, function() p:set_prompt(text) end) end
local function selected(p) return p:get_selection() and p:get_selection().value end
local function cancel(p) actions.close(p.prompt_bufnr) end
theme.select('catppuccin-mocha')
local original, count = theme.palette().base, published
local p = open()
local catalog_count = p.manager:num_results()
assert(catalog_count > 0, 'the picker catalog is empty')
assert(selected(p) == 'catppuccin-mocha', 'opening picker should select the confirmed theme')
local positions, ordered = {}, {}
for entry in p.manager:iter() do
  ordered[#ordered + 1] = entry.value
  positions[entry.value] = #ordered
end
assert(positions['melange-dark'] < positions['mellifluous-dark'] and positions['mellifluous-dark'] < positions['mellow-dark'],
  'accented labels must sort alphabetically too')
local function navigate(key, mode) vim.fn.maparg(key, mode or 'i', false, true).callback() end
p:set_selection(p:get_row(1))
navigate('<C-p>')
assert(selected(p) == ordered[1], 'Ctrl-P wrapped at the top')
navigate('<C-n>')
assert(selected(p) == ordered[2], 'Ctrl-N did not move down')
navigate('<C-p>', 'n')
assert(selected(p) == ordered[1], 'Ctrl-P did not move up in normal mode')
for _ = 1, #ordered + 1 do navigate('<C-n>') end
assert(selected(p) == ordered[#ordered], 'Ctrl-N did not stop at the bottom')
navigate('<C-n>', 'n')
assert(selected(p) == ordered[#ordered], 'normal-mode Ctrl-N wrapped at the bottom')
search(p, 'ay')
assert(p.manager:num_results() > 1 and selected(p) == p.manager:get_entry(1).value,
  'typing kept the opening row instead of selecting the best fuzzy match')
navigate('<C-n>')
assert(selected(p) == p.manager:get_entry(2).value, 'filtered results cannot be navigated')
search(p, 'ayu')
assert(selected(p) == p.manager:get_entry(1).value, 'editing the query did not reset selection to the top')
search(p, 'dark')
for entry in p.manager:iter() do
  assert(entry.value ~= 'catppuccin-mocha' and entry.value ~= 'oldworld-default', 'background metadata leaked into search')
end
search(p, '')
assert(selected(p) == 'catppuccin-mocha', 'clearing the query lost the opening theme')
search(p, 'OldWorld Cooler')
assert(selected(p) == 'oldworld-cooler')
key(p, '<C-s>')
assert(store.read()['oldworld-cooler'] and selected(p) == 'oldworld-cooler')
assert(p:_get_prompt() == 'OldWorld Cooler' and published == count)
key(p, '<Tab>')
assert(p.manager:num_results() == 1)
key(p, '<C-l>') -- Any -> Dark
assert(p.manager:num_results() == 1)
key(p, '<C-l>') -- Dark -> Light: no matches
assert(p.manager:num_results() == 0)
navigate('<C-n>')
navigate('<C-p>')
-- An empty picker cannot apply the stale prior selection or star it again.
actions.select_default(p.prompt_bufnr)
vim.fn.maparg('<C-s>', 'i', false, true).callback()
assert(vim.api.nvim_buf_is_valid(p.prompt_bufnr) and published == count)
key(p, '<C-l>') -- Light -> Any
assert(selected(p) == 'oldworld-cooler')
cancel(p)
assert(theme.palette().base == original and store.read()['oldworld-cooler'])
assert(published == count)

-- Last view was Favorites. Starring from All preserves the selected view.
p = open()
assert(p.manager:num_results() == 1)
key(p, '<Tab>', 'n')
search(p, 'Catppuccin Mocha')
search(p, 'Mellow Light')
key(p, '<C-s>', 'n')
assert(store.read()['mellow-light'])
key(p, '<Tab>')
search(p, '')
assert(p.manager:num_results() == 2)
assert(p.manager:get_entry(1).value == 'mellow-light', 'favorites are not alphabetical')
search(p, 'OldWorld Cooler')
key(p, '<C-s>') -- remove current row from Favorites
assert(p.manager:num_results() == 0 and not store.read()['oldworld-cooler'])
search(p, '')
assert(selected(p) == 'mellow-light')
key(p, '<C-s>')
assert(p.manager:num_results() == 0)
key(p, '<Tab>')
assert(p.manager:num_results() == catalog_count)
cancel(p)

-- External edits update an open Favorites picker without changing the query
-- or publishing terminal colors. Separate marker files preserve both edits.
store.set('oldworld-cooler', true)
p = open('favorites')
local child = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ "vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)",
  "require('custom.theme_favorites').set('mellow-light', true)" }, child)
local result = vim.system({ 'nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', child }, { text = true }):wait()
assert(result.code == 0, result.stderr)
assert(vim.wait(2000, function() return p.manager:num_results() == 2 end, 10), 'external favorite did not appear')
assert(store.read()['oldworld-cooler'] and store.read()['mellow-light'])
assert(published == count and p:_get_prompt() == '')
search(p, 'Mellow Light')
actions.select_default(p.prompt_bufnr)
assert(published > count and vim.fn.readfile(vim.fn.stdpath('state') .. '/theme-choice')[1] == 'mellow-light')
assert(vim.o.background == 'light')
vim.fn.delete(child)
-- Explicit views become the remembered choice, independent of favorites count.
vim.cmd 'ThemePicker all'
p = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
assert(vim.wait(2000, function() return type(p.manager) == 'table' and p.manager:num_results() == catalog_count end, 10))
cancel(p)
p = open()
assert(p.manager:num_results() == catalog_count)
key(p, '<Tab>')
cancel(p)
p = open()
assert(p.manager:num_results() == 2)
cancel(p)
""", plugins=True)
