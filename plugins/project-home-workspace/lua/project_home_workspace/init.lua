local M = {}
M.render = require('project_home_workspace.view').render
function M.setup() require('project_home').register('workspace', M.render) end
function M.open(opts)
  M.setup()
  require('project_home').open('workspace', opts)
end
return M
