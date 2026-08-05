---@module 'lazy'
---@type LazySpec
return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      -- Rendering latex here would need `pylatexenc` and only produces unicode
      -- approximations. Math is left to `snacks.nvim`, which renders it as an
      -- actual image, so keeping this off avoids rendering formulas twice.
      latex = { enabled = false },
    },
  },
}
