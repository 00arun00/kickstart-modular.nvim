local M = {}
M.render = function(...) return require('custom.project_home.volt.view').render(...) end
function M.setup()
  require('custom.project_home').register('volt', M.render)
  vim.api.nvim_create_user_command('ProjectHomeVolt', function() M.open() end, { force = true })
end
function M.open(opts)
  M.setup()
  return require('custom.project_home').open('volt', opts)
end
return M
