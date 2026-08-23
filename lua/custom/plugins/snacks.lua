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
      -- Renders images, mermaid diagrams and latex math inline using the kitty
      -- graphics protocol, which ghostty supports natively.
      -- Requires `imagemagick`. Latex math in markdown is compiled as a real
      -- latex document and rasterized through a pdf, so it needs both
      -- `tectonic` (or `pdflatex`) and `ghostscript`. `typst` is not involved:
      -- it only handles typst source files. Mermaid additionally needs `mmdc`.
      -- Run `:checkhealth snacks` to see which converters are missing.
      image = {
        enabled = true,
        doc = {
          -- Conceal charts as well as math, so a mermaid diagram is rendered
          -- in place of its source and the source returns when the cursor
          -- moves into it.
          --
          -- This truncated diagrams on the first attempt, but that was caused
          -- by render-markdown concealing the ``` fence lines: virtual lines
          -- anchored to a concealed line never render. It now skips mermaid
          -- blocks entirely (`code.disable`), so the fences stay real.
          --
          -- Image links are left unconcealed so `![alt](path)` stays readable.
          ---@param _ string tree-sitter language
          ---@param type snacks.image.Type
          conceal = function(_, type) return type == 'math' or type == 'chart' end,
        },
      },

      lazygit = {
        configure = true,
      },

      -- Only the `image` and `notifier` modules are enabled.
      -- `snacks.nvim` is a collection of independent modules and
      -- every other one stays off, so this does not
      -- turn into a second plugin framework alongside kickstart.
      notifier = { enabled = true },
    },
    keys = {
      { '<leader>gg', function() Snacks.lazygit() end, desc = 'Toggle Lazygit' },
      { '<leader>gf', function() Snacks.lazygit.log_file() end, desc = 'LazyGit Current File History' },
    },
  },
}
