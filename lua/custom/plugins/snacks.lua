---@module 'lazy'
---@type LazySpec
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    ---@module 'snacks'
    ---@type snacks.Config
    opts = {
      -- Only the image module is enabled. `snacks.nvim` is a collection of
      -- independent modules and every other one stays off, so this does not
      -- turn into a second plugin framework alongside kickstart.
      --
      -- Renders images, mermaid diagrams and latex math inline using the kitty
      -- graphics protocol, which ghostty supports natively.
      -- Requires `imagemagick`; mermaid additionally needs `mmdc` and math
      -- needs `typst`.
      image = { enabled = true },
    },
  },
}
