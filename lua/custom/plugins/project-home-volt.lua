local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
return {
  name = 'project-home-volt',
  dir = root .. '/plugins/project-home-volt',
  lazy = false,
  dependencies = { 'project-home-core', { 'nvzone/volt', commit = '620de1321f275ec9d80028c68d1b88b409c0c8b1' } },
  config = function() require('project_home_volt').setup() end,
}
