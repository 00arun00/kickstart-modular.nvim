-- Existing Python assertions are statements, not variables under the cursor.
local M = {}
local suffix = ' # nvim-dbg-original: '

function M.existing()
  if vim.bo.filetype ~= 'python' then return end
  local mode = vim.fn.mode()
  if mode ~= 'n' and mode ~= 'v' and mode ~= 'V' then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local text = vim.trim(line)
  if not text:match '^assert%s' and not text:match '^assert%(' then return end
  if mode == 'v' or mode == 'V' then
    local selected = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = mode })
    -- Partial selections retain the ordinary expression workflow.
    if #selected ~= 1 or vim.trim(selected[1]) ~= text then return end
  end
  local ok, root = pcall(function() return vim.treesitter.get_string_parser(text, 'python'):parse()[1]:root() end)
  if not ok or root:has_error() then return end
  local statement = root:named_child(0)
  if not statement or statement:type() ~= 'assert_statement' then return end
  for index = 1, root:named_child_count() - 1 do
    if root:named_child(index):type() ~= 'comment' then return end
  end
  local condition = statement:named_child(0)
  local message = statement:named_child(1)
  if not condition then return end
  if mode ~= 'n' then vim.cmd.normal { '\27', bang = true } end
  return {
    condition = vim.treesitter.get_node_text(condition, text),
    message = message and vim.treesitter.get_node_text(message, text),
    row = row - 1,
    original = line,
  }
end

function M.replace(source, target)
  if vim.api.nvim_buf_get_lines(0, target.row, target.row + 1, false)[1] ~= target.original then
    vim.notify('Assertion cancelled: source changed', vim.log.levels.WARN)
    return false
  end
  local line = target.original:match '^%s*' .. source .. suffix .. vim.json.encode(target.original)
  vim.api.nvim_buf_set_lines(0, target.row, target.row + 1, false, { line })
  require('chainsaw.visuals.styling').addStylingToLine(target.row)
  return true
end

-- Persist the original so cleanup also works after reopening the file.
function M.original(line)
  local encoded = line:match ' # nvim%-dbg%-original: (.*)$'
  if not encoded then return end
  local ok, original = pcall(vim.json.decode, encoded)
  if ok and type(original) == 'string' and not original:find '[\r\n]' then return original end
end

return M
