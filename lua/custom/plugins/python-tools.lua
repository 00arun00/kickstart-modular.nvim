return {
  {
    'mfussenegger/nvim-dap',
    dependencies = { 'mfussenegger/nvim-dap-python', 'rcarriga/nvim-dap-ui', 'nvim-neotest/nvim-nio' },
    keys = {
      { '<F5>', function() require('dap').continue() end, desc = 'Debug: continue' },
      { '<F10>', function() require('dap').step_over() end, desc = 'Debug: step over' },
      { '<F11>', function() require('dap').step_into() end, desc = 'Debug: step into' },
      { '<F12>', function() require('dap').step_out() end, desc = 'Debug: step out' },
      { '<leader>db', function() require('dap').toggle_breakpoint() end, desc = 'Debug: breakpoint' },
      {
        '<leader>dB',
        function()
          vim.ui.input({ prompt = 'Breakpoint condition: ' }, function(value)
            if value then require('dap').set_breakpoint(value) end
          end)
        end,
        desc = 'Debug: conditional breakpoint',
      },
      { '<leader>dc', function() require('dap').continue() end, desc = 'Debug: continue' },
      { '<leader>dq', function() require('dap').terminate() end, desc = 'Debug: terminate' },
      { '<leader>du', function() require('dapui').toggle() end, desc = 'Debug: toggle UI' },
      { '<leader>de', function() require('dapui').eval() end, mode = { 'n', 'x' }, desc = 'Debug: evaluate expression' },
    },
    config = function()
      local dap, env = require 'dap', require 'custom.python.venv'
      require('dap-python').setup(require('custom.python.host').executable 'python', { include_configs = false })
      -- Explicit pythonPath also wins over a stale activated shell environment.
      dap.configurations.python = {
        {
          type = 'python',
          request = 'launch',
          name = 'Python: current file',
          program = '${file}',
          pythonPath = function() return env.python(env.here()) end,
          cwd = function() return env.root(env.here()) end,
          console = 'integratedTerminal',
          justMyCode = true,
        },
        {
          type = 'python',
          request = 'launch',
          name = 'Python: pytest current file',
          module = 'pytest',
          args = { '${file}', '-v' },
          pythonPath = function() return env.python(env.here()) end,
          cwd = function() return env.root(env.here()) end,
          console = 'integratedTerminal',
          justMyCode = false,
        },
      }
      require('dapui').setup()
      require('custom.chainsaw.dap').setup(dap)
      dap.listeners.after.event_initialized['python-ui'] = function() require('dapui').open() end
      dap.listeners.before.event_terminated['python-ui'] = function() require('dapui').close() end
      dap.listeners.before.event_exited['python-ui'] = function() require('dapui').close() end
    end,
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts) vim.list_extend(opts.spec, { { '<leader>d', group = 'debug' } }) end,
  },
}
