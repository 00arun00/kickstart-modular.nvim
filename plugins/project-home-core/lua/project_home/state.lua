local M = {}
local directory

function M.configure(opts) directory = opts and opts.directory or nil end

local function filename(root)
  local path = directory or (vim.fn.stdpath 'state' .. '/project-home')
  return path .. '/' .. vim.fn.sha256(vim.fs.normalize(root)) .. '.json', path
end

function M.get(root)
  local path = filename(root)
  local stat = vim.uv.fs_stat(path)
  if not stat then return {} end
  if stat.size > 2 * 1024 * 1024 then return {}, 'Project home state is too large' end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return {}, tostring(lines) end
  local parsed, data = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not parsed or type(data) ~= 'table' or data.version ~= 1 or data.root ~= vim.fs.normalize(root) or type(data.data) ~= 'table' then
    return {}, 'Invalid project home state'
  end
  return data.data
end

function M.set(root, data)
  if type(root) ~= 'string' or root == '' or type(data) ~= 'table' then return false, 'Invalid project state' end
  local path, dir = filename(root)
  local ok, result = pcall(function()
    vim.fn.mkdir(dir, 'p')
    local encoded = vim.json.encode { version = 1, root = vim.fs.normalize(root), data = data }
    if #encoded > 2 * 1024 * 1024 then error 'Project state exceeds 2 MiB' end
    local temp = path .. '.' .. vim.fn.getpid() .. '.' .. tostring(vim.uv.hrtime()) .. '.tmp'
    local fd, err = vim.uv.fs_open(temp, 'w', 384)
    if not fd then error(err) end
    local written, write_err = vim.uv.fs_write(fd, encoded, 0)
    vim.uv.fs_close(fd)
    if not written then
      vim.uv.fs_unlink(temp)
      error(write_err)
    end
    local moved, move_err = vim.uv.fs_rename(temp, path)
    if not moved then
      vim.uv.fs_unlink(temp)
      error(move_err)
    end
  end)
  return ok, ok and nil or tostring(result)
end

function M.update(root, key, value)
  local data = M.get(root)
  data[key] = value
  return M.set(root, data)
end

return M
