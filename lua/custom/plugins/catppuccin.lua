---@module 'lazy'
---@type LazySpec
return {
  {
    'catppuccin/nvim',
    name = 'catppuccin',
    priority = 1000,
    config = function()
      require('catppuccin').setup {
        flavour = 'mocha',
        styles = {
          comments = {},
        },
        custom_highlights = function(colors)
          return {
            Folded = { bg = colors.mantle },
            FoldColumn = { fg = colors.overlay1, bg = colors.base },
            CursorLineFold = { fg = colors.lavender, bg = colors.base, bold = true },
            FoldSummary = { fg = colors.subtext0, bg = colors.mantle },
            DiagnosticError = { fg = colors.red },
            DiagnosticWarn = { fg = colors.peach },
            DiagnosticSignError = { fg = colors.red },
            DiagnosticSignWarn = { fg = colors.peach },
            NeoTreeNormal = { fg = colors.text, bg = colors.mantle },
            NeoTreeNormalNC = { fg = colors.text, bg = colors.mantle },
            NeoTreeRootName = { fg = colors.lavender, bold = true },
            NeoTreeCursorLine = { bg = colors.surface0 },
            NeoTreeIndentMarker = { fg = colors.surface1 },
            NeoTreeExpander = { fg = colors.overlay1 },
            NeoTreeTabActive = { fg = colors.lavender, bg = colors.surface0, bold = true },
            NeoTreeTabInactive = { fg = colors.subtext0, bg = colors.mantle },
            NeoTreeTabSeparatorActive = { fg = colors.mantle, bg = colors.mantle },
            NeoTreeTabSeparatorInactive = { fg = colors.mantle, bg = colors.mantle },
          }
        end,
      }
      vim.cmd.colorscheme 'catppuccin-mocha'
    end,
  },
}
