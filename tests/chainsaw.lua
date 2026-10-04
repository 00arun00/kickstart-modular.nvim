-- Run with: nvim --headless -n -u NONE -i NONE -l tests/chainsaw.lua
-- Requires the installed Chainsaw plugin and Python Tree-sitter parser.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
require('custom.chainsaw').rich = false -- Phase 1 / native baseline

local function check(lines, cursor, variable, insert_after, indent, visual)
  vim.cmd.enew { bang = true }
  vim.bo.filetype = 'python'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.treesitter.get_parser(0, 'python'):parse()
  vim.api.nvim_win_set_cursor(0, cursor)
  if visual then vim.cmd.normal { 'viw', bang = true } end
  require('chainsaw').variableLog()
  local expected = vim.deepcopy(lines)
  table.insert(expected, insert_after + 1, (indent or '') .. ('print(" ⟦nvim:dbg⟧ str │ %s → ", str((%s)), sep="")'):format(variable, variable))
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, expected), vim.inspect { cursor = cursor, actual = actual, expected = expected })
  assert(not vim.treesitter.get_parser(0, 'python'):parse()[1]:root():has_error(), 'Inserted log breaks Python syntax')
end

local parenthesized = { 'a = (', 'afafdsaf', ')' }
check(parenthesized, { 1, 0 }, 'a', 3)
check(parenthesized, { 2, 0 }, 'afafdsaf', 3)
check(parenthesized, { 2, 0 }, 'afafdsaf', 3, '', true)
check({ 'def example():', '    a = (', '        afafdsaf', '    )', '    return a' }, { 3, 8 }, 'afafdsaf', 4, '    ')
check({ 'a = [', '    item,', ']' }, { 2, 4 }, 'item', 3)
check({ 'a = build(', '    item,', ')' }, { 2, 4 }, 'item', 3)
check({ 'a += (', '    item', ')' }, { 1, 0 }, 'a', 3)
check({ 'a: int = (', '    item', ')' }, { 1, 0 }, 'a', 3)
check({ 'a = b = (', '    item', ')' }, { 1, 4 }, 'b', 3)
check({ 'a = 12', 'consume(a)' }, { 1, 0 }, 'a', 1)
-- Retain upstream insertion after a function's docstring for parameter logging.
check({ 'def example(value):', '    """Explain the function.', '    More detail.', '    """', '    return value' }, { 1, 12 }, 'value', 4, '    ')

local function reset(filetype, lines, cursor)
  vim.cmd.enew { bang = true }
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
  if filetype == 'python' then vim.treesitter.get_parser(0, 'python'):parse() end
end

local function run_python()
  local code = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  local result = vim.system({ 'python3', '-c', code }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result
end

-- Pretty-printing evaluates real nested data; cleanup leaves no import behind.
local original = { 'payload = {"items": list(range(30)), "nested": {"ok": True}}' }
reset('python', original)
require('chainsaw').objectLog()
local result = run_python()
assert(result.stdout:find('⟦nvim:dbg⟧ object │ payload → ', 1, true) and result.stdout:find("'nested': {'ok': True}", 1, true))
assert(#vim.split(result.stdout, '\n') > 3, 'Expected multiline pretty output')
require('chainsaw').removeLogs()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original))

-- A visual selection of multiple values must remain one pformat argument,
-- rather than binding the second value to pprint's numeric indent parameter.
reset('python', { 'left, right = {"name": "training"}, {"name": "validation"}' })
vim.cmd.normal { 'v10l', bang = true }
require('chainsaw').objectLog()
result = run_python()
assert(result.stdout:find("({'name': 'training'}, {'name': 'validation'})", 1, true), result.stdout)
require('chainsaw').removeLogs()
assert(vim.api.nvim_buf_line_count(0) == 1)

reset('python', { 'value = 1' })
require('chainsaw').stacktraceLog()
result = run_python()
assert(result.stderr:find('line 2, in <module>', 1, true), result.stderr)
require('chainsaw').removeLogs()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'value = 1' }))

-- The inferred Rust type is printed without consuming a non-Copy value.
reset('rust', { 'fn main() {', '    let value = String::from("hello");', '    println!("{}", value);', '}' }, { 2, 8 })
require('chainsaw').typeLog()
local rust_file = vim.fn.tempname() .. '.rs'
local rust_bin = vim.fn.tempname()
vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), rust_file)
local compiled = vim.system({ 'rustc', '--crate-name', 'chainsaw_test', rust_file, '-o', rust_bin }, { text = true }):wait()
assert(compiled.code == 0, compiled.stderr)
local executed = vim.system({ rust_bin }, { text = true }):wait()
vim.fn.delete(rust_file)
vim.fn.delete(rust_bin)
assert(executed.code == 0 and executed.stdout == 'hello\n', executed.stderr)
assert(executed.stderr:find('⟦nvim:dbg⟧ type │ value → alloc::string::String', 1, true), executed.stderr)

-- Breadcrumbs carry distinct letter labels, carry the cleanup marker, and use different labels.
reset('python', { 'value = 1' })
require('chainsaw').emojiLog()
require('chainsaw').emojiLog()
local breadcrumb_lines = vim.api.nvim_buf_get_lines(0, 1, -1, false)
assert(breadcrumb_lines[1]:find('checkpoint │ A', 1, true))
assert(breadcrumb_lines[2]:find('checkpoint │ B', 1, true))
for _, line in ipairs(breadcrumb_lines) do
  assert(line:find('⟦nvim:dbg⟧ checkpoint │ ', 1, true))
end
assert(run_python().stdout:find('⟦nvim:dbg⟧ checkpoint │ ', 1, true))

-- Navigation skips the current line, wraps, opens folds, and preserves search.
local logs = require 'custom.navigation.logs'
reset('python', { 'debug = 1', 'print("⟦nvim:dbg⟧ first")', 'value = 2', 'print("⟦nvim:dbg⟧ second")' })
vim.fn.setreg('/', 'previous search')
vim.wo.foldmethod = 'manual'
vim.cmd '3,4fold'
logs.jump(1)
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
logs.jump(1)
assert(vim.api.nvim_win_get_cursor(0)[1] == 4 and vim.fn.foldclosed(4) == -1)
logs.jump(1)
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
logs.jump(-1)
assert(vim.api.nvim_win_get_cursor(0)[1] == 4)
assert(vim.fn.getreg '/' == 'previous search')

-- A literal ripgrep search must not interpret ⟦nvim:dbg⟧ as a character class.
local captured
package.loaded['telescope.builtin'] = { grep_string = function(opts) captured = opts end }
logs.find()
assert(captured.cwd == vim.fs.root(vim.fn.getcwd(), '.git'))
local fixture = vim.fn.tempname()
vim.fn.writefile({ 'debug = 1', 'print("⟦nvim:dbg⟧ value")', 'print("⟦NVIM:DBG⟧ ignored")' }, fixture)
local args = { 'rg', '--smart-case', '--no-heading' }
vim.list_extend(args, captured.additional_args)
vim.list_extend(args, { '--', captured.search, fixture })
local found = vim.system(args, { text = true }):wait()
vim.fn.delete(fixture)
assert(found.code == 0 and found.stdout == 'print("⟦nvim:dbg⟧ value")\n', vim.inspect(found))
print 'PASS: Python placement, custom Python/Rust output, cleanup, breadcrumbs, log navigation, and literal project search'
