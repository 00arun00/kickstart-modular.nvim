local M = {}
local directory = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))

-- Resolve runtime helpers beside this module, independent of the project cwd.
function M.helper(name) return vim.fs.joinpath(directory, 'helpers', name) end

return M
