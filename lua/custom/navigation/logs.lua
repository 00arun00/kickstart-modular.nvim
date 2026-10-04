local M = {}

local function marker() return require('chainsaw.config.config').config.marker end

local function empty_python_suite(node)
  if node:type() == 'block' then
    local statements = 0
    for child in node:iter_children() do
      if child:named() and child:type() ~= 'comment' then statements = statements + 1 end
    end
    if statements == 0 then return true end
  end
  for child in node:iter_children() do
    if empty_python_suite(child) then return true end
  end
  return false
end

-- Find a complete Python logging statement, including trailing marker comments.
-- Refuse shared lines (e.g. `work(); print(...)`) rather than delete user code.
local function python_range(root, lines, row, column)
  local node = root:named_descendant_for_range(row, column, row, column)
  if node:type() == 'comment' then
    local previous = node:prev_named_sibling()
    if not previous or previous:end_() ~= row then return end
    node = previous
  end
  while node do
    local kind = node:type()
    if kind == 'expression_statement' or kind == 'assert_statement' then break end
    if kind == 'block' or kind == 'module' then return end
    node = node:parent()
  end
  if not node or node:has_error() then return end
  local source = vim.treesitter.get_node_text(node, 0)
  local helper = source:match '^__import__%("runpy"%)%.run_path%s*%(' and source:find('nvim_debug.py', 1, true)
  if helper and source:match '%[%s*"fail"%s*%]' then
    local block = node:parent()
    local parent = block and block:parent()
    if not parent or parent:type() ~= 'if_statement' or block:named_child_count() ~= 1 then return end
    local parent_source = vim.treesitter.get_node_text(parent, 0)
    if not parent_source:match '^if not ' or parent:field('alternative')[1] then return end
    node = parent
  end
  if node:type() == 'expression_statement' then
    local child = node:named_child(0)
    local allowed_call = child and child:type() == 'call' and (source:match '^print%s*%(' or source:match '^breakpoint%s*%(')
    local timer = source:match '^nvim_dbg_start_%d+%s*=%s*__import__%("time"%)%.perf_counter%(%s*%)'
    -- Recognize old generated timer assignments, but not arbitrary assignments
    -- containing a marker (e.g. prefix = "[debug]").
    local old_timer = source:match '^timelog_start_%d+%s*=%s*time%.perf_counter%(%s*%)'
    local old_stack = source:match '^__import__%("traceback"%)%.print_stack%(%s*%)'
    if not (allowed_call or timer or old_timer or old_stack or helper) then return end
  end
  local first, start_col, last, end_col = node:range()
  if end_col == 0 then
    last = last - 1
    end_col = #lines[last + 1]
  end
  local before, after = lines[first + 1]:sub(1, start_col), lines[last + 1]:sub(end_col + 1)
  if not before:match '^%s*$' or not (after:match '^%s*$' or after:match '^%s*#') then return end
  return first, last + 1
end

-- C++/Rust parsers are optional here. Only recognize our emitted statement
-- families, then balance delimiters/quotes to remove the complete statement.
-- Unknown/raw-string syntax is deliberately left untouched.
local function compiled_ranges(lines, ft)
  local ranges = {}
  for first, line in ipairs(lines) do
    local candidate
    if ft == 'rust' then
      candidate = line:match '^%s*eprintln!%s*%(' or line:match '^%s*assert!%s*%(' or line:match '^%s*let nvim_dbg_start_%d+%s*='
    else
      candidate = line:match '^%s*std::cerr%s*<<'
        or line:match '^%s*std::cerr%s*$'
        or line:match '^%s*assert%s*%('
        or line:match '^%s*auto nvim_dbg_start_%d+%s*='
    end
    local rich_block = line:match '^%s*if%s*[%(!]' or (ft == 'rust' and line:match '^%s*{')
    candidate = candidate or rich_block or (ft == 'cpp' and line:match '^%s*nvim_dbg::[%w_]+%s*%(')
    if candidate then
      local brackets, quoted, escaped, done, invalid = {}, nil, false, false, false
      for last = first, #lines do
        local current = lines[last]
        local i = 1
        while i <= #current do
          local char = current:sub(i, i)
          if quoted then
            if escaped then
              escaped = false
            elseif char == '\\' then
              escaped = true
            elseif char == quoted then
              quoted = nil
            end
          elseif current:sub(i):match '^r#*"' or current:sub(i):match '^R"' or current:sub(i, i + 1) == '/*' then
            invalid = true
            break
          elseif current:sub(i, i + 1) == '//' then
            break
          elseif char == '"' or char == "'" then
            quoted = char
          elseif char:find '[%(%[%{]' then
            brackets[#brackets + 1] = char
          elseif char:find '[%)%]%}]' then
            local expected = ({ [')'] = '(', [']'] = '[', ['}'] = '{' })[char]
            if table.remove(brackets) ~= expected then
              invalid = true
              break
            end
            if char == '}' and #brackets == 0 and rich_block then
              local tail = current:sub(i + 1)
              if not (tail:match '^%s*$' or tail:match '^%s*//') then invalid = true end
              done = true
              break
            end
          elseif char == ';' and #brackets == 0 then
            local tail = current:sub(i + 1)
            if not (tail:match '^%s*$' or tail:match '^%s*//') then invalid = true end
            done = true
            break
          end
          i = i + 1
        end
        if invalid then break end
        if done then
          local source = table.concat(vim.list_slice(lines, first, last), '\n')
          if rich_block then
            local body = source:match '{(.*)}'
            if not body then break end
            if ft == 'rust' then body = body:gsub('^%s*#%[path%s*=%s*".-"%]%s*mod%s+nvim_dbg%s*;', '') end
            -- A generated wrapper contains exactly one helper call; never erase
            -- neighboring application statements in a containing block.
            if not body:match '^%s*nvim_dbg::[%w_]+%b()%s*;%s*$' then break end
          end
          for row = first - 1, last - 1 do
            if not ranges[row] then ranges[row] = { first - 1, last } end
          end
          break
        end
      end
    end
  end
  return ranges
end

local function lua_range(root, lines, row, column)
  local node = root:named_descendant_for_range(row, column, row, column)
  if node:type() == 'comment' then
    local previous = node:prev_named_sibling()
    if not previous or previous:end_() ~= row then return end
    node = previous
  end
  while node and node:parent() do
    local parent = node:parent():type()
    if parent == 'chunk' or parent == 'block' then break end
    node = node:parent()
  end
  if not node or node:has_error() then return end
  local source = vim.treesitter.get_node_text(node, 0)
  local helper = source:match '^dofile%s*%(' and source:find('nvim_debug.lua', 1, true)
  if helper and source:find('.fail(', 1, true) then
    local block = node:parent()
    local parent = block and block:parent()
    if not parent or parent:type() ~= 'if_statement' or block:named_child_count() ~= 1 then return end
    local parent_source = vim.treesitter.get_node_text(parent, 0)
    if not parent_source:match '^if not ' or parent_source:find('else', 1, true) then return end
    node = parent
  end
  local call = node:type() == 'function_call' and (source:match '^print%s*%(' or source:match '^assert%s*%(' or source:match '^vim%.notify%s*%(')
  local timer = source:match '^local nvim_dbg_start_%d+%s*=%s*os%.clock%(%s*%)'
  if not (call or timer or helper) then return end
  local first, start_col, last, end_col = node:range()
  local before, after = lines[first + 1]:sub(1, start_col), lines[last + 1]:sub(end_col + 1)
  if not before:match '^%s*$' or not (after:match '^%s*$' or after:match '^%s*%-%-') then return end
  return first, last + 1
end

function M.remove()
  local mode = vim.fn.mode()
  if mode == '\22' then
    vim.notify('Use characterwise or linewise selection to remove debug logs', vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local first, last = 0, #lines
  if mode == 'v' or mode == 'V' then
    local anchor, cursor = vim.fn.line 'v', vim.fn.line '.'
    first, last = math.min(anchor, cursor) - 1, math.max(anchor, cursor)
    vim.cmd.normal { '\27', bang = true }
  elseif mode ~= 'n' then
    return
  end

  local root, compiled
  local ft = vim.bo.filetype
  if ft == 'python' or ft == 'lua' then
    local ok, trees = pcall(function() return vim.treesitter.get_parser(0, ft):parse() end)
    if not ok or not trees[1] then
      vim.notify(ft .. ' debug cleanup requires a Tree-sitter parser', vim.log.levels.WARN)
      return
    end
    root = trees[1]:root()
  elseif ft == 'cpp' or ft == 'rust' then
    compiled = compiled_ranges(lines, ft)
  end

  local ranges, seen, skipped = {}, {}, 0
  local text = marker()
  for row = first, last - 1 do
    local column = lines[row + 1]:find(text, 1, true)
    if column then
      local start_row, end_row
      if root then
        local locate = ft == 'python' and python_range or lua_range
        start_row, end_row = locate(root, lines, row, column - 1)
      elseif compiled then
        local range = compiled[row]
        if range then
          start_row, end_row = unpack(range)
        end
      else
        -- Other languages need a statement-aware adapter before safe cleanup.
        start_row, end_row = nil, nil
      end
      -- A partial selection must not delete code outside the selected lines.
      if start_row and start_row >= first and end_row <= last then
        if not seen[start_row] then
          ranges[#ranges + 1] = { start_row, end_row }
          seen[start_row] = true
        end
      else
        skipped = skipped + 1
      end
    end
  end
  -- Drop our C++ include only when all helper references are being removed and
  -- the include itself is inside the requested selection.
  if ft == 'cpp' then
    local retained = false
    for row, line in ipairs(lines) do
      if line:find('nvim_dbg::', 1, true) then
        local removed = false
        for _, range in ipairs(ranges) do
          if row > range[1] and row <= range[2] then removed = true end
        end
        if not removed then retained = true end
      end
    end
    if not retained then
      for row = first, last - 1 do
        local line = lines[row + 1]
        if line:match '^#include ' and line:find('nvim_debug.hpp', 1, true) and line:find('// ' .. text, 1, true) then
          ranges[#ranges + 1] = { row, row + 1 }
          skipped = math.max(0, skipped - 1)
        end
      end
    end
  end
  table.sort(ranges, function(a, b) return a[1] > b[1] end)
  for _, range in ipairs(ranges) do
    if ft == 'python' then
      for row = range[1] + 1, range[2] do
        local original = require('custom.chainsaw-assert').original(lines[row])
        if original then range[3] = { original } end
      end
    end
  end
  if root and not root:has_error() then
    local remaining = vim.deepcopy(lines)
    for _, range in ipairs(ranges) do
      for row = range[2], range[1] + 1, -1 do
        table.remove(remaining, row)
      end
      if range[3] then table.insert(remaining, range[1] + 1, range[3][1]) end
    end
    local parsed = vim.treesitter.get_string_parser(table.concat(remaining, '\n'), ft):parse()
    if parsed[1]:root():has_error() or (ft == 'python' and empty_python_suite(parsed[1]:root())) then
      vim.notify('Cleanup would leave invalid syntax (for example an empty Python suite); add a pass or adjust the selection', vim.log.levels.WARN)
      return
    end
  end
  local removed = 0
  for index, range in ipairs(ranges) do
    if index > 1 then vim.cmd.undojoin() end
    vim.api.nvim_buf_set_lines(0, range[1], range[2], false, range[3] or {})
    removed = removed + range[2] - range[1]
  end
  if removed > 0 then
    vim.b.timeLogStart = nil
    vim.b.timelogStart = nil -- Clear upstream's misspelled reset variable too.
    -- Retain the index so partial cleanup cannot reuse surviving timer names.
    vim.b.timeLogIndex = (vim.b.timeLogIndex or 0) + 1
  end
  local message = ('Removed %d debug line(s)'):format(removed)
  if skipped > 0 then message = message .. ('; skipped %d partial or unsupported statement(s)'):format(skipped) end
  vim.notify(message, vim.log.levels.INFO)
end

function M.find()
  require('telescope.builtin').grep_string {
    search = marker(),
    -- Supply the marker literally to ripgrep, including its square brackets.
    use_regex = true,
    word_match = '',
    additional_args = { '--fixed-strings', '--case-sensitive', '--glob', '!.git/**' },
    hidden = true,
    cwd = vim.fs.root(0, '.git') or vim.fn.getcwd(),
    prompt_title = 'Debug logs',
  }
end

function M.jump(direction)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current = vim.api.nvim_win_get_cursor(0)[1]
  local text = marker()
  -- Search whole lines, wrapping once. Leave the user's search register alone.
  for offset = 1, #lines do
    local row = (current - 1 + direction * offset) % #lines + 1
    local column = lines[row]:find(text, 1, true)
    if column then
      vim.cmd "normal! m'"
      vim.api.nvim_win_set_cursor(0, { row, column - 1 })
      vim.cmd 'normal! zv'
      return
    end
  end
  vim.notify('No debug logs in this buffer', vim.log.levels.INFO)
end

return M
