-- Language-aware rendering around Chainsaw's commands and repeat machinery.
local M = {}

M.marker = '⟦nvim:dbg⟧'
M.icons =
  { str = '', repr = '', object = '', type = '', checkpoint = '📍', note = '', time = '', stack = '', assert = '🧪', break_ = '' }
local kinds = {
  variableLog = 'str',
  reprLog = 'repr',
  objectLog = 'object',
  typeLog = 'type',
  emojiLog = 'checkpoint',
  messageLog = 'note',
  timeLogStart = 'time',
  timeLogStop = 'time',
  stacktraceLog = 'stack',
  assertLog = 'assert',
  debugLog = 'break_',
}

-- Never rewrite the expression to escape its label (notably C++/Rust indexing).
local function quote(ft, text)
  text = text:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
  text = text:gsub('%c', function(c)
    if ft == 'lua' or ft == 'nvim_lua' then return ('\\%03d'):format(c:byte()) end
    if ft == 'cpp' then return ('\\%03o'):format(c:byte()) end
    return ('\\x%02x'):format(c:byte())
  end)
  return '"' .. text .. '"'
end
M.quote = quote

function M.render(ft, action, expression, specific, marker)
  local kind = kinds[action]
  if not kind then return nil, 'Unsupported log action: ' .. action end
  local prefix = M.icons[kind] .. ' ' .. (marker or M.marker) .. ' ' .. (kind == 'break_' and 'break' or kind) .. ' │ '
  local label = quote(ft, prefix .. (expression or '') .. ' → ')
  local condition = quote(ft, prefix .. (expression or ''))
  local value = '(' .. (expression or '') .. ')'
  local plain = quote(ft, (action == 'emojiLog' and M.icons.checkpoint .. ' ' .. (marker or M.marker) .. ' ' or prefix) .. (specific or ''))
  local index = tostring(specific or 1)
  local timer = 'nvim_dbg_start_' .. index
  local timer_label = quote(ft, prefix .. '#' .. index .. ' → ')
  local mark = marker or M.marker
  if ft == 'python' then
    if action == 'variableLog' then return 'print(' .. label .. ', str(' .. value .. '), sep="")' end
    if action == 'reprLog' then return 'print(' .. label .. ', repr(' .. value .. '), sep="")' end
    if action == 'objectLog' then return 'print(' .. label .. ', __import__("pprint").pformat(' .. value .. ', sort_dicts=False), sep="")' end
    if action == 'typeLog' then return 'print(' .. label .. ', type(' .. value .. '), sep="")' end
    if action == 'assertLog' then return 'assert ' .. value .. ', ' .. condition end
    if action == 'debugLog' then return 'breakpoint()  # ' .. M.icons.break_ .. ' ' .. mark .. ' break' end
    if action == 'messageLog' or action == 'emojiLog' then return 'print(' .. plain .. ')' end
    if action == 'stacktraceLog' then
      return 'print(' .. quote(ft, prefix .. '\n') .. ' + "".join(__import__("traceback").format_stack()), file=__import__("sys").stderr)'
    end
    if action == 'timeLogStart' then return timer .. ' = __import__("time").perf_counter()  # ' .. mark end
    if action == 'timeLogStop' then
      return 'print(' .. timer_label .. ' + format((__import__("time").perf_counter() - ' .. timer .. ') * 1000, ".3f") + " ms")'
    end
  elseif ft == 'rust' then
    local formats = { variableLog = '{}', reprLog = '{:?}', objectLog = '{:#?}' }
    if formats[action] then return 'eprintln!("{}' .. formats[action] .. '", ' .. label .. ', &' .. value .. ');' end
    if action == 'typeLog' then return 'eprintln!("{}{}", ' .. label .. ', std::any::type_name_of_val(&' .. value .. '));' end
    if action == 'assertLog' then return 'assert!(' .. value .. ', "{}", ' .. condition .. ');' end
    if action == 'messageLog' or action == 'emojiLog' then return 'eprintln!("{}", ' .. plain .. ');' end
    if action == 'stacktraceLog' then return 'eprintln!("{}\\n{}", ' .. quote(ft, prefix) .. ', std::backtrace::Backtrace::force_capture());' end
    if action == 'timeLogStart' then return 'let ' .. timer .. ' = std::time::Instant::now(); // ' .. mark end
    if action == 'timeLogStop' then return 'eprintln!("{}{:.3} ms", ' .. timer_label .. ', ' .. timer .. '.elapsed().as_secs_f64() * 1000.0);' end
  elseif ft == 'cpp' then
    if action == 'variableLog' then return 'std::cerr << ' .. label .. ' << ' .. value .. ' << std::endl;' end
    if action == 'typeLog' then return 'std::cerr << ' .. label .. ' << typeid(' .. value .. ').name() << std::endl;' end
    if action == 'assertLog' then return 'assert(' .. value .. ' && ' .. condition .. ');' end
    if action == 'messageLog' or action == 'emojiLog' then return 'std::cerr << ' .. plain .. ' << std::endl;' end
    if action == 'timeLogStart' then return 'auto ' .. timer .. ' = std::chrono::steady_clock::now(); // ' .. mark end
    if action == 'timeLogStop' then
      return 'std::cerr << '
        .. timer_label
        .. ' << std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - '
        .. timer
        .. ').count() << " ms" << std::endl;'
    end
  elseif ft == 'lua' or ft == 'nvim_lua' then
    local emit = ft == 'nvim_lua' and 'vim.notify' or 'print'
    if action == 'variableLog' then return emit .. '(' .. label .. ' .. tostring(' .. value .. '))' end
    if ft == 'nvim_lua' and (action == 'reprLog' or action == 'objectLog') then return emit .. '(' .. label .. ' .. vim.inspect(' .. value .. '))' end
    if action == 'typeLog' then return emit .. '(' .. label .. ' .. type(' .. value .. '))' end
    if action == 'assertLog' then return 'assert(' .. value .. ', ' .. condition .. ')' end
    if action == 'messageLog' or action == 'emojiLog' then return emit .. '(' .. plain .. ')' end
    if action == 'stacktraceLog' then return emit .. '(debug.traceback(' .. quote(ft, prefix) .. ', 2))' end
    if action == 'timeLogStart' then return 'local ' .. timer .. ' = os.clock() -- ' .. mark end
    if action == 'timeLogStop' then return emit .. '(' .. timer_label .. ' .. string.format("%.3f ms CPU", (os.clock() - ' .. timer .. ') * 1000))' end
  end
  return nil, ('%s is not available for %s yet'):format(kind == 'break_' and 'break' or kind, ft)
end

local function expression()
  local mode = vim.fn.mode()
  if mode == '\22' then return nil, 'Select an expression with characterwise or linewise visual mode' end
  if mode == 'v' or mode == 'V' then
    local selection = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = mode })
    if #selection ~= 1 then return nil, 'Select a single-line expression' end
    vim.cmd.normal { '\27', bang = true }
    return vim.trim(selection[1])
  end
  -- Detection and placement must both see the latest buffer, including a
  -- previous insertion followed by dot-repeat at a different expression.
  pcall(function() vim.treesitter.get_parser(0):parse() end)
  local detected = require('chainsaw.core.determine-var').getVar()
  if vim.bo.filetype == 'python' then
    local ok, node = pcall(vim.treesitter.get_node, { ignore_injections = true })
    -- On a quote or string content, upstream can return only that fragment.
    -- Keep its subscript detection, but otherwise use the complete literal.
    if ok and node and node:type():match '^string_' then
      while node and node:type() ~= 'string' do
        node = node:parent()
      end
      if node and (not node:parent() or node:parent():type() ~= 'subscript') then detected = vim.treesitter.get_node_text(node, 0) end
    end
  end
  return detected
end

local function valid_python_expression(text)
  if text:find '[\r\n]' then return false end
  local ok, valid = pcall(function()
    local root = vim.treesitter.get_string_parser('(' .. text .. ')\n', 'python'):parse()[1]:root()
    return not root:has_error() and root:named_child_count() == 1 and root:named_child(0):type() == 'expression_statement'
  end)
  return ok and valid
end

local function next_checkpoint()
  local prefix = require('chainsaw.config.config').config.marker .. ' checkpoint │ '
  local highest = ''
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local from = 1
    while true do
      local _, last = line:find(prefix, from, true)
      if not last then break end
      local label = line:sub(last + 1):match '^([A-Z]+)%f[%A]'
      if label and (#label > #highest or (#label == #highest and label > highest)) then highest = label end
      from = last + 1
    end
  end
  -- Spreadsheet-style labels: A … Z, AA … AZ, BA … . Derive the next
  -- label from the buffer so reopening/undo cannot create duplicate labels.
  local tail = ''
  for index = #highest, 1, -1 do
    local byte = highest:byte(index)
    if byte < string.byte 'Z' then return highest:sub(1, index - 1) .. string.char(byte + 1) .. tail end
    tail = 'A' .. tail
  end
  return 'A' .. tail
end

function M.setup(options)
  M.rich = options and options.rich or false
  local inserter = require 'chainsaw.core.insert-statements'
  if M.installed then return end
  M.installed = true
  local original_insert = inserter.insert
  local function insert(action, specific, supplied, observed, replacement)
    action = action or vim.b.chainsawLogType
    local ft = require('chainsaw.utils').getFiletype()
    if not ({ python = true, rust = true, cpp = true, lua = true, nvim_lua = true })[ft] then
      if not require('chainsaw.config.config').config.logStatements[action] then
        vim.notify(action .. ' is not configured for ' .. ft, vim.log.levels.WARN)
        return false
      end
      return original_insert(action, specific)
    end
    local expr, err = supplied, nil
    if ({ variableLog = true, reprLog = true, objectLog = true, typeLog = true, assertLog = true })[action] and not expr then
      expr, err = expression()
      if expr == '' then err = 'No expression under cursor' end
    end
    if not err and ft == 'python' then
      if expr and not valid_python_expression(expr) then err = 'Select a complete Python expression' end
      if observed and observed ~= '' and not valid_python_expression(observed) then err = 'Observed value must be a complete Python expression' end
    end
    local config = require('chainsaw.config.config').config
    local source, include
    if not err and M.rich then
      source, include = require('custom.chainsaw-rich').render(ft, action, expr, observed, config.marker, replacement)
    end
    if not err and not source then
      source, err = M.render(ft, action, expr, specific, config.marker)
    end
    if not source then
      vim.notify(err, vim.log.levels.WARN)
      return false
    end
    local result
    if replacement then
      result = require('custom.chainsaw-assert').replace(source, replacement)
    else
      result = require('custom.chainsaw-insert').insert(source, ft)
    end
    if result and include then require('custom.chainsaw-rich').ensure_include(include) end
    return result
  end
  inserter.insert = insert
  local commands = require 'chainsaw.core.log-commands'
  for action in pairs(kinds) do
    if action ~= 'emojiLog' and action ~= 'timeLogStart' and action ~= 'timeLogStop' then commands[action] = function() return insert(action) end end
  end
  -- Upstream emojiLog randomizes a fixed pool and eventually reuses labels.
  -- Override the command itself so the keymap, :Chainsaw, and dot-repeat agree.
  commands.emojiLog = function() return insert('emojiLog', 'checkpoint │ ' .. next_checkpoint()) end
  commands.assertLog = function()
    if not M.rich then return insert 'assertLog' end
    local replacement = require('custom.chainsaw-assert').existing()
    local expr, err
    if replacement then
      expr = replacement.condition
    else
      expr, err = expression()
    end
    if not expr or expr == '' then
      vim.notify(err or 'Select an assertion condition', vim.log.levels.WARN)
      return
    end
    if vim.bo.filetype == 'python' and not valid_python_expression(expr) then
      vim.notify('Select a complete Python assertion condition', vim.log.levels.WARN)
      return
    end
    local buffer, cursor = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
    local tick = vim.api.nvim_buf_get_changedtick(buffer)
    vim.ui.input({ prompt = 'Observed value on failure (expression, optional): ' }, function(observed)
      if observed == nil then return end
      observed = vim.trim(observed)
      if observed:find '[\r\n]' then
        vim.notify('Observed value must be a single-line expression', vim.log.levels.WARN)
        return
      end
      if
        buffer ~= vim.api.nvim_get_current_buf()
        or tick ~= vim.api.nvim_buf_get_changedtick(buffer)
        or not vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(0))
      then
        vim.notify('Assertion cancelled: insertion location changed', vim.log.levels.WARN)
        return
      end
      insert('assertLog', nil, expr, observed, replacement)
    end)
  end
  commands.messageLog = function()
    local buffer, cursor = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
    vim.ui.input({ prompt = 'Debug note: ' }, function(note)
      if not note then return end
      if buffer ~= vim.api.nvim_get_current_buf() or not vim.deep_equal(cursor, vim.api.nvim_win_get_cursor(0)) then
        vim.notify('Debug note cancelled: insertion location changed', vim.log.levels.WARN)
        return
      end
      insert('messageLog', note)
    end)
  end
  -- Account for surviving/reloaded timer statements before allocating an index.
  local time_log = commands.timeLog
  commands.timeLog = function()
    if vim.b.timeLogStart == nil or vim.b.timeLogStart then
      local index = vim.b.timeLogIndex or 1
      for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        for used in line:gmatch 'nvim_dbg_start_(%d+)' do
          index = math.max(index, tonumber(used) + 1)
        end
      end
      vim.b.timeLogIndex = index
    end
    return time_log()
  end
end

return M
