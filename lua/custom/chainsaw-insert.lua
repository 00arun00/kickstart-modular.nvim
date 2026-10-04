-- Insert already-rendered code without another round of template expansion.
local M = {}
local scoped_expressions = {
  lambda = true,
  list_comprehension = true,
  set_comprehension = true,
  dictionary_comprehension = true,
  generator_expression = true,
}
local function indent(lines, row) return (lines[row + 1] or ''):match '^%s*' end
local function after(node)
  local _, _, row, column = node:range()
  return column == 0 and row or row + 1
end

local function python_location(node, lines)
  while node do
    local kind = node:type()
    if scoped_expressions[kind] then return nil, nil, 'Logging inside a lambda or comprehension can lose its local scope; select a value outside it' end
    if kind == 'block' or kind == 'module' then return end
    if kind == 'function_definition' then
      -- A parameter selected in the signature is available inside the body.
      -- Preserve a leading docstring, even when the signature spans lines.
      local body = node:field('body')[1]
      local first
      if body then
        for child in body:iter_children() do
          if child:named() and child:type() ~= 'comment' then
            first = child
            break
          end
        end
      end
      if not first then return nil, nil, 'Complete the function body before inserting a log' end
      local start, column = first:start()
      if not lines[start + 1]:sub(1, column):match '^%s*$' then return nil, nil, 'Expand the inline function body before inserting a log' end
      local child = first:named_child(0)
      local docstring = first:type() == 'expression_statement' and child and child:type() == 'string'
      return docstring and after(first) or start, indent(lines, start)
    end
    local parent = node:parent()
    if parent and (parent:type() == 'block' or parent:type() == 'module') then
      if node:has_error() then return nil, nil, 'Complete the Python statement before inserting a log' end
      local start, column, last, end_column = node:range()
      local tail = end_column == 0 and '' or lines[last + 1]:sub(end_column + 1)
      if not lines[start + 1]:sub(1, column):match '^%s*$' or not (tail:match '^%s*$' or tail:match '^%s*#') then
        return nil, nil, 'Split shared-line Python statements before inserting a log'
      end
      if kind == 'return_statement' or kind == 'raise_statement' then return start, indent(lines, start) end
      -- Compound headers introduce/control scope; don't move a header-local
      -- expression to an unrelated location after the entire compound statement.
      if kind == 'expression_statement' or kind == 'assert_statement' then return after(node), indent(lines, start) end
      return nil, nil, 'Select an expression in a standalone statement or function body'
    end
    node = parent
  end
end

local function location(ft, lines, cursor)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, ft == 'nvim_lua' and 'lua' or ft):parse()
    return vim.treesitter.get_node { ignore_injections = true }
  end)
  local row = cursor[1]
  if not ok and ft == 'python' then return nil, nil, 'Python log insertion requires a Tree-sitter parser' end
  if ok and node then
    if ft == 'python' then
      local target, whitespace, err = python_location(node, lines)
      if target or err then return target, whitespace, err end
    else
      local shift = require('chainsaw.config.smart-insert-location').ftConfig[ft]
      if shift then row = row + (shift(node) or 0) end
    end
  end
  if row < 0 or row > #lines then return nil, nil, 'No valid insertion location' end
  -- Retain the upstream indentation heuristic for other languages and blanks.
  local whitespace = indent(lines, math.max(0, row - 1))
  for next_row = row + 1, #lines do
    if not lines[next_row]:match '^%s*$' then
      local next_indent = indent(lines, next_row - 1)
      if #next_indent > #whitespace then whitespace = next_indent end
      break
    end
  end
  return row, whitespace
end

function M.insert(source, ft)
  if source:find '[\r\n]' then
    vim.notify('The rendered log must be one source line', vim.log.levels.WARN)
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, whitespace, err = location(ft, lines, cursor)
  if not row then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end
  local rendered = whitespace .. source
  vim.api.nvim_buf_set_lines(0, row, row, false, { rendered })
  require('chainsaw.visuals.styling').addStylingToLine(row)
  vim.api.nvim_win_set_cursor(0, { row + 1, math.min(cursor[2], #rendered) })
  require('chainsaw.pre-commit-hook').install()
  return true
end
return M
