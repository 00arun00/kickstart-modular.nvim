-- Standalone Lua/LuaJIT formatter. No Neovim globals required.
local M = {}
local function repr(value, seen, depth, pretty)
  if type(value) == 'string' then return string.format('%q', value) end
  if type(value) ~= 'table' then return tostring(value) end
  if seen[value] then return '<cycle>' end
  if depth >= 8 then return '<max depth>' end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local entries = {}
  for index, key in ipairs(keys) do
    if index > 100 then
      entries[#entries + 1] = '...'
      break
    end
    entries[#entries + 1] = '[' .. repr(key, seen, depth + 1, false) .. '] = ' .. repr(value[key], seen, depth + 1, pretty)
  end
  seen[value] = nil
  if #entries == 0 then return '{}' end
  if not pretty then return '{' .. table.concat(entries, ', ') .. '}' end
  local indent = string.rep('  ', depth + 1)
  return '{\n' .. indent .. table.concat(entries, ',\n' .. indent) .. '\n' .. string.rep('  ', depth) .. '}'
end
function M.repr_log(marker, label, value) print(' ' .. marker .. ' repr │ ' .. label .. ' → ' .. repr(value, {}, 0, false)) end
function M.object_log(marker, label, value)
  print(' ' .. marker .. ' object │ ' .. label)
  print('    ' .. repr(value, {}, 0, true):gsub('\n', '\n    '))
end
function M.stack_log(marker)
  local frames, level = {}, 2
  while true do
    local frame = debug.getinfo(level, 'Sln')
    if not frame then break end
    if frame.what ~= 'C' then table.insert(frames, 1, frame) end
    level = level + 1
  end
  io.stderr:write(' ' .. marker .. ' stack\n')
  for index, frame in ipairs(frames) do
    local filename = frame.short_src:match '[^/\\]+$' or frame.short_src
    local name = frame.name or (frame.what == 'main' and '<module>' or '<anonymous>')
    local current = index == #frames and '  ← current' or ''
    io.stderr:write(
      '    ' .. string.rep('  ', index - 1) .. (index == 1 and '' or '↳ ') .. filename .. ':' .. frame.currentline .. '  ' .. name .. current .. '\n'
    )
  end
end
function M.fail(marker, condition, observed)
  local frame = debug.getinfo(2, 'Sln')
  local location = (frame.short_src:match '[^/\\]+$' or frame.short_src) .. ':' .. frame.currentline .. ' · ' .. (frame.name or '<anonymous>')
  io.stderr:write('🧪 ' .. marker .. ' assert │ condition failed\n    │\n    │  expected   ' .. condition .. '\n')
  io.stderr:write('    │  observed   ' .. repr(observed, {}, 0, false) .. '\n    │  location   ' .. location .. '\n    ╰─ FAILED\n')
  error(condition, 2)
end
return M
