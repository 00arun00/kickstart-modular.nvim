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
      code = {
        -- Leave mermaid blocks alone so `snacks.nvim` can render the diagram.
        --
        -- `conceal_delimiters` hides the ``` fence lines, and snacks anchors a
        -- diagram's virtual lines to the closing fence. Virtual lines on a
        -- concealed line never render, so the diagram stayed invisible until
        -- the cursor landed on that line and anti-conceal revealed it again.
        disable = { 'mermaid' },
      },
    },
  },
}
