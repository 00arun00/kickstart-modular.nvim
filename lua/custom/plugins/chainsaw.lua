---@module 'lazy'
---@type LazySpec
return {
  {
    'chrisgrieser/nvim-chainsaw',
    event = 'VeryLazy',
    opts = {
      marker = require('custom.chainsaw').marker,
    },
    config = function(_, opts)
      require('chainsaw').setup(opts)
      require('custom.chainsaw').setup { rich = true }
      -- Cover keymaps and :Chainsaw removeLogs with the same cleanup behavior.
      require('chainsaw.core.log-commands').removeLogs = require('custom.navigation.logs').remove
    end,
    -- Actions use the current language's templates; not every action has a
    -- built-in template for every language. N/V actions also accept selections.
    keys = {
      { '<leader>lv', function() require('chainsaw').variableLog() end, mode = { 'n', 'x' }, desc = 'Log: string / display' },
      { '<leader>lr', function() require('chainsaw').reprLog() end, mode = { 'n', 'x' }, desc = 'Log: representation' },
      { '<leader>lo', function() require('chainsaw').objectLog() end, mode = { 'n', 'x' }, desc = 'Log: object' },
      { '<leader>ly', function() require('chainsaw').typeLog() end, mode = { 'n', 'x' }, desc = 'Log: type' },
      { '<leader>la', function() require('chainsaw').assertLog() end, mode = { 'n', 'x' }, desc = 'Log: assertion' },
      { '<leader>lt', function() require('chainsaw').timeLog() end, desc = 'Log: start/stop timer' },
      { '<leader>ls', function() require('chainsaw').stacktraceLog() end, desc = 'Log: stack trace' },
      { '<leader>lb', function() require('custom.chainsaw-dap').toggle_breakpoint() end, desc = 'Log: debugger breakpoint' },
      { '<leader>le', function() require('chainsaw').emojiLog() end, desc = 'Log: execution breadcrumb' },
      { '<leader>lm', function() require('chainsaw').messageLog() end, desc = 'Log: message' },
      { '<leader>lx', function() require('chainsaw').removeLogs() end, mode = { 'n', 'x' }, desc = 'Log: remove marked lines' },
      { '<leader>lf', function() require('custom.navigation.logs').find() end, desc = 'Log: find in project' },
      { '<leader>lj', function() require('custom.navigation.logs').jump(1) end, desc = 'Log: next marked line' },
      { '<leader>lk', function() require('custom.navigation.logs').jump(-1) end, desc = 'Log: previous marked line' },
    },
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts) vim.list_extend(opts.spec, { { '<leader>l', group = 'Logs', mode = { 'n', 'x' } } }) end,
  },
}
