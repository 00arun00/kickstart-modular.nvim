-- One marker per variant: edits in different instances never overwrite another
-- variant's favorites. Same-variant edits follow the last completed action.
local M = {}

function M.directory() return vim.fn.stdpath 'state' .. '/theme-favorites' end

local function write(path, value)
  local temporary = path .. '.' .. vim.fn.getpid() .. '.' .. tostring(vim.uv.hrtime()) .. '.tmp'
  local ok, err = pcall(function()
    assert(vim.fn.writefile({ value }, temporary) == 0, 'Could not write theme preference')
    local renamed, failure = vim.uv.fs_rename(temporary, path)
    assert(renamed, failure)
  end)
  if not ok then
    vim.uv.fs_unlink(temporary)
    error(err)
  end
end

function M.read_scope()
  local ok, lines = pcall(vim.fn.readfile, vim.fn.stdpath 'state' .. '/theme-picker-view')
  local scope = ok and lines[1] or nil
  if scope == 'all' or scope == 'favorites' then return scope end
end

function M.save_scope(scope)
  assert(scope == 'all' or scope == 'favorites', 'Invalid theme picker view')
  vim.fn.mkdir(vim.fn.stdpath 'state', 'p')
  write(vim.fn.stdpath 'state' .. '/theme-picker-view', scope)
end

function M.read()
  if vim.fn.isdirectory(M.directory()) == 0 then return {} end
  local favorites = {}
  for _, name in ipairs(vim.fn.readdir(M.directory())) do
    if name:match '^[%w_-]+$' and vim.fn.filereadable(M.directory() .. '/' .. name) == 1 then favorites[name] = true end
  end
  return favorites
end

function M.set(name, enabled)
  assert(name:match '^[%w_-]+$', 'Invalid theme favorite ID')
  vim.fn.mkdir(M.directory(), 'p')
  local path = M.directory() .. '/' .. name
  if not enabled then
    local ok, err = vim.uv.fs_unlink(path)
    if not ok and vim.uv.fs_stat(path) then error(err) end
    return
  end
  write(path, name)
end

return M
