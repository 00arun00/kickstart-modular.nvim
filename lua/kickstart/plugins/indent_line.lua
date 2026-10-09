-- Add indentation guides even on blank lines

---@module 'lazy'
---@type LazySpec
return {
  'lukas-reineke/indent-blankline.nvim',
  -- Enable `lukas-reineke/indent-blankline.nvim`
  -- See `:help ibl`
  main = 'ibl',
  keys = {
    { '<leader>Ti', '<cmd>IBLToggle<CR>', desc = '[T]oggle [I]ndentation guides' },
  },
  ---@module 'ibl'
  ---@type ibl.config
  opts = {},
}
