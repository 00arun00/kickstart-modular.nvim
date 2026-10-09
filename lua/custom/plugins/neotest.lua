---@module 'lazy'
---@type LazySpec
return {
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-neotest/neotest-python',
      'nvim-neotest/nvim-nio',
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'mfussenegger/nvim-dap',
    },
    keys = {
      { '<leader>tn', function() require('neotest').run.run() end, desc = 'Tests: nearest test' },
      { '<leader>tf', function() require('neotest').run.run(vim.api.nvim_buf_get_name(0)) end, desc = 'Tests: test file' },
      {
        '<leader>ta',
        function() require('neotest').run.run(require('custom.python.venv').root(require('custom.python.venv').here())) end,
        desc = 'Tests: test project',
      },
      { '<leader>td', function() require('neotest').run.run { strategy = 'dap' } end, desc = 'Tests: debug nearest test' },
      { '<leader>ts', function() require('neotest').summary.toggle() end, desc = 'Tests: test summary' },
      { '<leader>to', function() require('neotest').output.open { enter = true, auto_close = true } end, desc = 'Tests: test output' },
      { '<leader>tO', function() require('neotest').output_panel.toggle() end, desc = 'Tests: test output panel' },
      { '<leader>tx', function() require('neotest').run.stop() end, desc = 'Tests: stop test' },
      { '<leader>tl', function() require('neotest').run.run_last() end, desc = 'Tests: rerun last test' },
    },
    opts = function()
      return {
        adapters = {
          require 'neotest-python' {
            python = function(root) return require('custom.python.venv').python(root) end,
            runner = 'pytest',
            dap = { justMyCode = false },
          },
        },
      }
    end,
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts) vim.list_extend(opts.spec, { { '<leader>t', group = 'Tests' } }) end,
  },
}
