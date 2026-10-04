-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_rich.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
local rich = require 'custom.chainsaw.rich'
local marker = require('custom.chainsaw').marker
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
local function run(args, fails)
  local result = vim.system(args, { text = true }):wait()
  local failed = result.code ~= 0 or result.signal ~= 0
  assert(failed == (fails or false), vim.inspect(args) .. '\n' .. vim.inspect(result))
  return result.stdout .. result.stderr
end
local files = { python = 'py', rust = 'rs', cpp = 'cpp', lua = 'lua' }
local definitions = {
  python = 'value = {"items": [1, 2, 3], "name": "Ada\\tLovelace"}',
  rust = 'let value = vec![1, 2, 3];',
  cpp = 'std::vector<int> value = {1,2,3};',
  lua = 'local value = {items = {1,2,3}, name = "Ada\\tLovelace"}; value.self = value',
}
local function program(ft, actions, fails, formatted)
  local body = { definitions[ft] }
  local include
  for _, action in ipairs(actions) do
    local source, header = rich.render(ft, action[1], action[2], action[3], marker)
    assert(source, ft .. ' ' .. action[1])
    body[#body + 1] = source
    include = include or header
  end
  local expected = { definitions[ft] }
  if ft == 'rust' then
    table.insert(body, 1, 'fn main() {')
    body[#body + 1] = '}'
    expected = { 'fn main() {', definitions[ft], '}' }
  end
  if ft == 'cpp' then
    table.insert(body, 1, 'int main() {')
    table.insert(body, 1, '#include <vector>')
    table.insert(body, 1, include)
    body[#body + 1] = '}'
    expected = { '#include <vector>', 'int main() {', definitions[ft], '}' }
  end
  local file = dir .. '/fixture.' .. files[ft]
  vim.fn.writefile(body, file)
  if formatted and ft == 'rust' then
    run { 'rustfmt', file }
    body = vim.fn.readfile(file)
  end
  if formatted and ft == 'python' then
    local ruff = vim.fn.exepath 'ruff'
    if ruff == '' then ruff = vim.fn.stdpath 'data' .. '/mason/bin/ruff' end
    run { ruff, 'format', file }
    body = vim.fn.readfile(file)
  end
  local cmd
  if ft == 'rust' then
    run { 'rustc', '--crate-name', 'rich_fixture', '-g', file, '-o', dir .. '/rust' }
    cmd = { dir .. '/rust' }
  elseif ft == 'cpp' then
    run { 'clang++', '-std=c++17', '-g', file, '-o', dir .. '/cpp' }
    cmd = { dir .. '/cpp' }
  else
    cmd = { ft == 'python' and 'python3' or 'luajit', file }
  end
  local output = run(cmd, fails)
  if fails then
    for _, part in ipairs { '🧪 ' .. marker .. ' assert', ft == 'python' and 'condition' or 'expected', 'observed', 'location', '╰─ FAILED' } do
      assert(output:find(part, 1, true), output)
    end
  else
    assert(output:find(marker, 1, true), output)
  end
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(0, 0, -1, false, body)
  require('chainsaw').removeLogs()
  local remaining = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(not table.concat(remaining, '\n'):find(marker, 1, true), vim.inspect(remaining))
  assert(not table.concat(remaining, '\n'):find('nvim_dbg::', 1, true), vim.inspect(remaining))
  assert(not table.concat(remaining, '\n'):find('nvim_debug.', 1, true), vim.inspect(remaining))
  if ft == 'python' then
    local parsed = vim.system({ 'python3', '-c', 'import ast,sys; ast.parse(sys.stdin.read())' }, { text = true, stdin = table.concat(remaining, '\n') }):wait()
    assert(parsed.code == 0, parsed.stderr)
  end
  return output
end
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  local output = program(ft, { { 'objectLog', 'value' }, { 'stacktraceLog' } }, false, true)
  assert(output:find(' ' .. marker .. ' object │ value', 1, true), output)
  assert(output:find(' ' .. marker .. ' stack', 1, true), output)
  if ft == 'python' or ft == 'lua' then assert(output:find('← current', 1, true), output) end
  if ft == 'lua' then assert(output:find('<cycle>', 1, true), output) end
  program(ft, { { 'assertLog', ft == 'python' and 'False' or 'false', 'value' } }, true, true)
  -- Passing checks do not evaluate diagnostic expressions (which would fail).
  local expression = ft == 'python' and '1 / 0' or ft == 'rust' and 'panic!("evaluated")' or ft == 'cpp' and '(std::abort(), 0)' or 'error("evaluated")'
  -- Use object output to assert the process actually ran.
  program(ft, { { 'assertLog', ft == 'python' and 'True' or 'true', expression }, { 'objectLog', 'value' } }, false, false)
  if ft == 'lua' or ft == 'cpp' then program(ft, { { 'reprLog', 'value' } }, false, false) end
  print('PASS: ' .. ft .. ' rich output, lazy assertion diagnostics, formatted statement cleanup')
end
vim.fn.delete(dir, 'rf')

-- The public API takes the rich path, adds one C++ include, and cleans it up.
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft
  local original = ft == 'python' and { 'value = [1, 2, 3]' }
    or ft == 'rust' and { 'fn main() {', 'let value = vec![1,2,3];', '}' }
    or ft == 'cpp' and { '#include <vector>', 'int main() {', 'std::vector<int> value = {1,2,3};', '}' }
    or { 'local value = {1,2,3}' }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, original)
  local row = ft == 'cpp' and 3 or ft == 'rust' and 2 or 1
  local column = assert(original[row]:find('value', 1, true)) - 1
  vim.api.nvim_win_set_cursor(0, { row, column })
  vim.cmd.normal { 'viw', bang = true }
  require('chainsaw').objectLog()
  require('chainsaw').stacktraceLog()
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  assert(text:find('nvim_debug.', 1, true), text)
  if ft == 'cpp' then
    local _, count = text:gsub('#include [^\n]*nvim_debug.hpp', '')
    assert(count == 1, text)
  end
  require('chainsaw').removeLogs()
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original), vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
end
-- Source assertion UI captures diagnostics as an expression, not as text.
vim.cmd.enew { bang = true }
vim.bo.filetype = 'python'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'value = 2' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local input = vim.ui.input
vim.ui.input = function(_, callback) callback '{"value": value}' end
require('chainsaw').assertLog()
vim.ui.input = input
local statement = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
assert(statement:find('if not (value):', 1, true) and statement:find('{"value": value}', 1, true), statement)
-- Removing a sole Python suite statement must not leave invalid Python.
vim.cmd.enew { bang = true }
vim.bo.filetype = 'python'
local suite = { 'def example():', '    print("' .. marker .. '")' }
vim.api.nvim_buf_set_lines(0, 0, -1, false, suite)
require('chainsaw').removeLogs()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), suite))
-- Never erase user statements from a block that happens to call the helper.
vim.cmd.enew { bang = true }
vim.bo.filetype = 'cpp'
local shared = { 'if (ready) { nvim_dbg::stack_log("' .. marker .. '"); user_work(); }' }
vim.api.nvim_buf_set_lines(0, 0, -1, false, shared)
require('chainsaw').removeLogs()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), shared))
print 'PASS: public API, helper include ownership, assertion prompt, and cleanup syntax protection'
