local M = {}

function M.executable(name)
  local windows = vim.fn.has 'win32' == 1
  return vim.fs.joinpath(vim.fn.stdpath 'data', 'python', windows and 'Scripts' or 'bin', name .. (windows and '.exe' or ''))
end

function M.setup()
  -- Set this before any plugin probes the Python provider. Never use a project's
  -- interpreter here: the remote host is shared by every buffer in this process.
  if not vim.g.python3_host_prog and vim.fn.executable(M.executable 'python') == 1 then vim.g.python3_host_prog = M.executable 'python' end
  local data = vim.fs.joinpath(vim.fn.stdpath 'data', 'jupyter')
  local separator = vim.fn.has 'win32' == 1 and ';' or ':'
  vim.env.JUPYTER_PATH = data .. (vim.env.JUPYTER_PATH and separator .. vim.env.JUPYTER_PATH or '')
end

return M
