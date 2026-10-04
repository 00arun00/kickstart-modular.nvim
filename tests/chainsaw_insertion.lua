-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_insertion.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
vim.g.mapleader = ' '
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
for _, key in ipairs(spec.keys) do
  vim.keymap.set(key.mode or 'n', key[1], key[2])
end
local chainsaw = require 'chainsaw'
local config = require 'custom.chainsaw'
local function reset(lines, cursor, ft)
  vim.cmd.normal { '\27', bang = true }
  vim.cmd.enew { bang = true }
  vim.bo.filetype = ft or 'python'
  vim.bo.undolevels = -1
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.undolevels = 1000
  vim.api.nvim_win_set_cursor(0, cursor)
end
local function press(keys) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false) end
local function execute()
  local result = vim.system({ 'python3', '-c', table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local function cleanup(original)
  chainsaw.removeLogs()
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original), vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
end
for _, rich in ipairs { false, true } do
  config.rich = rich
  for _, visual in ipairs { false, true } do
    local original = { 'def consume(value):', '    assert value == {"size": 32}', 'config = {"size": 32}', 'consume(', '    config,', ')' }
    reset(original, { 5, 4 })
    if visual then press 'viw' end
    press ' lo'
    assert(vim.api.nvim_buf_get_lines(0, 5, 6, false)[1] == ')')
    assert(execute():find('object │ config', 1, true))
    cleanup(original)
    original = { 'def example(value):', '    return (', '        value', '    )', 'assert example({"size": 32}) == {"size": 32}' }
    reset(original, { 3, 8 })
    if visual then press 'viw' end
    press ' lo'
    assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:match '^    ')
    assert(execute():find('object │ value', 1, true))
    cleanup(original)
    original =
      { 'def example(error):', '    raise (', '        error', '    )', 'try:', '    example(ValueError("expected"))', 'except ValueError:', '    pass' }
    reset(original, { 3, 8 })
    if visual then press 'viw' end
    press ' lo'
    assert(execute():find('object │ error', 1, true))
    cleanup(original)
  end
  for _, key in ipairs { '{{lnum}}', '{{insert}}', '{{var}}', '{{marker}}' } do
    local expr = 'record["' .. key .. '"]'
    local original = { 'record = {"' .. key .. '": 42}', expr }
    reset(original, { 2, 0 })
    press 'V'
    press ' lo'
    assert(execute():find('42', 1, true))
    assert(vim.api.nvim_get_current_line():find('(' .. expr .. ')', 1, true))
    assert(vim.fn.mode() == 'n')
    -- Direct insertion must retain signs and a single undo step.
    assert(#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace 'chainsaw.markers', 0, -1, {}) > 0)
    vim.cmd.undo()
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original))
    vim.cmd.redo()
    assert(execute():find('42', 1, true))
    cleanup(original)
  end
end
-- Refuse expressions whose comprehension/lambda scope would be lost.
for _, fixture in ipairs {
  { 'values = [item for item in range(3)]', 'item' },
  { 'values = {item for item in range(3)}', 'item' },
  { 'values = {item: item for item in range(3)}', 'item' },
  { 'values = (item for item in range(3))', 'item' },
  { 'transform = lambda item: item + 1', 'item' },
} do
  reset({ fixture[1] }, { 1, assert(fixture[1]:find(fixture[2], 1, true)) - 1 })
  chainsaw.objectLog()
  assert(vim.api.nvim_buf_line_count(0) == 1, fixture[1])
end
-- Keep a multiline signature's docstring and parameter scope intact.
local original = { 'def example(', '    value,', '):', '    """Documentation."""', '    return value', 'assert example(42) == 42' }
reset(original, { 2, 4 })
chainsaw.objectLog()
assert(vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] == '    """Documentation."""')
assert(execute():find('42', 1, true))
cleanup(original)
-- Shared-line statements should be left unchanged rather than split unsafely.
original = { 'value = 1; consume(value)' }
reset(original, { 1, 0 })
chainsaw.objectLog()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), original))
-- Mapping + dot-repeat at another value must preserve detection and insertion.
reset({ 'value = {"size": 32}', 'other = {"size": 64}' }, { 1, 0 })
press ' lo'
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press '.'
assert(vim.api.nvim_buf_line_count(0) == 4)
local output = execute()
assert(output:find('object │ value', 1, true) and output:find('object │ other', 1, true), output)
-- Strings in expressions must remain verbatim in every target language.
for _, ft in ipairs { 'rust', 'cpp', 'lua' } do
  for _, key in ipairs { '{{lnum}}', '{{insert}}' } do
    local expr = 'record["' .. key .. '"]'
    reset({ expr }, { 1, 0 }, ft)
    press 'V'
    press ' lv'
    assert(vim.api.nvim_get_current_line():find('(' .. expr .. ')', 1, true), vim.api.nvim_get_current_line())
  end
end
print 'PASS: executable call/return/raise placement, literal placeholders, scopes, docstrings, cleanup, undo, signs, mappings, and repeat'
