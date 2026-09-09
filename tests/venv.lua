vim.opt.rtp:prepend(vim.fn.getcwd())
local env = require 'custom.python.venv'
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
  vim.cmd.PyVenvReset()
  assert(env.python(root) == root .. '/.venv/bin/python')
  local name, spec = require('custom.python.notebook').kernel(root)
  assert(spec.argv[1] == root .. '/.venv/bin/python')
  assert(spec.argv[3] == root)
  assert(spec.env.VIRTUAL_ENV == root .. '/.venv')
  assert(name ~= require('custom.python.notebook').kernel(root .. '/src'))
  local stopped, started = {}, {}
  local original_get, original_start = vim.lsp.get_clients, vim.lsp.start
  vim.lsp.config('basedpyright', { cmd = { 'unused' } })
  vim.lsp.get_clients = function()
    return {
      { name = 'basedpyright', root_dir = root, attached_buffers = { [vim.api.nvim_get_current_buf()] = true }, stop = function() stopped.ours = true end },
      { name = 'ruff', root_dir = '/other/project', attached_buffers = {}, stop = function() stopped.other = true end },
    }
  end
  vim.lsp.start = function() started.ours = true end
  env.restart(root)
  assert(vim.wait(1000, function() return started.ours end))
  assert(stopped.ours and not stopped.other)
  vim.lsp.get_clients, vim.lsp.start = original_get, original_start
end, debug.traceback)
vim.fn.delete(root, 'rf')
assert(ok, err)
print 'PASS: nested .venv, overrides/reset, kernel isolation, scoped LSP restart'
