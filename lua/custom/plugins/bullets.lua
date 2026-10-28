---@module 'lazy'
---@type LazySpec
return {
  {
    'bullets-vim/bullets.nvim',
    version = '^1.0.1',
    ft = 'markdown',
    opts = {
      enabled_file_types = { 'markdown' },
      set_mappings = false,
      -- Match render-markdown.lua. Only the final character means complete.
      checkbox_markers = ' -/123>!?~x',
      -- Our task action updates ancestors without overwriting other states.
      nested_checkboxes = false,
      auto_indent_after_colon = false,
      pad_right = false,
    },
    config = function(_, opts)
      require('bullets').setup(opts)
      require('custom.markdown_lists').setup()
    end,
  },
}
