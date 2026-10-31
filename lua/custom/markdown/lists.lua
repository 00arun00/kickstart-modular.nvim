local M = {}

local function feed(keys) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'in', false) end

-- Check before inserting a newline: an empty line's column can otherwise
-- obscure its enclosing fence. Ignore injected languages inside code blocks.
local function in_code_block()
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, 'markdown'):parse()
    return vim.treesitter.get_node { ignore_injections = true }
  end)
  if not ok then return false end
  while node do
    if node:type() == 'fenced_code_block' or node:type() == 'indented_code_block' then return true end
    node = node:parent()
  end
  return false
end

local function is_checked(marker) return marker == 'x' or marker == 'X' end

local function split_item_text()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  if col >= #line then return false end
  local ok, item = pcall(function()
    vim.treesitter.get_parser(0, 'markdown'):parse()
    local node = vim.treesitter.get_node { ignore_injections = true }
    while node and node:type() ~= 'list_item' do
      node = node:parent()
    end
    return node
  end)
  if not ok or not item then return false end

  local first = item:start()
  local opening = vim.api.nvim_buf_get_lines(0, first, first + 1, false)[1]
  local prefix = opening:match '^%s*[-+*]%s+' or opening:match '^%s*%d+[.)]%s+'
  if not prefix then return false end
  -- Align task continuations with the task text, after the checkbox as well.
  local checkbox = opening:sub(#prefix + 1):match '^%[[^%]]%]%s+'
  if checkbox then prefix = prefix .. checkbox end
  if row == first + 1 and col < #prefix then return false end

  local indent = string.rep(' ', vim.fn.strdisplaywidth(prefix))
  local before = line:sub(1, col):gsub('%s+$', '')
  local after = line:sub(col + 1):gsub('^%s+', '')
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { before, indent .. after })
  vim.api.nvim_win_set_cursor(0, { row + 1, #indent })
  return true
end

-- Use Markdown's parsed nesting, rather than a fixed indentation width. This
-- also excludes examples in fences and supports multi-paragraph list items.
local function task_tree()
  local root = vim.treesitter.get_parser(0, 'markdown'):parse()[1]:root()
  local tasks = {}
  local function visit(node, parent)
    if node:type() == 'fenced_code_block' or node:type() == 'indented_code_block' then return end
    if node:type() == 'list_item' then
      local row = node:start()
      local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
      local prefix, marker, suffix = line:match '^(%s*[-+*]%s+%[)(.)(%].*)$'
      if not prefix then
        prefix, marker, suffix = line:match '^(%s*%d+[.)]%s+%[)(.)(%].*)$'
      end
      if prefix and (require('bullets.config').options.checkbox_markers:find(marker, 1, true) or is_checked(marker)) then
        local task = { row = row, prefix = prefix, marker = marker, suffix = suffix, children = {}, parent = parent }
        if parent then table.insert(parent.children, task) end
        tasks[row] = task
        parent = task
      end
    end
    for child in node:iter_children() do
      visit(child, parent)
    end
  end
  visit(root)
  return tasks
end

function M.toggle_task()
  if in_code_block() then return end
  local ok, tasks = pcall(task_tree)
  if not ok then
    vim.notify('Task completion needs the Markdown Tree-sitter parser: ' .. tostring(tasks), vim.log.levels.WARN)
    return
  end
  local task = tasks[vim.api.nvim_win_get_cursor(0)[1] - 1]
  if not task then return end
  require('bullets.actions').toggle_checkbox()
  task.marker = is_checked(task.marker) and ' ' or 'x'
  task = task.parent
  while task do
    local complete = true
    for _, child in ipairs(task.children) do
      if not is_checked(child.marker) then complete = false end
    end
    local marker = complete and 'x' or (is_checked(task.marker) and ' ' or task.marker)
    if marker ~= task.marker then
      vim.cmd 'undojoin'
      vim.api.nvim_buf_set_lines(0, task.row, task.row + 1, false, { task.prefix .. marker .. task.suffix })
      task.marker = marker
    end
    task = task.parent
  end
end

function M.attach(buf)
  local function map(mode, lhs, rhs, desc, opts)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('force', { buffer = buf, silent = true, desc = desc }, opts or {}))
  end

  map('i', '<CR>', function()
    if in_code_block() then return feed '<CR>' end
    if split_item_text() then return end
    require('bullets.actions').insert_new_bullet()
  end, 'Markdown: continue list or insert newline')
  map('n', 'o', function()
    if in_code_block() then return feed 'o' end
    require('bullets.actions').insert_new_bullet()
  end, 'Markdown: open next list item')
  map('i', '<C-CR>', '<CR>', 'Markdown: plain newline')
  map('n', '<leader>ct', M.toggle_task, 'Markdown: toggle task completion')
  map('n', 'gN', function()
    if not in_code_block() then require('bullets.actions').renumber_list() end
  end, 'Markdown: renumber list')
  map('x', 'gN', ':RenumberSelection<CR>', 'Markdown: renumber selection')
end

function M.setup()
  local group = vim.api.nvim_create_augroup('custom-markdown-lists', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'markdown',
    callback = function(event) M.attach(event.buf) end,
  })
  if vim.bo.filetype == 'markdown' then M.attach(0) end
end

return M
