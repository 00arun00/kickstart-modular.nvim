-- Provision the disposable CI editor. Never run against a personal installation.
local function setup()
  assert(vim.env.CI == 'true', 'This setup is only for disposable CI runners')
  vim.opt.rtp:prepend(vim.fn.getcwd())
  require('custom.python.host').setup()
  require 'lazy-bootstrap'
  require 'lazy-plugins'
  require('lazy').restore { wait = true, show = false }
  assert(not require('lazy.manage.checker').has_errors(), 'Lazy plugin installation failed')

  local lock = vim.json.decode(table.concat(vim.fn.readfile 'lazy-lock.json', '\n'))
  for name, plugin in pairs(require('lazy.core.config').plugins) do
    if plugin.url and lock[name] then
      local result = vim.system({ 'git', '-C', plugin.dir, 'rev-parse', 'HEAD' }, { text = true }):wait()
      assert(result.code == 0 and vim.trim(result.stdout) == lock[name].commit, 'Plugin revision mismatch: ' .. name)
    end
  end

  local parsers =
    { 'bash', 'c', 'cpp', 'diff', 'html', 'latex', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'python', 'query', 'regex', 'rust', 'vim', 'vimdoc', 'yaml' }
  require('nvim-treesitter').install(parsers):wait(300000)
  for _, parser in ipairs(parsers) do
    assert(vim.treesitter.language.add(parser), 'Parser installation failed: ' .. parser)
  end

  require('lazy').load { plugins = { 'mason.nvim', 'mason-lspconfig.nvim', 'mason-tool-installer.nvim' } }
  require('mason-tool-installer').setup { run_on_start = false }
  local registry = require 'mason-registry'
  local refreshed = false
  registry.refresh(function() refreshed = true end)
  assert(vim.wait(120000, function() return refreshed end), 'Mason registry refresh timed out')
  local tools = vim.json.decode(table.concat(vim.fn.readfile 'scripts/ci-tools.json', '\n'))
  for name, version in pairs(tools) do
    local package = registry.get_package(name)
    package:install { version = version }
    assert(vim.wait(300000, function() return not package:is_installing() end, 100), 'Mason installation timed out: ' .. name)
    assert(package:is_installed(), 'Mason installation failed: ' .. name)
  end

  vim.cmd 'runtime plugin/rplugin.vim'
  vim.cmd 'UpdateRemotePlugins'
  assert(vim.fn.filereadable(vim.fn.stdpath 'data' .. '/rplugin.vim') == 1, 'Remote-plugin manifest missing')
  print 'CI editor dependencies ready'
end

local ok, err = xpcall(setup, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
