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
      { 'datsfilipe/vesper.nvim', opts = { italics = { comments = false, keywords = false, functions = false, strings = false, variables = false } } },
      { 'webhooked/kanso.nvim', opts = { italics = false, commentStyle = { italic = false }, keywordStyle = { italic = false } } },
      { 'vague-theme/vague.nvim', opts = { italic = false } },
      { 'kepano/flexoki-neovim', name = 'flexoki', main = 'flexoki', opts = {} },
      { 'thesimonho/kanagawa-paper', name = 'kanagawa-paper.nvim', branch = 'neovim', opts = {} },
      { 'savq/melange-nvim' },
      { 'nyoom-engineering/oxocarbon.nvim', build = false },
      { 'everviolet/nvim', name = 'evergarden', main = 'evergarden', opts = { cache = false } },
      { 'mellow-theme/mellow.nvim', init = function() vim.g.mellow_italic_comments = false end },
      { 'dgox16/oldworld.nvim', opts = {} },
      { 'ramojus/mellifluous.nvim', opts = {} },
      { 'olivercederborg/poimandres.nvim', opts = { disable_italics = true } },
      { 'EdenEast/nightfox.nvim', opts = {} },
      { '0xstepit/flow.nvim', opts = {} },
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
