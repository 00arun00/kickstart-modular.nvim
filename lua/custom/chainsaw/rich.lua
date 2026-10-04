-- Temporary statements reference these local helpers; target projects need no
-- package installation. C++ alone requires a marked header include.
local M = {}
local directory = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
M.directory = vim.fs.joinpath(directory, 'helpers')

function M.render(ft, action, expression, observed, marker, existing_assertion)
  local q = function(value) return require('custom.chainsaw').quote(ft, value) end
  local label, mark = q(expression or ''), q(marker)
  local argument = '(' .. (expression or '') .. ')'
  local methods = { reprLog = 'repr_log', objectLog = 'object_log', stacktraceLog = 'stack_log', assertLog = 'fail' }
  local method = methods[action]
  if not method then return end
  if action == 'reprLog' and (ft == 'python' or ft == 'rust' or ft == 'nvim_lua') then return end
  if ft == 'nvim_lua' then ft = 'lua' end
  local detail = observed and observed ~= '' and '(' .. observed .. ')' or q 'condition evaluated to false'
  local args = mark
  if action == 'objectLog' or action == 'reprLog' then args = args .. ', ' .. label .. ', ' .. argument end
  if action == 'assertLog' then args = args .. ', ' .. label .. ', ' .. detail end
  if ft == 'python' then
    if action == 'assertLog' then
      args = mark .. ', ' .. label
      if observed and observed ~= '' then args = args .. ', observed=(' .. observed .. '), observed_label=' .. q(observed) end
      if existing_assertion and existing_assertion.message then args = args .. ', message=(' .. existing_assertion.message .. ')' end
    end
    local call = '__import__("runpy").run_path(' .. q(M.directory .. '/nvim_debug.py') .. ')[' .. q(method) .. '](' .. args .. ')'
    if action == 'assertLog' then
      if existing_assertion then return 'assert ' .. argument .. ', ' .. call end
      return 'if not ' .. argument .. ': ' .. call
    end
    return call
  elseif ft == 'lua' then
    local call = 'dofile(' .. q(M.directory .. '/nvim_debug.lua') .. ').' .. method .. '(' .. args .. ')'
    if action == 'assertLog' then return 'if not ' .. argument .. ' then ' .. call .. ' end' end
    return call
  elseif ft == 'rust' then
    if action == 'objectLog' then args = mark .. ', ' .. label .. ', &' .. argument end
    if action == 'assertLog' then args = mark .. ', ' .. label .. ', &' .. detail end
    local call = '{ #[path = ' .. q(M.directory .. '/nvim_debug.rs') .. '] mod nvim_dbg; nvim_dbg::' .. method .. '(' .. args .. '); }'
    if action == 'assertLog' then call = 'if !' .. argument .. ' ' .. call end
    return call .. ' // ' .. marker
  elseif ft == 'cpp' then
    if action == 'assertLog' then args = args .. ', __FILE__, __LINE__' end
    local call = 'nvim_dbg::' .. method .. '(' .. args .. ');'
    if action == 'assertLog' then call = 'if (!' .. argument .. ') { ' .. call .. ' }' end
    return call, '#include ' .. q(M.directory .. '/nvim_debug.hpp') .. ' // ' .. marker
  end
end

function M.ensure_include(include)
  if not include then return end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:find('#include', 1, true) and line:find('nvim_debug.hpp', 1, true) then return end
  end
  -- Include outside functions/namespaces, after a possible shebang only.
  local row = lines[1] and lines[1]:match '^#!' and 1 or 0
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.cmd.undojoin()
  vim.api.nvim_buf_set_lines(0, row, row, false, { include })
  vim.api.nvim_win_set_cursor(0, { cursor[1] + 1, cursor[2] })
end
return M
