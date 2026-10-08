"""Workspace design-fidelity captures from actual Neovim redraw events.

Populated sample data intentionally matches the approved design's content density.
No project files or Git state are changed. All persistence is temporary.
"""
import json
import os
from pathlib import Path
import sys
import tempfile

import pynvim
from capture_grid import capture

repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/project-home-fidelity')
output.mkdir(parents=True, exist_ok=True)
full_config = '--full-config' in sys.argv
with tempfile.TemporaryDirectory(prefix='home-visual-') as temp:
    temp = Path(temp)
    os.environ['NVIM_LOG_FILE'] = str(temp / 'nvim.log')
    os.environ['XDG_STATE_HOME'] = str(temp / 'state')
    boot = temp / 'init.lua'
    boot.write_text('''
vim.opt.termguicolors=true
vim.opt.swapfile=false
vim.opt.shortmess:append('I')
vim.opt.laststatus=2
vim.opt.rtp:prepend(%s)
vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/catppuccin'))
require('catppuccin').setup({flavour='mocha',compile_path=%s..'/theme'})
vim.cmd.colorscheme('catppuccin-mocha')
require('custom.project_home.state').configure({directory=%s..'/state'})
require('custom.project_home.providers').load=function(_,cb) return function()end end
require('custom.project_home').setup({startup=false})
vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/volt'));require('custom.project_home.volt').setup()
local root=%s
local paths={'lua/kickstart/plugins/mini.lua','lua/custom/plugins/catppuccin.lua','init.lua','docs/navigation.md','README.md'}
local recent={};for _,p in ipairs(paths)do recent[#recent+1]={path=root..'/'..p,label=p}end
local days={};for i=1,364 do days[i]={date=os.date('%%Y-%%m-%%d',os.time()-(364-i)*86400),count=(i*17%%23)>11 and i%%9 or 0,mine=i%%5==0 and 2 or 0}end
_G.visual_model={
 root=root,name='nvim',branch='feature/dashboard',session={count=4},recents=recent,
 show_activity=true,scope='repo',
 git={available=true,loading=false,upstream='origin/feature/dashboard',ahead=2,behind=0,
  changes={{path='a'},{path='b'},{path='c'},{path='d'}},modified=3,staged=1,unstaged=2,untracked=1,
  latest={hash='a81f3c2abcdef',subject='Add project entry points',date=os.date('%%Y-%%m-%%dT12:00:00+00:00')}},
 prs={status='ready',user='aj',items={
  {number=42,title='Build a project-aware dashboard',reviewDecision='CHANGES_REQUESTED',statusCheckRollup={{conclusion='FAILURE'}}},
  {number=39,title='Improve Python environment discovery',reviewDecision='REVIEW_REQUIRED',statusCheckRollup={{conclusion='SUCCESS'}}},
  {number=37,title='Clean up theme configuration',isDraft=true,author={login='aj'},statusCheckRollup={}}}},
 worktrees={{path=root,current=true,branch='feature/dashboard'},{path='/tmp/second',branch='main'},{path='/tmp/third',branch='fix/notebook'}},
 activity={status='ready',identity='aj@example.test',days=days,total=186,mine_total=54}
}
''' % (json.dumps(str(repo)), json.dumps(str(temp)), json.dumps(str(temp)), json.dumps(str(repo))))
    argv = ['nvim', '--embed', '--headless', '-n', '-i', 'NONE']
    if full_config:
        os.chdir(repo)
        os.environ['XDG_CACHE_HOME'] = str(temp / 'cache')
        argv += ['--cmd', "lua vim.api.nvim_create_autocmd('VimEnter',{once=true,callback=function() local m=package.loaded['mason-tool-installer'];if m then m.setup({run_on_start=false})end end})"]
    else:
        argv += ['-u', str(boot)]
    n = pynvim.attach('child', argv=argv)
    try:
        n.ui_attach(166, 50, rgb=True, ext_linegrid=True)
        if full_config:
            n.exec_lua(boot.read_text()[boot.read_text().index('local root='):])
        layout = 'volt'
        n.exec_lua("local c=require('custom.project_home').open(...);if c.cancel then c.cancel() end;c.model=vim.deepcopy(visual_model); c.render()", layout)
        if full_config:
            # Keep startup messages as evidence, then close transient notification
            # overlays so they do not obscure the dashboard being compared.
            n.exec_lua('vim.wait(200)')
            (output / 'startup-messages.txt').write_text(n.command_output('messages'))
            n.command('silent! Noice dismiss')
        results = []
        for width, height in [(166, 50), (120, 52), (80, 45)]:
            n.ui_try_resize(width, height)
            n.command('doautocmd VimResized')
            n.command('normal! gg')
            capture(n, output / f'workspace-{width}x{height}.png', width, height)
            data = n.exec_lua("local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()];return {lines=vim.api.nvim_buf_get_lines(c.buf,0,-1,false),items=c.items}")
            assert len(data['lines']) <= height - 2, f'{width} columns: home extends below the viewport'
            recent_row = next(i for i, line in enumerate(data['lines']) if 'Recent files' in line)
            git_row = next(i for i, line in enumerate(data['lines']) if 'Git workspace' in line)
            assert recent_row == git_row, 'main column headings must align'
            heat_rows = [line for line in data['lines'] if line.count('■') + line.count('□') == (52 if width == 166 else 39 if width == 120 else 26)]
            assert len(heat_rows) == 7, 'the entire adaptive graph must remain visible'
            assert any('History' in line for line in data['lines']), 'history action remains available'
            (output / f'workspace-{width}x{height}.json').write_text(json.dumps(data, indent=2))
            results.append({'width': width, 'height': height, 'lines': len(data['lines'])})
        for width, height in [(90, 40), (60, 34)]:
            n.ui_try_resize(width, height)
            n.command('doautocmd VimResized')
            n.command('normal! gg')
            capture(n, output / f'workspace-resize-{width}.png', width, height)
            data = n.exec_lua("local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()];return vim.api.nvim_buf_get_lines(c.buf,0,-1,false)")
            assert len(data) <= height - 2
            assert any('█' in line for line in data)
        n.ui_try_resize(166, 50)
        n.command('doautocmd VimResized')
        n.exec_lua("vim.fn.maparg('r','n',false,true).callback()")
        capture(n, output / 'workspace-keyboard.png', 166, 50)
        n.exec_lua("vim.fn.maparg('?','n',false,true).callback()")
        capture(n, output / 'workspace-help.png', 166, 50)
        n.exec_lua("vim.fn.maparg('<Esc>','n',false,true).callback()")
        n.exec_lua("vim.fn.maparg('<Esc>','n',false,true).callback()")
        n.command('colorscheme catppuccin-latte')
        n.command('doautocmd VimResized')
        capture(n, output / 'workspace-latte.png', 166, 50)
        groups = ['Normal', 'NormalFloat', 'ProjectHomeCanvas', 'ProjectHomeBackdrop', 'ProjectHomeWorkspaceSelected', 'ProjectHomeVoltKey']
        (output / 'latte-highlights.json').write_text(json.dumps({g:n.api.get_hl(0, {'name':g,'link':False}) for g in groups}, indent=2))
        assert n.api.get_hl(0, {'name':'ProjectHomeCanvas','link':False}).get('bg') is not None, 'Latte canvas survives theme change'
        n.command('colorscheme catppuccin-mocha')
        n.exec_lua("local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()];c.model.show_activity=false;c.render()")
        capture(n, output / 'workspace-no-activity.png', 166, 50)
        n.exec_lua("""local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]
          c.model=vim.deepcopy(visual_model);c.model.recents={c.model.recents[1]};c.model.prs.items={}
          c.render()""")
        capture(n, output / 'workspace-sparse.png', 166, 50)
        # Reproduce the user's split-screen density: five files, no PRs.
        n.exec_lua("""local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]
          c.model=vim.deepcopy(visual_model);c.model.name='cs285_deep_rl_berkley';c.model.branch='chore/ruff-fix'
          c.model.prs.items={};c.model.git.upstream=nil
          for i,d in ipairs(c.model.activity.days) do d.count=i%61==0 and 1 or 0 end
          c.model.root=vim.fn.expand('~/code/courses/cs285_deep_rl_berkley')
          c.model.recents={};for _,name in ipairs({'train.py','scratch.py','model.py','modal_train.py','logging_utils.py'}) do
            table.insert(c.model.recents,{path=c.model.root..'/hw1/src/hw1_imitation/'..name}) end
          c.render()""")
        for width, height in [(90, 50), (166, 50)]:
            n.ui_try_resize(width, height)
            n.command('doautocmd VimResized')
            n.command('normal! gg')
            capture(n, output / f'workspace-empty-{width}.png', width, height)
            assert n.current.window.cursor[0] <= height
            n.command('normal! G$')
            capture(n, output / f'workspace-footer-{width}.png', width, height)
            assert n.funcs.winsaveview()['leftcol'] == 0, 'footer navigation must not shift dashboard horizontally'
        n.exec_lua("""local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]
          for _,name in ipairs({'keymaps.lua','init.lua','options.lua','terminal.lua','README.md','session.lua'}) do
            table.insert(c.model.recents,{path=c.model.root..'/lua/custom/'..name}) end
          c.render()""")
        for width, height in [(90, 40), (166, 50)]:
            n.ui_try_resize(width, height)
            n.command('doautocmd VimResized')
            n.command('normal! gg')
            capture(n, output / f'workspace-recents-{width}.png', width, height)
        (output / 'mocha-highlights.json').write_text(json.dumps({g:n.api.get_hl(0, {'name':g,'link':False}) for g in groups}, indent=2))
        assert n.api.get_hl(0, {'name':'ProjectHomeCanvas','link':False}).get('bg') is not None, 'Mocha canvas survives round-trip theme change'
        print(json.dumps(results))
    finally:
        try:
            n.command('qa!')
        except (EOFError, OSError):
            pass
        n.close()
