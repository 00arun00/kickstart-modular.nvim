-- Notebook cells are a navigation source, not a second parser/rendering layer.
local M = {}
local cache = {}
vim.api.nvim_create_autocmd('BufWipeout', {
  group = vim.api.nvim_create_augroup('notebook-navigation-cache', { clear = true }),
  callback = function(ev) cache[ev.buf] = nil end,
})

local function cells(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then return cache[buf].cells end
  local result = require('custom.python.cells_ui').scan(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, cell in ipairs(result) do
    if cell.kind == 'Code' then
      -- Jupytext writes metadata.title as free text before marker options.
      local title = lines[cell.first + 1]:gsub('^# %%%%%s*', '')
      local option = title:find '[%w_.%-]+%s*='
      local json = title:find('{', 1, true)
      local stop = math.min(option or #title + 1, json or #title + 1)
      title = vim.trim(title:sub(1, stop - 1):gsub('%[code%]', ''))
      if title ~= '' then cell.title = title end
    end
    if not cell.title then
      for row = cell.first + 2, cell.last + 1 do
        local text = lines[row]
        if text:find '%S' then
          -- A leading comment describes code; otherwise use its first line.
          text = text:gsub('^%s*# ?', '')
          if cell.kind ~= 'Code' then text = text:gsub('^#+%s+', '') end
          text = vim.trim(text)
          if text ~= '' then
            cell.title = text
            break
          end
        end
      end
    end
    if cell.title then cell.title = vim.fn.strcharpart(cell.title:gsub('%s+', ' '), 0, 60) end
  end
  cache[buf] = { tick = tick, cells = result }
  return result
end

function M.is_notebook(buf) return vim.bo[buf].filetype == 'python' and vim.api.nvim_buf_get_name(buf):match '%.ipynb$' ~= nil end

local function symbol(buf, win, all, index)
  local cell = all[index]
  local name = ('%02d %s'):format(index, cell.kind)
  if cell.title then name = name .. ' · ' .. cell.title end
  return require('dropbar.bar').dropbar_symbol_t:new(setmetatable({
    name = name,
    name_hl = 'PythonCell' .. cell.kind,
    buf = buf,
    win = win,
    sibling_idx = index,
    data = { notebook_cell = index },
    range = { start = { line = cell.first, character = 0 }, ['end'] = { line = cell.last + 1, character = 0 } },
  }, {
    __index = function(self, key)
      if key == 'siblings' then
        local siblings = {}
        for i in ipairs(all) do
          siblings[i] = symbol(buf, win, all, i)
        end
        self.siblings = siblings
        return siblings
      end
    end,
  }))
end

function M.get_symbols(buf, win, cursor)
  if not M.is_notebook(buf) then return {} end
  local all = cells(buf)
  for i, cell in ipairs(all) do
    if cursor[1] - 1 >= cell.first and cursor[1] - 1 <= cell.last then
      local result = { symbol(buf, win, all, i) }
      if cell.kind == 'Code' then
        local sources = require 'dropbar.sources'
        local scope = require('dropbar.utils').source.fallback { sources.lsp, sources.treesitter }
        for _, item in ipairs(scope.get_symbols(buf, win, cursor)) do
          -- Keep stale/out-of-cell LSP ranges from attaching the previous scope.
          if item.range and item.range.start.line > cell.first and item.range.start.line <= cell.last then table.insert(result, item) end
        end
      end
      return result
    end
  end
  return {}
end

function M.pick_cells()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  if not M.is_notebook(buf) then return vim.notify('Cell navigation is available in Python notebooks', vim.log.levels.INFO) end
  local all = cells(buf)
  if #all == 0 then return vim.notify('No notebook cells found', vim.log.levels.INFO) end
  local row, index = vim.api.nvim_win_get_cursor(win)[1] - 1, 1
  for i, cell in ipairs(all) do
    if row >= cell.first and row <= cell.last then index = i end
  end
  local bar = require('dropbar.utils').bar.get_current()
  if not bar then return vim.notify('Breadcrumbs are unavailable in this window', vim.log.levels.INFO) end
  local item = symbol(buf, win, all, index)
  item.bar, item.bar_idx = bar, 1
  bar:pick_mode_wrap(function() item:on_click() end)
end

return M
