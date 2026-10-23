"""Font setup and selection preserve original settings and unrelated edits."""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.fast, pytest.mark.lua]


def test_font_roundtrip(tmp_path):
    home = tmp_path / "home with spaces"
    home.mkdir()
    script = tmp_path / "fonts.lua"
    script.write_text(r"""
vim.opt.rtp:prepend(vim.env.FONT_TEST_ROOT)
local api = require 'custom.fonts'
local config = vim.env.HOME .. '/ghostty.conf'
local function read(path) return table.concat(vim.fn.readfile(path), '\n') end
vim.fn.writefile({'font-family = Existing Font', 'font-size = 13'}, config)
vim.g.font_sync = {ghostty_config=config}
local available = true
local reloads = 0
local installs, pending = 0, nil
local stream_output
local changes = 0
vim.api.nvim_create_autocmd('User', {pattern='FontInstallChanged', callback=function() changes=changes+1 end})
local consent = false
vim.fn.confirm = function(_, _, default)
  assert(default == 1, 'installation confirmation must default to No')
  return consent and 2 or 1
end
vim.uv.os_uname = function() return {sysname='Darwin'} end
vim.fn.exepath = function(name) return '/fake/' .. name end
vim.system = function(args, opts, callback)
  if args[1] == '/fake/brew' then
    assert(opts.timeout == 300000 and opts.stdin == false)
    stream_output = opts.stdout
    assert(args[2] == 'install' and args[3] == '--cask' and args[4] == 'font-lilex')
    installs, pending = installs + 1, callback
    return {}
  end
  local stdout = ''
  if args[2] == '+version' then stdout = 'Ghostty 1.3.1'
  elseif args[2] == '+list-fonts' then stdout = available and 'iA Writer Mono V\nLilex\n' or ''
  elseif args[1] == 'pkill' then reloads = reloads + 1
  else error('unexpected command') end
  return {wait=function() return {code=0,stdout=stdout} end}
end
api.setup()
assert(vim.fn.exists(':FontPicker') == 2)
local profiles = require 'custom.font_profiles'
for _, item in ipairs(api.presets) do
  local preview = table.concat(profiles.lines(item, false), '\n')
  assert(preview:find('## Font supports', 1, true))
  assert(preview:find('Ligatures: inherited, not explicitly enabled or disabled.', 1, true))
  assert(preview:find('ACTIVE terminal font', 1, true))
  if item.family then assert(preview:find('Not installed', 1, true)) end
end
local custom = table.concat(profiles.lines({id='original', label='Other Font (baseline)', detail='Existing settings'}, true), '\n')
assert(custom:find('Not catalogued', 1, true), 'custom baseline must not inherit JetBrains capability claims')
api.install()
local original = read(config)
api.install()
assert(read(config) == original, 'installation must be idempotent')
local state = vim.fn.stdpath('state') .. '/terminal-font'
local manifest = vim.json.decode(read(state .. '/installation.json'))
assert(read(manifest.backup) == 'font-family = Existing Font\nfont-size = 13')
assert(api.current() == 'original')
assert(api.baseline_label() == 'Existing Font (baseline)')
local complete
api.install_font('lilex')
assert(installs == 0, 'declining installation must not launch Homebrew')
for _, id in ipairs {'maple', 'recursive', 'plex', 'commit'} do
  api.install_font(id)
  assert(installs == 0, 'new presets must require consent too')
  assert(not pcall(api.select, id), 'missing fonts must not change typography')
  assert(api.current() == 'original')
end
consent = true
api.install_font('lilex', function(ok) complete = ok end)
api.install_font('lilex')
assert(installs == 1, 'duplicate installs must be suppressed')
stream_output(nil, 'Downloading font...\n')
assert(vim.wait(1000, function() return read(state .. '/install-lilex.log') == 'Downloading font...' end))
assert(changes > 0, 'open pickers must receive progress events')
pending({code=0,stdout='installed'})
assert(vim.wait(1000, function() return complete == true end))
assert(api.current() == 'original', 'installation must not change selected typography')
api.install_font('lilex', function(ok) complete = ok end)
pending({code=1,stderr='download failed'})
assert(vim.wait(1000, function() return complete == false end))
assert(read(state .. '/install-lilex.log') == 'download failed')
assert(api.current() == 'original')
api.install_font('lilex', function(ok) complete = ok end)
complete = nil
pending({code=124,stderr='timeout'})
assert(vim.wait(1000, function() return complete == false end))
local previous = installs
api.install_font('lilex')
assert(installs == previous + 1, 'timeout must release installing state for retry')
pending({code=1,stderr='retry failed'})
assert(vim.wait(1000, function() return read(state .. '/install-lilex.log') == 'retry failed' end))
assert(not pcall(api.install_font, 'arbitrary-package'))
api.select('writer')
assert(api.current() == 'writer')
assert(read(state .. '/ghostty.conf'):find('iA Writer Mono V', 1, true))
api.select('lilex')
assert(api.current() == 'lilex')
available = false
assert(not pcall(api.select, 'writer'), 'missing font must not silently fall back')
assert(api.current() == 'lilex')
assert(not pcall(api.select, 'unknown'))
api.select('original')
assert(read(state .. '/ghostty.conf') == '# font-choice: original', 'original must remove all overrides')
vim.fn.writefile({'# unrelated later edit'}, config, 'a')
api.uninstall()
assert(read(config) == 'font-family = Existing Font\nfont-size = 13\n# unrelated later edit')
assert(vim.fn.filereadable(manifest.backup) == 1)
assert(reloads == 4)
api.install()
local modified = read(config):gsub('# END nvim%-font%-sync', '# edited end marker')
vim.fn.writefile(vim.split(modified, '\n', {plain=true}), config)
assert(not pcall(api.uninstall), 'edited block must not be removed')
assert(read(config) == modified)
vim.cmd 'qa!'
""")
    env = dict(os.environ, HOME=str(home), FONT_TEST_ROOT=str(ROOT))
    for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
        env[f"XDG_{kind}_HOME"] = str(home / kind.lower())
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-l", str(script)],
        env=env,
        check=False,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr
