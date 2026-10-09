---@module 'lazy'
---@type LazySpec
return {
  {
    'nvim-neotest/neotest',
    ft = 'python',
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
        function() require('neotest').project.run(require('custom.python.venv').root(require('custom.python.venv').here())) end,
        desc = 'Tests: test project',
      },
      { '<leader>td', function() require('neotest').run.run { strategy = 'dap' } end, desc = 'Tests: debug nearest test' },
      { '<leader>ts', function() require('neotest').summary.toggle() end, desc = 'Tests: test summary' },
      { '<leader>to', function() require('neotest').output.open { short = true, enter = true, auto_close = true } end, desc = 'Tests: test output' },
      { '<leader>tO', function() require('neotest').output_panel.toggle() end, desc = 'Tests: test output panel' },
      { '<leader>tx', function() require('neotest').run.stop() end, desc = 'Tests: stop test' },
      { '<leader>tl', function() require('neotest').run.run_last() end, desc = 'Tests: rerun last test' },
    },
    opts = function()
      local env = require 'custom.python.venv'
      local adapter = require 'neotest-python' {
        python = function(root) return env.python(root) end,
        dap = { justMyCode = false },
      }
      -- unittest resolves module names from cwd, including when the editor
      -- was opened in a different project. Apply the same cwd to debugging.
      local build_spec = adapter.build_spec
      adapter.build_spec = function(args)
        local position = args.tree:data()
        if position.type == 'dir' then
          local root = adapter.root(position.path) or vim.fn.getcwd()
          if require('neotest-python.base').get_runner { env.python(root) } == 'unittest' then
            -- unittest discovery skips non-package subdirectories on Python 3.11.
            -- Let Neotest run its discovered files instead of rediscovering them.
            return nil
          end
        end
        local spec = build_spec(args)
        spec.cwd = adapter.root(args.tree:data().path) or vim.fn.getcwd()
        if type(spec.strategy) == 'table' then spec.strategy.cwd = spec.cwd end
        return spec
      end
      return {
        icons = { passed = '', failed = '' },
        highlights = { passed = 'DiagnosticOk', failed = 'DiagnosticError' },
        status = { signs = true, virtual_text = false },
        summary = { mappings = { short = { 'o', 'O', 'K', '<leader>to' }, output = 'go', prev_failed = '[f', next_failed = ']f' } },
        adapters = { adapter },
        consumers = {
          navigation = require 'custom.navigation.tests',
          output_style = require 'custom.navigation.test_output',
          project = function(client)
            return {
              run = require('nio').create(function(root)
                -- Neotest has no public refresh consumer. Await discovery before
                -- running so files added outside the editor join this run too.
                root = vim.uv.fs_realpath(root) or root
                client:get_adapters() -- Ensure the client is started before registering this root.
                client:_update_adapters(root)
                -- Environment roots (e.g. a nested .venv) need not be adapter roots.
                local adapter_id = client:get_adapter(adapter.root(root) or root)
                if not adapter_id then return vim.notify('No test adapter found for ' .. root, vim.log.levels.WARN) end
                client:_update_positions(root, { adapter = adapter_id })
                require('neotest').run.run { root, adapter = adapter_id }
              end, 1),
            }
          end,
        },
      }
    end,
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts) vim.list_extend(opts.spec, { { '<leader>t', group = 'Tests' } }) end,
  },
}
