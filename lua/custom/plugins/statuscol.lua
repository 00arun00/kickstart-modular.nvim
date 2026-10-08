---@module 'lazy'
---@type LazySpec
return {
  {
    'luukvbaal/statuscol.nvim',
    lazy = false,
    config = function() require('custom.navigation.statuscolumn').setup() end,
  },
}
