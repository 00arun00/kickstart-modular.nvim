vim.opt.rtp:prepend(vim.fn.getcwd())
local env = require 'custom.python.venv'
local original_cwd = vim.fn.getcwd()
local root = vim.fn.tempname() .. ' space'
local function executable(path)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, path)
  vim.fn.setfperm(path, 'rwxr-xr-x')
end
local ok, err = xpcall(function()
  vim.fn.mkdir(root .. '/src/pkg', 'p')
  vim.fn.writefile({}, root .. '/pyproject.toml')
  executable(root .. '/.venv/bin/python')
  executable(root .. '/.venv/bin/ruff')
  assert(env.python(root .. '/src/pkg') == root .. '/.venv/bin/python')
  assert(env.ruff(root .. '/src/pkg') == root .. '/.venv/bin/ruff')
  executable(root .. '/src/.venv/bin/python')
  assert(env.python(root .. '/src/pkg') == root .. '/src/.venv/bin/python')
  executable(root .. '/alternate/bin/python')
  vim.cmd.edit(vim.fn.fnameescape(root .. '/main.py'))
  vim.cmd.PyVenvSet(root .. '/alternate')
  assert(env.python(root) == root .. '/alternate/bin/python')
  -- A fresh module (another editor session) and a symlink share the selection.
  package.loaded['custom.python.venv'] = nil
  env = require 'custom.python.venv'
  assert(env.python(root) == root .. '/alternate/bin/python')
  local alias = root .. '-link'
  assert(vim.uv.fs_symlink(root, alias))
  assert(env.python(alias) == root .. '/alternate/bin/python')
  vim.fn.delete(alias)
  vim.fn.delete(root .. '/alternate/bin/python')
  local valid, failure = pcall(env.python, root)
  assert(not valid and failure:find 'PyVenvReset', 'stale selections must not silently fall back')
  vim.cmd.PyVenvReset()
  assert(env.python(root) == root .. '/.venv/bin/python')
  executable(root .. '/alternate/bin/python')
  local original_select, original_input = vim.ui.select, vim.ui.input
  local choose
  vim.ui.select = function(items, _, callback)
    assert(vim.tbl_contains(items, root .. '/alternate'))
    assert(vim.tbl_contains(items, root .. '/.venv'))
    choose = callback
  end
  vim.cmd.PyVenvSet()
  choose(nil)
  assert(env.python(root) == root .. '/.venv/bin/python', 'cancelling must preserve selection')
  -- Picker callbacks must retain the originating project even after a buffer switch.
  vim.cmd.edit(vim.fn.fnameescape(root .. '/src/main.py'))
  choose(root .. '/alternate')
  assert(env.python(root) == root .. '/alternate/bin/python')
  assert(env.python(root .. '/src') == root .. '/src/.venv/bin/python')
  vim.cmd.edit(vim.fn.fnameescape(root .. '/main.py'))
  vim.ui.input = function(_, callback) callback(root .. '/.venv') end
  choose 'Enter another environment path…'
  assert(env.python(root) == root .. '/.venv/bin/python')
  vim.ui.select, vim.ui.input = original_select, original_input
  vim.cmd.PyVenvReset()
  -- Load the module from a project cwd: helper lookup must follow the checkout.
  vim.fn.chdir(root)
  local name, spec = require('custom.python.notebook').kernel(root)
  assert(spec.argv[1] == root .. '/.venv/bin/python')
  assert(vim.fn.filereadable(spec.argv[2]) == 1, 'Kernel launcher must exist outside the project cwd')
  assert(spec.argv[3] == root)
  assert(spec.env.VIRTUAL_ENV == root .. '/.venv')
  assert(name ~= require('custom.python.notebook').kernel(root .. '/src'))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    '# ---',
    '# jupyter: metadata',
    '# ---',
    '# %% [markdown]',
    '# hello',
    '# %%',
    'print(1)',
    '',
    '# %% [raw]',
    'not Python!',
    '# %%',
    'print(2)',
  })
  local cells = require('custom.python.notebook').cells()
  assert(#cells == 2 and cells[1][1] == 7 and cells[2][1] == 12)
  assert(cells[1][2] == 7 and cells[1][4] == 9)
  local stopped, started = {}, {}
  local original_get, original_start = vim.lsp.get_clients, vim.lsp.start
  vim.lsp.config('basedpyright', { cmd = { 'unused' } })
  vim.lsp.get_clients = function()
    return {
      { name = 'basedpyright', root_dir = root, attached_buffers = { [vim.api.nvim_get_current_buf()] = true }, stop = function() stopped.ours = true end },
      { name = 'ruff', root_dir = '/other/project', attached_buffers = {}, stop = function() stopped.other = true end },
    }
  end
  vim.lsp.start = function(config)
    assert(config.root_dir == root)
    started.ours = true
  end
  env.restart(root)
  assert(vim.wait(1000, function() return started.ours end))
  assert(stopped.ours and not stopped.other)
  vim.lsp.get_clients, vim.lsp.start = original_get, original_start
end, debug.traceback)
vim.fn.chdir(original_cwd)
vim.fn.delete(root, 'rf')
assert(ok, err)
print 'PASS: nested .venv, overrides/reset, kernel isolation, scoped LSP restart'
