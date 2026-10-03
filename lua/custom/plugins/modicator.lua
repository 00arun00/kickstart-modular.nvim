---@module 'lazy'
---@type LazySpec
return {
  {
    'mawkler/modicator.nvim',
    event = 'VeryLazy',
    -- Set up the colorscheme and statusline before sampling their mode colors.
    dependencies = { 'catppuccin/nvim', 'nvim-lualine/lualine.nvim' },
    init = function()
      vim.o.termguicolors = true
      vim.o.cursorline = true
      vim.o.number = true
    end,
    opts = {
      integration = {
        lualine = { enabled = true, mode_section = 'a', highlight = 'bg' },
      },
    },
  },
}
