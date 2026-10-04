-- The dashboard implementation lives in custom.project_home; Volt renders it.
return {
  'nvzone/volt',
  commit = '620de1321f275ec9d80028c68d1b88b409c0c8b1',
  lazy = false,
  config = function()
    require('custom.project_home.volt').setup()
    require('custom.project_home').setup {
      default = 'volt',
      startup = vim.g.project_home_startup ~= false,
    }
  end,
}
