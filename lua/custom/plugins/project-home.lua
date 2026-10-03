-- Runtime shared by the Volt Workspace dashboard.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
return {
  name = 'project-home-core',
  dir = root .. '/plugins/project-home-core',
  lazy = false,
  config = function()
    require('project_home').setup {
      default = 'volt',
      startup = vim.g.project_home_startup ~= false,
    }
  end,
}
