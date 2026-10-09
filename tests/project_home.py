"""Actual Neovim integration journeys; all writes stay in temporary fixtures.

Run with a Python containing pynvim and Pillow:
  ~/.local/share/nvim/python/bin/python tests/project_home.py /tmp/project-home-review
Git is real. GitHub responses are controlled fixtures; no remote writes or network
are needed. Screenshots rasterize Neovim's actual redraw events.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import pynvim
from capture_grid import capture

repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/project-home-review')
output.mkdir(parents=True, exist_ok=True)
os.environ['NVIM_LOG_FILE'] = str(output / 'nvim.log')
checks = []


def wait(fn, label='condition', timeout=8):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(.025)
    raise AssertionError('Timed out: ' + label)


def check(value, label):
    assert value, label
    checks.append(label)


def close(n):
    try:
        n.command('qa!')
    except (EOFError, OSError):
        pass
    n.close()


with tempfile.TemporaryDirectory(prefix='project-home-') as temp:
    temp = Path(temp).resolve()
    project = temp / 'project'
    project.mkdir()

    def git(*args):
        return subprocess.run(['git', '-C', str(project), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    git('init', '-b', 'main')
    git('config', 'user.name', 'Home Test')
    git('config', 'user.email', 'owner@example.test')
    for name, text in {'README.md': '# Project\nA test guide.\n', 'init.lua': 'return { enabled = true }\n',
                       'lua/config.lua': 'local value = 1\nreturn value\n', 'docs/guide.md': '# Guide\n'}.items():
        path = project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    git('add', '.')
    git('commit', '-m', 'Initialize project home fixture')
    git('switch', '-c', 'feature/dashboard')
    (project / 'init.lua').write_text('return { enabled = false }\n')
    git('add', 'init.lua')
    (project / 'lua/config.lua').write_text('local value = 2\nreturn value\n')
    (project / 'notes.md').write_text('Untracked work\n')
    worktree = temp / 'project-main'
    git('worktree', 'add', str(worktree), 'main')
    git('remote', 'add', 'origin', 'https://github.com/example/project-home-fixture.git')
    os.environ['XDG_STATE_HOME'] = str(temp / 'xdg-state')
    boot = temp / 'init.lua'
    boot.write_text('''
vim.opt.swapfile=false
vim.opt.termguicolors=true
vim.opt.shortmess:append('I')
vim.opt.rtp:append(%s)
require('custom.project_home.state').configure({directory=%s})
-- The actual CLI argv and Git operations are separately provider-tested.
local provider=require('custom.project_home.providers')
provider.gh=function(_,args,cb)
  local result
  if args[1]=='api' then result='owner'
  elseif args[2]=='diff' then result='diff --git a/init.lua b/init.lua\\n-return true\\n+return false'
  elseif args[2]=='view' then
    result=vim.json.encode({number=tonumber(args[3]),title='Dashboard pull request '..args[3],body='A real workflow fixture.',headRefName='feature/dashboard',baseRefName='main',url='https://github.com/example/project/pull/'..args[3],statusCheckRollup={{name='Formatting',conclusion='FAILURE',detailsUrl='https://github.com/example/project/actions/runs/1'}},files={{path='init.lua'}}})
  else result=vim.json.encode({
    {number=42,title='Build project home',headRefName='feature/dashboard',reviewDecision='CHANGES_REQUESTED',author={login='owner'},statusCheckRollup={{name='Formatting',conclusion='FAILURE'}},reviewRequests={}},
    {number=39,title='Review documentation',headRefName='docs',reviewDecision='',author={login='maya'},statusCheckRollup={{name='Test',conclusion='SUCCESS'}},reviewRequests={{login='owner'}}},
    {number=37,title='Refine theme',headRefName='theme',isDraft=true,reviewDecision='',author={login='owner'},statusCheckRollup={},reviewRequests={}}}) end
  local cancelled=false
  vim.defer_fn(function()if not cancelled then cb(result)end end,35)
  return function()cancelled=true end
end
require('custom.project_home').setup({startup=true})
vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/volt'));require('custom.project_home.volt').setup()
vim.opt.rtp:append(vim.fn.expand('~/.local/share/nvim/lazy/catppuccin'))
local ok,theme=pcall(require,'catppuccin')
if ok then theme.setup({flavour='mocha',compile_path=vim.fn.stdpath('state')..'/project-home-test-cache'});vim.cmd.colorscheme('catppuccin-mocha') end
''' % (json.dumps(str(repo)), json.dumps(str(temp / 'state'))))



    def start(args=()):
        n = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-n', '-i', 'NONE', '-u', str(boot), *map(str, args)])
        return n

    oldcwd = Path.cwd()
    os.chdir(project)
    try:
        for args, expected in [((), 'projecthome'), ((project,), 'directory'), ((project / 'init.lua',), 'lua')]:
            n = start(args)
            try:
                wait(lambda: n.eval('v:vim_did_enter') == 1, 'VimEnter')
                if expected == 'projecthome':
                    wait(lambda: n.current.buffer.options['filetype'] == expected, 'startup dashboard')
                elif expected == 'directory':
                    time.sleep(.3)
                    check(n.current.buffer.options['filetype'] != 'projecthome', 'directory launch not intercepted')
                else:
                    check(Path(n.current.buffer.name) == project / 'init.lua', 'explicit file startup preserved')
                    check(n.current.buffer.options['filetype'] != 'projecthome', 'file launch not intercepted')
                checks.append('startup ' + ('noargs' if not args else str(args[0].name)))
            finally:
                close(n)

        n = start()
        try:
            n.ui_attach(120, 52, rgb=True, ext_linegrid=True)
            check(n.eval('g:colors_name') == 'catppuccin-mocha', 'Catppuccin actually loaded')

            def context(expr='ctx.model'):
                return n.exec_lua("local ctx=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()];return ctx and (" + expr + ')')

            def loaded():
                return context("not ctx.model.git.loading and ctx.model.prs.status~='loading' and ctx.model.activity.status~='loading'")

            def action(name, value=None):
                n.exec_lua("local a,v=...;local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()];assert(c,'not home');c.dispatch(a,v)", name, value)

            def lines():
                return '\n'.join(n.current.buffer[:])

            def home(layout='volt', root=project):
                n.exec_lua("local name,root=...;require('custom.project_home').open(name,{root=root})", layout, str(root))
                wait(loaded, 'provider load')

            wait(loaded, 'initial provider load')
            # Actual file visits create real recents; saved layout is separate.
            for path in ['README.md', 'init.lua', 'lua/config.lua', 'docs/guide.md']:
                n.command('edit ' + n.funcs.fnameescape(str(project / path)))
            n.command('vsplit ' + n.funcs.fnameescape(str(project / 'init.lua')))
            n.command('vertical resize 35')
            n.command('ProjectHomeSessionSave')
            home()
            check(len(context('ctx.model.recents')) >= 4, 'real project recents persisted')
            check(context('ctx.model.session.count') == 2, 'session separate from recents')
            for layout in ['volt']:
                home(layout)
                check(context('ctx.layout') == layout, layout + ' independently selectable')
                check('Recent files' in lines() or 'RECENT FILES' in lines(), layout + ' recent section')
                check('42' in lines() and '39' in lines() and '37' in lines(), layout + ' multiple PRs')
                pos = n.current.window.cursor
                check(any(i['line'] == pos[0] and i.get('col', 0) == pos[1] for i in context('ctx.items')),
                      layout + ' initially focuses an action')
                capture(n, output / (layout + '-catppuccin.png'), 120, 52)
                n.input('g')
                if layout == 'volt':
                    wait(lambda: context('ctx.keyboard_section') == 'git', 'g focuses Git section')
                    n.input('<CR>')
                wait(lambda: context('ctx.pages[#ctx.pages] and ctx.pages[#ctx.pages].live_action') == 'git', 'g opens changes')
                check('init.lua' in lines(), layout + ' actual working changes')
                capture(n, output / (layout + '-changes.png'), 120, 52)
                action('diff', 'init.lua')
                wait(lambda: 'enabled' in lines(), 'actual diff')
                before = n.current.window.cursor[0]
                n.input('j')
                wait(lambda: n.current.window.cursor[0] != before, 'j scrolls text view')
                checks.append(layout + ' diff keyboard scrolling')
                capture(n, output / (layout + '-diff.png'), 120, 52)
                action('home')
                action('prs')
                check('42' in lines() and '39' in lines() and '37' in lines(), layout + ' full PR list')
                capture(n, output / (layout + '-prs.png'), 120, 52)
                action('pr', 42)
                wait(lambda: 'Dashboard pull request' in lines(), 'PR detail')
                capture(n, output / (layout + '-pr.png'), 120, 52)
                action('pr_checks', 42)
                check('Formatting' in lines(), layout + ' PR checks')
                check(any(i['action'] == 'url' for i in context('ctx.items')), layout + ' check log links')
                pos = n.current.window.cursor
                focused = next((i for i in context('ctx.items') if i['line'] == pos[0] and i.get('col', 0) == pos[1]), None)
                check(focused and focused['action'] == 'url', layout + ' check view focuses log action')
                capture(n, output / (layout + '-checks.png'), 120, 52)
                action('pr_files', 42)
                wait(lambda: 'diff --git' in lines(), 'PR diff')
                checks.append(layout + ' PR diff view')
                capture(n, output / (layout + '-pr-diff.png'), 120, 52)
                action('home')
                action('worktrees')
                check(str(worktree) in lines(), layout + ' worktree list')
                capture(n, output / (layout + '-worktrees.png'), 120, 52)
                action('home')
                n.input('m')
                wait(lambda: 'Workspace actions' in lines(), '? opens More')
                check('activity' in lines().lower(), layout + ' activity visibility discoverable')
                check('choose layout' not in lines().lower(), 'retired layout chooser removed')
                capture(n, output / (layout + '-more.png'), 120, 52)
                action('home')
                action('activity', 'you')
                check(context('ctx.scope') == 'you', layout + ' author scope')
                action('history')
                wait(lambda: 'Initialize project' in lines(), 'history')
                commit = next(i['value'] for i in context('ctx.items') if i['action'] == 'commit')
                action('commit', commit)
                wait(lambda: 'diff --git' in lines(), 'commit detail')
                check('Initialize project home fixture' in lines(), layout + ' actual commit detail')
                capture(n, output / (layout + '-commit.png'), 120, 52)
                action('home')
                n.command('colorscheme habamax')
                accent = n.api.get_hl(0, {'name': 'ProjectHomeAccent', 'link': False})
                source = n.api.get_hl(0, {'name': 'Special', 'link': False})
                check(accent == source, layout + ' follows active theme')
                capture(n, output / (layout + '-habamax.png'), 120, 52)
                n.ui_try_resize(60, 52)
                n.command('doautocmd VimResized')
                capture(n, output / (layout + '-narrow.png'), 60, 52)
                n.ui_try_resize(120, 52)
                n.command('colorscheme morning')
                check(n.api.get_hl(0, {'name': 'ProjectHomeMuted', 'link': False}) ==
                      n.api.get_hl(0, {'name': 'Comment', 'link': False}), layout + ' light theme follows semantic colors')
                capture(n, output / (layout + '-light.png'), 120, 52)
                n.command('colorscheme catppuccin-mocha')
                n.exec_lua("""local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]
                  _G.ph_model=vim.deepcopy(c.model)
                  c.model.git.error='Permission denied fixture'; c.model.git.loading=false
                  c.model.prs.status='unavailable'; c.model.prs.error='Offline fixture'
                  c.model.activity.status='unavailable'; c.home()""")
                check('Git status unavailable' in lines() and 'Activity unavailable' in lines(),
                      layout + ' failed providers remain distinct from clean or zero')
                capture(n, output / (layout + '-unavailable.png'), 120, 52)
                n.exec_lua("""local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]
                  c.model=vim.deepcopy(ph_model); c.model.activity.identity=nil; c.scope='you'; c.home()""")
                check('user.email' in lines(), layout + ' missing identity has an explanation')
                capture(n, output / (layout + '-no-identity.png'), 120, 52)
                n.exec_lua("local c=require('custom.project_home').contexts[vim.api.nvim_get_current_buf()]; c.model=ph_model; c.home()")
            # Back navigation retains the correct PR-specific checks.
            home()
            action('pr', 42)
            wait(lambda: 'Dashboard pull request 42' in lines(), 'PR42')
            action('pr', 39)
            wait(lambda: 'Dashboard pull request 39' in lines(), 'PR39')
            action('back')
            action('pr_overview', 42)
            check('Dashboard pull request 42' in lines(), 'back navigation PR cache keyed by number')
            action('home')
            # Drive native input fallbacks through their UI callbacks.
            n.exec_lua("vim.ui.input=function(opts,cb)_G.ph_input={opts=opts,cb=cb}end")

            action('find')
            n.exec_lua("ph_input.cb('docs/guide.md')")
            check(Path(n.current.buffer.name) == project / 'docs/guide.md', 'find fallback opens project-relative file')
            check(n.current.buffer.options['buflisted'], 'opened project file is listed for test signs')
            home()
            action('search')
            n.exec_lua("ph_input.cb('local value')")
            wait(lambda: 'lua/config.lua:1' in lines(), 'search results')
            hit = next(i['value'] for i in context('ctx.items') if i['action'] == 'search_hit')
            action('search_hit', hit)
            check(Path(n.current.buffer.name) == project / 'lua/config.lua', 'search hit opens correct file')
            home()
            action('activity_visibility')
            check(context('ctx.model.show_activity') is False, 'activity can be hidden')
            action('activity_visibility')
            check(context('ctx.model.show_activity') is True, 'activity can be restored')
            action('new')
            n.exec_lua("ph_input.cb('nested/new.lua')")
            check(n.current.buffer.name.endswith('nested/new.lua'), 'new file opens intended buffer')
            check(not (project / 'nested/new.lua').exists(), 'new buffer not silently written')
            n.current.buffer[:] = ['-- unsaved new work']
            dirty = n.current.buffer.number
            home()
            action('worktree', str(worktree))
            wait(loaded, 'worktree load')
            check(Path(context('ctx.model.root')) == worktree.resolve(), 'switch resolves target worktree')
            check(n.buffers[dirty].options['modified'], 'switch preserves dirty buffer')
            check(len(context('ctx.model.git.changes')) == 0, 'target clean state is correct')
            home('volt', project)
            wait(lambda: Path(context('ctx.model.root')) == project.resolve(), 'explicit root switch')
            checks.append('explicit root option changes existing home context')
            tab = n.current.tabpage.handle
            tabs = len(n.tabpages)
            saved_tabs = len(context('ctx.model.session.tabs'))
            n.input('u')
            wait(lambda: n.current.buffer.options['filetype'] != 'projecthome', 'Resume restores immediately')
            check(all(t.handle != tab for t in n.tabpages) and len(n.tabpages) == tabs + saved_tabs - 1,
                  'Resume replaces dashboard tab and adds remaining project tabs')
            check(n.buffers[dirty].options['modified'], 'restore preserves dirty buffers')
            global_tabs = n.exec_lua("local s=require('custom.project_home.sessions');local snapshot=s.capture(vim.fn.getcwd(),{scope='global'});require('custom.project_home.state').update(s.global_key,'session',snapshot);return #snapshot.tabs")
            home()
            action('more')
            check('Resume last Neovim session' in lines() and 'replaces all current tabs' in lines(),
                  'More describes global restore scope')
            action('resume_global')
            check(len(n.tabpages) == global_tabs and n.current.buffer.options['filetype'] != 'projecthome',
                  'Global action restores complete saved tab layout')
            check(n.buffers[dirty].options['modified'], 'global action preserves dirty buffers')
        finally:
            close(n)
    finally:
        os.chdir(oldcwd)

(output / 'results.json').write_text(json.dumps({'checks': checks, 'passed': len(checks)}, indent=2))
print(f'Project home integration: {len(checks)} checks passed; screenshots in {output}')
