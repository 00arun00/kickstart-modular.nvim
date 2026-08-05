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
      -- `doc.conceal` is left at its default, which conceals math only.
      --
      -- Concealing charts as well was tried and reverted: it does render the
      -- diagram in place of its source, but image rows beyond the source
      -- block's line count are attached as virt_lines to a line that conceal
      -- has just hidden, and those never render. A 6-line mermaid block needing
      -- ~20 rows is therefore truncated to 6. Confirmed by padding a block with
      -- comment lines until it was taller than its diagram - that one rendered
      -- in full while the unpadded one stayed clipped.
      --
      -- Math is small enough to fit inside its own block, which is why
      -- concealing it works and is the upstream default.
      image = { enabled = true },
    },
  },
}
