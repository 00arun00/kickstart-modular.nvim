"""Smoke-test Home with this installed config, including Oil and Telescope.

Requires the user's existing plugin installation and Python with pynvim.
All test files, logs, state, and cache use a temporary directory. Mason's
unrelated automatic tool-install check is disabled in the test process so
opening the explicit-file fixture does not require registry network access.
"""
import os
from pathlib import Path
import tempfile
import time

import pynvim


def wait(fn, label):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if fn():
            return
        time.sleep(.05)
    raise AssertionError(label)


with tempfile.TemporaryDirectory(prefix='project-home-full-') as temp:
    root = Path(temp).resolve()
    (root / 'sample.txt').write_text('Full configuration startup check\n')
    os.environ['NVIM_LOG_FILE'] = str(root / 'nvim.log')
    os.environ['XDG_STATE_HOME'] = str(root / 'state')
    os.environ['XDG_CACHE_HOME'] = str(root / 'cache')
    os.chdir(root)
    for args in [[], [str(root)], [str(root / 'sample.txt')]]:
        installer_guard = "lua vim.api.nvim_create_autocmd('VimEnter',{once=true,callback=function() local m=package.loaded['mason-tool-installer']; if m then m.setup({run_on_start=false}) end end})"
        n = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-n', '-i', 'NONE', '--cmd', installer_guard, *args])
        try:
            expected = 'text' if args == [str(root / 'sample.txt')] else 'projecthome'
            wait(lambda: n.current.buffer.options['filetype'] == expected,
                 f'{args}: expected {expected}, current argv may be rewritten by Oil')
            # Allow deferred plugin events to finish before checking stability.
            time.sleep(.3)
            assert n.current.buffer.options['filetype'] == expected
            assert n.eval('g:colors_name') == 'catppuccin-mocha'
            if expected == 'projecthome':
                n.exec_lua("require('project_home').contexts[vim.api.nvim_get_current_buf()].dispatch('browse')")
                wait(lambda: n.current.buffer.options['filetype'] == 'oil', 'Browse opens Oil')
                n.command('ProjectHome navigator')
                wait(lambda: n.current.buffer.options['filetype'] == 'projecthome', 'Home returns from Oil')
                n.exec_lua("require('project_home').contexts[vim.api.nvim_get_current_buf()].dispatch('find')")
                wait(lambda: any(b.options['filetype'] == 'TelescopePrompt' for b in n.buffers), 'Find opens Telescope')
            assert not n.command_output('messages').strip(), n.command_output('messages')
            print('PASS full config:', args or ['no arguments'], flush=True)
        finally:
            try:
                n.command('qa!')
            except (EOFError, OSError):
                pass
            n.close()
