-- Three local dashboard plugins share the same project data and actions.
-- Switch with :ProjectHome workspace|navigator|atelier or :ProjectHomeSelect.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h:h')
local specs = {
  {
    name = 'project-home-core',
    dir = root .. '/plugins/project-home-core',
    lazy = false,
    config = function()
      require('project_home').setup {
        default = vim.g.project_home_layout or 'workspace',
        remember_layout = vim.g.project_home_layout == nil,
        startup = vim.g.project_home_startup ~= false,
      }
    end,
  },
}

for _, layout in ipairs { 'workspace', 'navigator', 'atelier' } do
  specs[#specs + 1] = {
    name = 'project-home-' .. layout,
    dir = root .. '/plugins/project-home-' .. layout,
    lazy = false,
    dependencies = { 'project-home-core' },
    config = function() require('project_home_' .. layout).setup() end,
  }
end

return specs
