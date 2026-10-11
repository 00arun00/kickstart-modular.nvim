---@module 'lazy'
---@type LazySpec
return {
  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    opts = {
      -- Keep worklists available beside the source without opening automatically.
      focus = false,
      keys = {
        ['<C-t>'] = {
          action = function(view) require('custom.navigation.trouble').to_telescope(view) end,
          desc = 'Send filtered results to Telescope',
        },
        -- mini.surround owns the global s prefix.
        s = false,
        gs = {
          action = function(view)
            local current = view:get_filter 'severity'
            local severity = ((current and current.filter.severity or 0) + 1) % 5
            view:filter({ severity = severity }, {
              id = 'severity',
              template = '{hl:Title}Filter:{hl} {severity}',
              del = severity == 0,
            })
          end,
          desc = 'Cycle severity filter',
        },
      },
    },
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', desc = 'Diagnostics (Trouble)' },
      { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', desc = 'Buffer diagnostics (Trouble)' },
      { '<leader>xQ', '<cmd>Trouble qflist toggle<cr>', desc = 'Quickfix (Trouble)' },
      { '<leader>xL', '<cmd>Trouble loclist toggle<cr>', desc = 'Location list (Trouble)' },
      { '<leader>cl', '<cmd>Trouble lsp toggle win.position=right<cr>', desc = 'LSP results (Trouble)' },
      { '<leader>cs', '<cmd>Trouble symbols toggle<cr>', desc = 'Symbols (Trouble)' },
    },
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts)
      vim.list_extend(opts.spec, {
        { '<leader>x', group = 'Trouble' },
        { '<leader>c', group = 'Code' },
      })
    end,
  },
}
