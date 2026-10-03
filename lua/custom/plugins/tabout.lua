---@module 'lazy'
---@type LazySpec
return {
  {
    'abecodes/tabout.nvim',
    -- Install the global mappings before Blink loads on VimEnter. Blink's
    -- snippet mappings then fall back to Tabout when no snippet jump is active.
    lazy = false,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {
      tabkey = '<Tab>',
      backwards_tabkey = '<S-Tab>',
      -- Blink handles completion and snippet navigation itself.
      completion = false,
    },
  },
}
