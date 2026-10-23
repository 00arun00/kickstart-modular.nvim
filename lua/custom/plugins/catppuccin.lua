---@module 'lazy'
---@type LazySpec
return {
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    dependencies = {
      { 'rose-pine/neovim', name = 'rose-pine', main = 'rose-pine', opts = { styles = { italic = false } } },
      { 'folke/tokyonight.nvim', main = 'tokyonight', opts = { styles = { comments = { italic = false } } } },
      { 'Shatur/neovim-ayu', main = 'ayu', opts = { overrides = { Comment = { italic = false } } } },
      { 'olimorris/onedarkpro.nvim', opts = { options = { cursorline = true } } },
    },
    config = function()
      require('catppuccin').setup {
        flavour = 'mocha',
        styles = { comments = {} },
      }
      require('custom.theme').setup()
      require('custom.fonts').setup()
      require('custom.theme').restore()
    end,
  },
}
