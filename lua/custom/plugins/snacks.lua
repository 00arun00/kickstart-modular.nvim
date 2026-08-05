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
      -- Requires `imagemagick`. Latex math in markdown is compiled as a real
      -- latex document and rasterized through a pdf, so it needs both
      -- `tectonic` (or `pdflatex`) and `ghostscript`. `typst` is not involved:
      -- it only handles typst source files. Mermaid additionally needs `mmdc`.
      -- Run `:checkhealth snacks` to see which converters are missing.
      image = { enabled = true },
    },
  },
}
