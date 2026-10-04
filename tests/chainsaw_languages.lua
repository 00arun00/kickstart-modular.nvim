-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_languages.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
require('custom.chainsaw').rich = false -- Phase 1 / native baseline
local renderer = require 'custom.chainsaw'
local marker = renderer.marker
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local function run(args)
  local result = vim.system(args, { text = true }):wait()
  assert(result.code == 0, vim.inspect(args) .. '\n' .. result.stderr)
  return result.stdout .. result.stderr
end
local prelude = {
  python = 'value = "Ada\\tLovelace"',
  rust = 'fn main() { let value = String::from("Ada\\tLovelace");',
  cpp = '#include <iostream>\n#include <string>\n#include <chrono>\n#include <cassert>\n#include <typeinfo>\nint main() { std::string value = "Ada\\tLovelace";',
  lua = 'local value = "Ada\\tLovelace"',
}
local function execute(ft, statements, failing)
  local ending = (ft == 'rust' or ft == 'cpp') and '\n}' or ''
  local source = prelude[ft] .. '\n' .. table.concat(statements, '\n') .. ending
  local path = directory .. '/fixture.' .. ({ python = 'py', rust = 'rs', cpp = 'cpp', lua = 'lua' })[ft]
  vim.fn.writefile(vim.split(source, '\n'), path)
  local command
  if ft == 'rust' or ft == 'cpp' then
    local binary = directory .. '/fixture_' .. ft
    if ft == 'rust' then
      run { 'rustc', '--crate-name', 'chainsaw_fixture', path, '-o', binary }
    else
      run { 'clang++', '-std=c++17', path, '-o', binary }
    end
    command = { binary }
  else
    command = { ft == 'python' and 'python3' or 'luajit', path }
  end
  if failing then
    local result = vim.system(command, { text = true }):wait()
    assert((result.code ~= 0 or result.signal ~= 0) and (result.stdout .. result.stderr):find(marker, 1, true), vim.inspect(result))
    return
  end
  return run(command)
end
local function render(ft, action, expr, arg)
  local source, err = renderer.render(ft, action, expr, arg)
  assert(source, err)
  return source
end
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  local truth = ft == 'python' and 'True' or 'true'
  local statements = {
    render(ft, 'variableLog', 'value'),
    render(ft, 'typeLog', 'value'),
    render(ft, 'messageLog', nil, 'quote " slash \\ {ABC} {{insert}}'),
    render(ft, 'emojiLog', nil, 'checkpoint │ A'),
    render(ft, 'assertLog', truth),
    render(ft, 'timeLogStart', nil, 1),
    render(ft, 'timeLogStop', nil, 1),
  }
  if ft == 'python' or ft == 'rust' then
    statements[#statements + 1] = render(ft, 'reprLog', 'value')
    statements[#statements + 1] = render(ft, 'objectLog', 'value')
  end
  if ft ~= 'cpp' then statements[#statements + 1] = render(ft, 'stacktraceLog') end
  local output = execute(ft, statements)
  assert(output:find('str │ value → Ada\tLovelace', 1, true), output)
  assert(output:find('quote " slash \\ {ABC} {{insert}}', 1, true), output)
  assert(output:find('checkpoint │ A', 1, true), output)
  assert(output:find('time │ #1 → ', 1, true), output)
  if ft == 'lua' then assert(output:find('ms CPU', 1, true), output) end
  if ft == 'python' or ft == 'rust' then assert(output:find('Ada\\tLovelace', 1, true), output) end
  execute(ft, { render(ft, 'assertLog', ft == 'python' and 'False' or 'false') }, true)
  print('PASS: compiled/executed ' .. ft .. ' logs and assertion failure')
end
-- Exercise the actual insertion adapter with quoted selections, including Rust
-- and C++ expressions that must retain double quotes.
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft
  local expression = 'record["name"]'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { expression })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.normal { 'V', bang = true }
  require('chainsaw').variableLog()
  local inserted = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
  assert(inserted:find('(record["name"])', 1, true), inserted)
end
-- Unsupported operations must be non-mutating, never masquerade as repr/break.
vim.cmd.enew { bang = true }
vim.bo.filetype = 'cpp'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'value' })
require('chainsaw').reprLog()
require('chainsaw').debugLog()
assert(vim.api.nvim_buf_line_count(0) == 1)
-- Markers in ordinary assignments must not be mistaken for generated logs.
vim.cmd.enew { bang = true }
vim.bo.filetype = 'python'
local ordinary = { 'prefix = "' .. marker .. '"', 'print(prefix)', '# [debug] legacy marker' }
vim.api.nvim_buf_set_lines(0, 0, -1, false, ordinary)
require('chainsaw').removeLogs()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), ordinary))
-- Full formatted Rust/C++ statements are removed; neighboring statements survive.
for _, ft in ipairs { 'rust', 'cpp' } do
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft
  local statement = ft == 'rust' and { 'eprintln!(', '    "' .. marker .. ' {}",', '    value', ');' }
    or { 'std::cerr', '    << "' .. marker .. '"', '    << value', '    << std::endl;' }
  local original = { 'intact();' }
  local content = vim.list_extend(vim.deepcopy(original), statement)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
  require('chainsaw').removeLogs()
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original))
  -- Never delete a line shared with other code.
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'eprintln!("' .. marker .. '"); user_code();' })
  require('chainsaw').removeLogs()
  assert(vim.api.nvim_get_current_line():find('user_code', 1, true))
end
vim.fn.delete(directory, 'rf')
print 'PASS: expression escaping, unsupported actions, conservative and multiline cleanup'
