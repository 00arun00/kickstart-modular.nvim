local M = { ready = {} }
vim.api.nvim_create_autocmd('User', {
  pattern = 'MoltenKernelReady',
  group = vim.api.nvim_create_augroup('python-kernel-ready', { clear = true }),
  callback = function(event) M.ready[event.data.kernel_id] = true end,
})
local env = require 'custom.python.venv'
local config_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)))))

-- Each project/interpreter pair gets a private kernelspec. Never register a
-- generic python3 kernel or infer an interpreter from notebook metadata.
function M.kernel(path)
  local root = env.root(path)
  local python = env.python(path)
  local name = 'nvim-' .. vim.fn.sha256(root .. '\n' .. python):sub(1, 16)
  local spec = {
    argv = { python, vim.fs.joinpath(config_root, 'scripts', 'kernel-launch.py'), root, '-f', '{connection_file}' },
    display_name = 'Neovim: ' .. vim.fs.basename(root),
    language = 'python',
    env = { PATH = vim.fs.dirname(python) .. (vim.fn.has 'win32' == 1 and ';' or ':') .. (vim.env.PATH or '') },
  }
  if env.venv(path) then spec.env.VIRTUAL_ENV = env.venv(path) end
  return name, spec
end

function M.init()
  if #vim.fn.MoltenRunningKernels(true) > 0 then return vim.notify 'A kernel is already attached. Stop it with <leader>jq before switching environments.' end
  local path = env.here()
  local python = env.python(path)
  local result = vim.system({ python, '-c', 'import ipykernel' }, { text = true }):wait(10000)
  if result.code ~= 0 then
    return vim.notify('ipykernel is missing from ' .. python .. '\nIn your project run: uv add --dev ipykernel\nThen retry <leader>ji.', vim.log.levels.ERROR)
  end
  local name, spec = M.kernel(path)
  local dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'jupyter', 'kernels', name)
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ vim.json.encode(spec) }, vim.fs.joinpath(dir, 'kernel.json'))
  M.ready[name] = nil
  vim.cmd.MoltenInit { args = { name } }
end

-- Use exact cell spans: NotebookNavigator's Molten adapter adds a trailing
-- marker, and its run_all submits the whole document as a single cell.
function M.cells()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cells = {}
  local ok, parser = pcall(vim.treesitter.get_parser, 0, 'python')
  local tree = ok and parser:parse()[1] or nil
  local first, markdown = 1, false
  local function add(last)
    local start, limit = first, last
    while start <= last and (lines[start]:match '^%s*$' or lines[start]:match '^%s*#') do
      start = start + 1
    end
    while last >= start and lines[last]:match '^%s*$' do
      last = last - 1
    end
    if not markdown and start <= last then table.insert(cells, { start, last, 1, #lines[last] + 1, marker = math.max(1, first - 1), limit = limit }) end
  end
  for i, line in ipairs(lines) do
    local marker = line:match '^# %%%% ' or line == '# %%'
    if marker and tree then marker = tree:root():named_descendant_for_range(i - 1, 0, i - 1, #line):type() == 'comment' end
    if marker then
      add(i - 1)
      first, markdown = i + 1, line:find('[markdown]', 1, true) ~= nil or line:find('[raw]', 1, true) ~= nil
    end
  end
  add(#lines)
  return cells
end

function M.run(all, advance)
  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then return vim.notify('Initialize one project kernel with <leader>ji first', vim.log.levels.WARN) end
  if not M.ready[kernels[1]] then return vim.notify('Kernel is starting; wait for the ready notification', vim.log.levels.INFO) end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cells = M.cells()
  local current
  for i, cell in ipairs(cells) do
    if row >= cell.marker and row <= cell.limit then
      current = i
      break
    end
  end
  for i, cell in ipairs(cells) do
    if all or i == current then vim.fn.MoltenEvaluateRange(kernels[1], unpack(cell)) end
  end
  if advance then require('notebook-navigator').move_cell 'd' end
end

function M.restart()
  for _, kernel in ipairs(vim.fn.MoltenRunningKernels(true)) do
    M.ready[kernel] = nil
  end
  vim.cmd.MoltenRestart()
end

function M.import()
  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then return vim.notify('Initialize one project kernel first', vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(0):gsub('%.py$', '.ipynb')
  vim.cmd.MoltenImportOutput { args = { file, kernels[1] } }
end

function M.export()
  local file = vim.api.nvim_buf_get_name(0)
  if not file:match '%.ipynb$' then return vim.notify('Output export requires an .ipynb buffer', vim.log.levels.WARN) end
  vim.cmd.write()
  if vim.bo.modified then return vim.notify('Notebook save failed; outputs were not exported', vim.log.levels.ERROR) end
  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then return vim.notify('Attach exactly one kernel before exporting outputs', vim.log.levels.WARN) end
  vim.cmd.MoltenExportOutput { bang = true, args = { file, kernels[1] } }
  -- Molten writes externally; keep Jupytext's conflict detection in sync.
  vim.b.mtime = vim.uv.fs_stat(file).mtime
end

return M
