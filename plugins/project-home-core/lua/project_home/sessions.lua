local M = {}
local function in_root(path, root)
  path, root = vim.fs.normalize(path), vim.fs.normalize(root)
  return root == '/' and path:sub(1, 1) == '/' or path == root or path:sub(1, #root + 1) == root .. '/'
end
function M.capture(root)
  local count = 0
  local function walk(node)
    if node[1] == 'leaf' then
      local win = node[2]
      local buf = vim.api.nvim_win_get_buf(win)
      local path = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].buftype ~= '' or path == '' or not in_root(path, root) then return nil end
      count = count + 1
      return {
        kind = 'leaf',
        path = path,
        cursor = vim.api.nvim_win_get_cursor(win),
        width = vim.api.nvim_win_get_width(win),
        height = vim.api.nvim_win_get_height(win),
      }
    end
    local children = {}
    for _, child in ipairs(node[2]) do
      local saved = walk(child)
      if saved then children[#children + 1] = saved end
    end
    if #children == 0 then
      return nil
    elseif #children == 1 then
      return children[1]
    end
    local width, height = 0, 0
    for _, c in ipairs(children) do
      if node[1] == 'row' then
        width = width + (c.width or 1)
        height = math.max(height, c.height or 1)
      else
        height = height + (c.height or 1)
        width = math.max(width, c.width or 1)
      end
    end
    return { kind = node[1], children = children, width = width, height = height }
  end
  local tree = walk(vim.fn.winlayout())
  if not tree then return nil end
  return { tree = tree, count = count, saved_at = os.time(), root = root }
end
-- Persisted JSON is data, including when it was edited or partially corrupted.
function M.inspect(session, require_files, expected_root)
  if type(session) ~= 'table' or type(session.tree) ~= 'table' or type(session.root) ~= 'string' or session.root == '' or session.root:find '%z' then
    return nil, 'No valid saved workspace is available.'
  end
  if
    expected_root
    and (vim.uv.fs_realpath(session.root) or vim.fs.normalize(session.root)) ~= (vim.uv.fs_realpath(expected_root) or vim.fs.normalize(expected_root))
  then
    return nil, 'Saved workspace belongs to a different project.'
  end
  local result = { count = 0, files = {} }
  local function walk(node, depth)
    if type(node) ~= 'table' or depth > 16 then return false end
    if node.kind == 'leaf' then
      if
        type(node.path) ~= 'string'
        or node.path == ''
        or node.path:find '%z'
        or not in_root(node.path, session.root)
        or (require_files and vim.fn.filereadable(node.path) ~= 1)
      then
        return false
      end
      result.count = result.count + 1
      if result.count > 128 then return false end
      local cursor = type(node.cursor) == 'table' and tonumber(node.cursor[1]) or 1
      result.files[#result.files + 1] = { path = node.path, line = cursor and cursor == cursor and math.floor(math.max(1, math.min(cursor, 100000000))) or 1 }
      return true
    end
    if node.kind ~= 'row' and node.kind ~= 'col' then return false end
    if type(node.children) ~= 'table' or #node.children == 0 or #node.children > 20 then return false end
    for _, child in ipairs(node.children) do
      if not walk(child, depth + 1) then return false end
    end
    return true
  end
  if not walk(session.tree, 0) then return nil, 'Saved files are missing or the session is invalid. Your current windows are unchanged.' end
  local timestamp = tonumber(session.saved_at)
  result.saved_at = timestamp and timestamp == timestamp and math.max(0, math.min(timestamp, os.time())) or os.time()
  return result
end
function M.restore(session, opts)
  opts = opts or {}
  local info, err = M.inspect(session, true, opts.root)
  if not info then return false, err end
  if vim.fn.isdirectory(session.root) ~= 1 then return false, 'Saved project folder is unavailable.' end
  vim.cmd.tabnew()
  vim.cmd('tcd ' .. vim.fn.fnameescape(session.root))
  local function restore(node, win)
    vim.api.nvim_set_current_win(win)
    if node.kind == 'leaf' then
      local b = vim.fn.bufadd(node.path)
      vim.fn.bufload(b)
      vim.api.nvim_win_set_buf(win, b)
      for key, value in pairs(opts.window_options or {}) do
        pcall(function() vim.wo[win][key] = value end)
      end
      local pos = type(node.cursor) == 'table' and node.cursor or { 1, 0 }
      local row = tonumber(pos[1]) or 1
      if row ~= row then row = 1 end
      local line = math.floor(math.max(1, math.min(row, vim.api.nvim_buf_line_count(b))))
      local text = vim.api.nvim_buf_get_lines(b, line - 1, line, false)[1] or ''
      local col = tonumber(pos[2]) or 0
      if col ~= col then col = 0 end
      col = math.floor(math.max(0, math.min(col, #text)))
      pcall(vim.api.nvim_win_set_cursor, win, { line, col })
      return
    end
    local available = node.kind == 'row' and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win)
    local wins = { win }
    for i = 2, #node.children do
      vim.api.nvim_set_current_win(wins[#wins])
      vim.cmd(node.kind == 'row' and 'rightbelow vsplit' or 'rightbelow split')
      wins[i] = vim.api.nvim_get_current_win()
    end
    for i, c in ipairs(node.children) do
      restore(c, wins[i])
    end
    local total = tonumber(node.kind == 'row' and node.width or node.height)
    if total and total == total and total >= 1 and total < 10000000 then
      total = math.floor(total)
      for i = 1, #node.children - 1 do
        local child = node.children[i]
        local weight = tonumber(node.kind == 'row' and child.width or child.height) or 1
        if weight ~= weight or weight < 1 or weight > total then weight = 1 end
        local size = math.max(1, math.floor((available - #node.children + 1) * (weight or 1) / total))
        pcall(node.kind == 'row' and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height, wins[i], size)
      end
    end
  end
  restore(session.tree, vim.api.nvim_get_current_win())
  return true
end
return M
