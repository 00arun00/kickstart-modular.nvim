"""Install/uninstall runs against disposable homes and detected-app doubles."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
pytestmark = [pytest.mark.fast, pytest.mark.lua]

PRELUDE = r"""
vim.opt.rtp:prepend(vim.env.THEME_TEST_ROOT)
local home = vim.env.HOME
local state = vim.fn.stdpath('state') .. '/terminal-theme'
local api = require 'custom.theme_sync_setup'
local function read(path)
 local f=io.open(path,'rb'); if not f then return nil end
 local s=f:read('*a'); f:close(); return s
end
local function write(path,s)
 vim.fn.mkdir(vim.fs.dirname(path),'p')
 local f=assert(io.open(path,'wb')); f:write(s); f:close()
end
local p = { base='#fafafa', mantle='#eeeeee', text='#242424', surface0='#dddddd', surface1='#bbbbbb',
 overlay1='#666666', subtext0='#555555', red='#aa1122', green='#228833', yellow='#997700',
 blue='#114499', lavender='#774499', sky='#117788', teal='#227766', peach='#994411' }
package.loaded['custom.theme'] = { palette=function() return p end }
vim.o.background='light'
local calls = {}
local binaries = { ghostty=true, tmux=true, fzf=true, pkill=true }
vim.fn.exepath = function(name) return binaries[name] and '/fake/'..name or '' end
vim.fn.executable = function() return 0 end
vim.uv.os_uname = function() return {sysname='Linux'} end
local ghost_version='Ghostty 1.3.1'
vim.system = function(args)
 calls[#calls+1]=args
 local out, code = '',0
 if args[2]=='+version' then out=ghost_version
 elseif args[2]=='-V' then out='tmux 3.5a'
 elseif args[2]=='show-environment' then out='FZF_DEFAULT_OPTS=--layout=reverse --color=dark\n'
 elseif args[2]=='show-options' then
   local option=args[#args]
   if option=='@sessionx-_built-fzf-opts' then out="declare -a fzf_opts=('--style=full')\n"
   elseif option=='@sessionx-additional-options' then out="--style=full --header='some words'"
   elseif option=='focus-events' then out='off\n'
   elseif option:match('format$') then out='#[fg=#123456,bg=colour42,bold] #I #W #(echo fg=red)\n'
   else out='default\n' end
 end
 return {wait=function() return {code=code,stdout=out,stderr=''} end}
end
"""


def run_lua(tmp_path, body):
    script = tmp_path / "test.lua"
    script.write_text(PRELUDE + body + "\nprint('PASS'); vim.cmd 'qa!'\n")
    home = tmp_path / "home with spaces"
    home.mkdir(exist_ok=True)
    env = dict(
        os.environ,
        HOME=str(home),
        SHELL="/bin/zsh",
        ZDOTDIR=str(home),
        THEME_TEST_ROOT=str(ROOT),
        XDG_CONFIG_HOME=str(home / ".config"),
        XDG_STATE_HOME=str(home / "state"),
        XDG_CACHE_HOME=str(home / "cache"),
        XDG_DATA_HOME=str(home / "data"),
        FZF_DEFAULT_OPTS="--layout=reverse --color=dark",
    )
    result = subprocess.run(
        ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", str(script)],
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "PASS" in result.stdout + result.stderr
    return home


def test_setup_preview_install_uninstall_preserves_later_edits(tmp_path):
    run_lua(
        tmp_path,
        r"""
local configs={home..'/.config/ghostty/config',home..'/.tmux.conf',home..'/.zshrc'}
for _,path in ipairs(configs) do write(path,'# original\n') end
api.commands()
vim.cmd 'ThemeSyncSetup'
assert(read(state..'/enabled')==nil)
for _,path in ipairs(configs) do assert(read(path)=='# original\n') end
local plan=api.plan()
assert(#plan.files==3 and plan.targets.ghostty and plan.targets.tmux and plan.targets.fzf)
local backup=api.install(plan)
assert(read(state..'/enabled'))
assert(api.plan().installed)
assert(read(state..'/ghostty.conf'):find('palette = 22=',1,true))
assert(read(state..'/ghostty.conf'):find('background = #fafafa',1,true))
local tmux=read(state..'/tmux.conf')
assert(tmux:find('#I #W #(echo fg=red)',1,true), 'changed a status command')
assert(not tmux:find('#123456',1,true))
assert(tmux:find('@sessionx-_built-fzf-opts',1,true))
for _,file in ipairs(plan.files) do
 assert(read(file.backup)=='# original\n')
 assert(read(file.target):find('# BEGIN nvim-theme-sync',1,true))
end
write(configs[2],read(configs[2])..'# later edit\n')
api.uninstall(api.uninstall_plan())
assert(read(state..'/enabled')==nil)
assert(read(state..'/installation.json')==nil)
assert(read(backup..'/installation.json'))
assert(read(configs[1])=='# original\n')
assert(read(configs[2])=='# original\n# later edit\n')
assert(read(configs[3])=='# original\n')
assert(api.plan().installed==nil)
""",
    )


def test_missing_unsupported_and_ambiguous_apps_are_skipped(tmp_path):
    run_lua(
        tmp_path,
        r"""
binaries={}
assert(#api.plan().files==0)
binaries={ghostty=true}
ghost_version='Ghostty 1.1.3'
assert(#api.plan().files==0, 'must not signal old Ghostty')
ghost_version='Ghostty 1.3.1'
vim.uv.os_uname=function() return {sysname='Darwin'} end
write(home..'/.config/ghostty/config','one')
write(home..'/Library/Application Support/com.mitchellh.ghostty/config','two')
assert(#api.plan().files==0,'ambiguous Ghostty configs require a path')
assert(#api.plan({ghostty_config=home..'/.config/ghostty/config'}).files==1)
vim.uv.os_uname=function() return {sysname='Windows_NT'} end
assert(#api.plan().files==0)
""",
    )


def test_uninstall_refuses_modified_managed_block_without_touching_files(tmp_path):
    run_lua(
        tmp_path,
        r"""
write(home..'/.zshrc','# original\n')
local plan=api.plan({tmux=false,ghostty=false})
api.install(plan)
local path=home..'/.zshrc'
local modified=read(path):gsub('function fzf','function myfzf')
write(path,modified)
local ok=pcall(api.uninstall_plan)
assert(not ok)
assert(read(path)==modified and read(state..'/enabled'))
""",
    )


def test_symlinks_new_files_and_failed_install_rollback(tmp_path):
    run_lua(
        tmp_path,
        r"""
local source=home..'/dotfiles/zshrc'
write(source,'# linked\n')
assert(vim.uv.fs_symlink(source,home..'/.zshrc'))
local plan=api.plan({tmux=false})
local rename=vim.uv.fs_rename
vim.uv.fs_rename=function(from,to)
 if to==source then return nil,'forced write failure' end
 return rename(from,to)
end
assert(not pcall(api.install,plan))
vim.uv.fs_rename=rename
assert(read(source)=='# linked\n')
assert(read(home..'/.config/ghostty/config')==nil)
assert(read(state..'/enabled')==nil)
plan=api.plan({tmux=false})
api.install(plan)
assert(vim.uv.fs_lstat(home..'/.zshrc').type=='link')
api.uninstall(api.uninstall_plan())
assert(vim.uv.fs_lstat(home..'/.zshrc').type=='link' and read(source)=='# linked\n')
assert(read(home..'/.config/ghostty/config')==nil)
""",
    )


def test_shell_wrapper_reads_new_colors_and_preserves_options(tmp_path):
    home = run_lua(
        tmp_path,
        r"""
write(home..'/.zshrc','# original\n')
api.install(api.plan({tmux=false,ghostty=false}))
""",
    )
    executable = tmp_path / "fzf"
    executable.write_text('#!/bin/sh\nprintf \'%s\\n\' "$FZF_DEFAULT_OPTS" "$*"\n')
    executable.chmod(0o755)
    colors = home / "state/nvim/terminal-theme/fzf.conf"
    colors.write_text("--color=light,bg:#ffffff\n")
    env = dict(
        os.environ,
        PATH=str(tmp_path) + os.pathsep + os.environ["PATH"],
        FZF_DEFAULT_OPTS="--height=40% --color=dark",
        HOME=str(home),
    )
    for shell in ("bash", "zsh"):
        if not shutil.which(shell):
            continue
        result = subprocess.run(
            [shell, "-c", 'source "$HOME/.zshrc"; fzf --filter="some words"'],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        )
        assert "--height=40% --color=dark --color=light,bg:#ffffff" in result.stdout
        assert "--filter=some words" in result.stdout


def test_existing_manual_links_are_adopted_without_duplicates(tmp_path):
    run_lua(
        tmp_path,
        r"""
write(state..'/enabled','manual')
write(state..'/templates.json','{}')
write(home..'/.config/ghostty/config','theme = Previous\nconfig-file = '..state..'/ghostty.conf\n')
write(home..'/.tmux.conf','set -g mouse on\nsource-file -q "'..state..'/tmux.conf"\n')
write(home..'/.zshrc','export ORIGINAL=yes\nexport FZF_DEFAULT_OPTS_FILE="'..state..'/fzf.conf"\n')
local plan=api.plan()
assert(plan.legacy)
api.install(plan)
assert(read(home..'/.config/ghostty/config'):match('config%-file'))
local _,count=read(home..'/.config/ghostty/config'):gsub('config%-file','')
assert(count==1)
api.uninstall(api.uninstall_plan())
assert(read(home..'/.config/ghostty/config')=='theme = Previous\n')
assert(read(home..'/.tmux.conf')=='set -g mouse on\n')
assert(read(home..'/.zshrc')=='export ORIGINAL=yes\n')
""",
    )


def test_detection_without_sessionx_and_config_change_refusal(tmp_path):
    run_lua(
        tmp_path,
        r"""
local original=vim.system
vim.system=function(args)
 if args[#args]=='@sessionx-_built-fzf-opts' then return {wait=function() return {code=0,stdout=''} end} end
 return original(args)
end
local plan=api.plan({ghostty=false,fzf=false})
assert(plan.templates.sessionx==false)
write(home..'/.tmux.conf','# changed after preview\n')
assert(not pcall(api.install,plan))
assert(read(state..'/enabled')==nil)
plan=api.plan({ghostty=false,fzf=false})
api.install(plan)
assert(not read(state..'/tmux.conf'):find('@sessionx',1,true))
assert(not read(state..'/tmux.conf'):find('set-environment',1,true))
api.uninstall(api.uninstall_plan())
assert(read(home..'/.tmux.conf')=='# changed after preview\n')
""",
    )


def test_new_config_under_symlinked_parent_can_be_uninstalled(tmp_path):
    run_lua(
        tmp_path,
        r"""
vim.fn.mkdir(home..'/real-parent','p')
assert(vim.uv.fs_symlink(home..'/real-parent',home..'/alias-parent'))
local path=home..'/alias-parent/newrc'
api.install(api.plan({ghostty=false,tmux=false,shell_config=path}))
assert(read(home..'/real-parent/newrc'))
api.uninstall(api.uninstall_plan())
assert(read(path)==nil)
assert(vim.uv.fs_lstat(home..'/alias-parent').type=='link')
""",
    )
