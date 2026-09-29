---@module 'lazy'
---@type LazySpec
return {
  {
    'chrisgrieser/nvim-origami',
    event = 'VeryLazy',
    opts = {
      -- Prefer LSP folds, falling back to Tree-sitter and then indentation.
      useLspFoldsWithTreesitterFallback = { enabled = true },
      autoFold = { enabled = false },
      -- Map only h/l below; preserve ordinary ^/$ motions.
      foldKeymaps = { setup = false, closeOnlyOnFirstColumn = false },
      -- Origami's search hook re-enables deliberately disabled folds, including
      -- special output windows. Native search opens the matched fold instead.
      pauseFoldsOnSearch = false,
      foldtext = {
        padding = { width = function(...) return require('custom.navigation.folds').padding(...) end },
        lineCount = { template = ' %d', hlgroup = 'FoldSummary' },
        diagnosticsCount = true,
        gitsignsCount = true, -- Toggle with <leader>zg.
        disableOnFt = { 'neo-tree', 'oil', 'help', 'lazy', 'mason', 'snacks_picker_input' },
      },
    },
    config = function(_, opts) require('custom.navigation.folds').setup(opts) end,
    keys = {
      { 'h', function() require('origami').h() end, desc = 'Move left; close fold at start of text or in indentation' },
      { 'l', function() require('origami').l() end, desc = 'Move right; open closed fold' },
      { '<leader>zf', function() require('custom.navigation.folds').focus() end, desc = 'Folds: focus code at cursor' },
      { '<leader>zp', function() require('custom.navigation.folds').preview() end, desc = 'Folds: preview closed fold (repeat to enter)' },
      { '<leader>zg', function() require('custom.navigation.folds').toggle_git() end, desc = 'Folds: toggle hidden Git changes' },
    },
  },
}
