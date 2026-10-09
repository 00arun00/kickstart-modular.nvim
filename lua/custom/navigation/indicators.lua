local M = {}
local tick, buffers

-- Rank Neotest's hardcoded priority 1000 below diagnostics and DAP, without
-- changing its signs or patching the plugin. Cache once per buffer per redraw.
function M.render(args)
  if tick ~= args.tick then
    tick, buffers = args.tick, {}
  end
  if not buffers[args.buf] then
    local namespaces = vim.api.nvim_get_namespaces()
    local excluded = {}
    for name, id in pairs(namespaces) do
      if name == 'gutter_marks' or name:match '^gitsigns' then excluded[id] = true end
    end
    local signs = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(args.buf, -1, 0, -1, { type = 'sign', details = true })) do
      local details = mark[4]
      if details.sign_text and not excluded[details.ns_id] then
        local priority = (details.sign_name or ''):match '^neotest_' and 5 or details.priority
        local line = mark[2] + 1
        if not signs[line] or priority > signs[line].priority then
          signs[line] = { priority = priority, text = details.sign_text, hl = details.sign_hl_group, cursor_hl = details.cursorline_hl_group }
        end
      end
    end
    buffers[args.buf] = signs
  end
  local signs = buffers[args.buf]
  if not next(signs) then return '' end
  local sign = args.virtnum == 0 and signs[args.lnum]
  if not sign then return '%#SignColumn# %*' end
  local hl = (args.relnum == 0 and sign.cursor_hl) or sign.hl or 'SignColumn'
  return '%#' .. hl .. '#' .. sign.text:gsub('%s', ''):gsub('%%', '%%%%') .. '%*'
end

return M
