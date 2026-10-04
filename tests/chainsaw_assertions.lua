-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_assertions.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/nvim-chainsaw')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local spec = require('custom.plugins.chainsaw')[1]
spec.config(nil, spec.opts)
vim.g.mapleader = ' '
for _, key in ipairs(spec.keys) do
  if key[1] == '<leader>la' then vim.keymap.set(key.mode, key[1], key[2]) end
end
local input, notify = vim.ui.input, vim.notify
local prompted, warning
vim.notify = function(message) warning = message end
local function reset(line, column, response, visual)
  vim.cmd.normal { '\27', bang = true }
  vim.cmd.enew { bang = true }
  vim.bo.filetype = 'python'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, column })
  if visual then vim.cmd.normal { 'v', bang = true } end
  prompted, warning = false, nil
  vim.ui.input = function(_, callback)
    prompted = true
    callback(response)
  end
end
local function execute(fails)
  local code = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  local parsed = vim.system({ 'python3', '-c', 'import ast,sys; ast.parse(sys.stdin.read())' }, { stdin = code, text = true }):wait()
  assert(parsed.code == 0, parsed.stderr)
  local result = vim.system({ 'python3', '-c', code }, { text = true }):wait()
  assert((result.code ~= 0) == fails, result.stderr)
  if fails then
    assert(result.stderr:find('condition failed', 1, true), result.stderr)
    assert(not result.stderr:find('│  observed', 1, true), result.stderr)
  end
end
-- Enter and whitespace both mean no optional diagnostic expression.
for _, response in ipairs { '', '   ' } do
  for _, value in ipairs { 'True', 'False' } do
    reset('value = ' .. value, 0, response)
    require('chainsaw').assertLog()
    assert(prompted and not warning, warning)
    execute(value == 'False')
  end
end
-- Quotes and string content must resolve to the whole literal, not a token.
for _, column in ipairs { 8, 9, 13 } do
  reset('value = "hello"', column, '')
  require('chainsaw').assertLog()
  assert(prompted and not warning, warning)
  assert(vim.api.nvim_get_current_line():find('if not ("hello"):', 1, true))
  execute(false)
end
-- An explicitly selected quote is invalid; leave the buffer untouched.
reset('value = "hello"', 8, '', true)
require('chainsaw').assertLog()
assert(not prompted and warning and vim.api.nvim_buf_line_count(0) == 1)
-- Invalid optional diagnostics must not introduce broken code either.
for _, response in ipairs { '"', 'value +', 'value; print(value)' } do
  reset('value = False', 0, response)
  require('chainsaw').assertLog()
  assert(prompted and warning and vim.api.nvim_buf_line_count(0) == 1)
end
reset('value = False', 0, nil)
require('chainsaw').assertLog()
assert(prompted and not warning and vim.api.nvim_buf_line_count(0) == 1)
-- Existing assertions: every cursor position and whole-statement visual modes
-- must preserve the call, laziness, indentation, message, and cleanup behavior.
local original = '    assert len(train_loader), "need a valid len" # keep this comment'
for _, mode in ipairs { 'n', 'v', 'V' } do
  for _, column in ipairs { 0, 4, 11, 15, 30, 35, #original - 1 } do
    for _, values in ipairs { '{}', '{1}' } do
      reset('', 0, '')
      local lines = { 'def train(train_loader):', original, 'train(' .. values .. ')' }
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 2, column })
      if mode == 'V' then
        vim.cmd.normal { 'V', bang = true }
      elseif mode == 'v' then
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        vim.cmd.normal { 'v$', bang = true }
      end
      vim.api.nvim_feedkeys(' la', 'xt', false)
      assert(prompted and not warning, tostring(warning))
      assert(vim.api.nvim_buf_line_count(0) == 3)
      local generated = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
      assert(generated:find('assert (len(train_loader)),', 1, true), generated)
      local code = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      local run = vim.system({ 'python3', '-c', code }, { text = true }):wait()
      assert((run.code ~= 0) == (values == '{}'), run.stderr)
      if values == '{}' then
        assert(run.stderr:find('│  message    need a valid len', 1, true), run.stderr)
        assert(not run.stderr:find('│  observed', 1, true), run.stderr)
      end
      -- Native optimization semantics must be retained for existing assertions.
      local optimized = vim.system({ 'python3', '-O', '-c', code }, { text = true }):wait()
      assert(optimized.code == 0 and optimized.stderr == '', optimized.stderr)
      require('chainsaw').removeLogs()
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines))
    end
  end
end
-- Function calls must run once; the original message stays lazy.
reset('', 0, '')
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'calls = []',
  'def condition(): calls.append(1); return True',
  'assert condition(), 1 / 0',
  'assert calls == [1]',
})
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_feedkeys(' la', 'xt', false)
assert(prompted and not warning, warning)
execute(false)
-- Restoration must survive formatting that wraps the generated helper call.
local before = {
  'def train(train_loader):',
  '    assert len(train_loader), "need a valid len"',
  'train({1})',
}
reset('', 0, '')
vim.api.nvim_buf_set_lines(0, 0, -1, false, before)
vim.api.nvim_win_set_cursor(0, { 2, 4 })
vim.api.nvim_feedkeys(' la', 'xt', false)
local formatted = vim
  .system({ vim.fn.stdpath 'data' .. '/mason/bin/ruff', 'format', '--stdin-filename', 'train.py', '-' }, {
    stdin = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'),
    text = true,
  })
  :wait()
assert(formatted.code == 0, formatted.stderr)
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.trim(formatted.stdout), '\n', { plain = true }))
require('chainsaw').removeLogs()
local restored = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(restored:find(before[2], 1, true) and not restored:find('nvim_debug.py', 1, true), restored)
-- Diagnostics coexist with the original message and both remain failure-only.
for _, succeeds in ipairs { false, true } do
  reset('', 0, 'diagnostic()')
  local lines = {
    'calls = []',
    'def condition(): calls.append("condition"); return ' .. (succeeds and 'True' or 'False'),
    'def diagnostic(): calls.append("observed"); return None',
    'def message(): calls.append("message"); return "need a valid len"',
    'def train():',
    '    assert condition(), message()',
    'try:',
    '    train()',
    'except AssertionError as error:',
    '    assert error.args == ("need a valid len",)',
    'assert calls == ' .. (succeeds and '["condition"]' or '["condition", "observed", "message"]'),
  }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 6, 4 })
  vim.api.nvim_feedkeys(' la', 'xt', false)
  assert(prompted and not warning, warning)
  local result = vim.system({ 'python3', '-c', table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  if succeeds then
    assert(result.stderr == '', result.stderr)
  else
    assert(result.stderr:find('│  condition  condition()', 1, true), result.stderr)
    assert(result.stderr:find('│  observed   diagnostic() → None', 1, true), result.stderr)
    assert(result.stderr:find('│  message    need a valid len', 1, true), result.stderr)
  end
end
-- Cancelling must leave an existing assertion untouched.
reset('assert False, "original"', 0, nil)
vim.api.nvim_feedkeys(' la', 'xt', false)
assert(prompted and not warning and vim.api.nvim_get_current_line() == 'assert False, "original"')
-- Do not replace changed source while an asynchronous prompt is open.
reset('assert False, "original"', 0, '')
vim.ui.input = function(_, callback)
  vim.api.nvim_set_current_line 'assert True, "edited"'
  callback ''
end
vim.api.nvim_feedkeys(' la', 'xt', false)
assert(warning and vim.api.nvim_get_current_line() == 'assert True, "edited"')
vim.ui.input, vim.notify = input, notify
print 'PASS: assertion N/v/V mappings, existing statements, lazy messages, optimization, restoration, validation, and cancellation'
