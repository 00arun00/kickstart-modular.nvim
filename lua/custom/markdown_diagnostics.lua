local M = {}
local enabled = true
local hidden = {}
local mapped = {}

function M.is_enabled() return enabled end

local function refresh(buf)
  local markdown = vim.bo[buf].filetype == 'markdown'
  if markdown and not enabled then
    if vim.diagnostic.is_enabled { bufnr = buf } then
      hidden[buf] = true
      -- This hides decorations and future updates, but retains diagnostic data.
      vim.diagnostic.enable(false, { bufnr = buf })
    end
  elseif hidden[buf] then
    hidden[buf] = nil
    vim.diagnostic.enable(true, { bufnr = buf })
  end
  if markdown then
    mapped[buf] = true
    vim.keymap.set('n', '<leader>Td', M.toggle, {
      buffer = buf,
      desc = (enabled and 'Hide' or 'Show') .. ' Markdown diagnostics (all buffers)',
    })
  elseif mapped[buf] then
    mapped[buf] = nil
    pcall(vim.keymap.del, 'n', '<leader>Td', { buffer = buf })
  end
end

function M.toggle()
  enabled = not enabled
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then refresh(buf) end
  end
  vim.api.nvim_exec_autocmds('User', { pattern = 'MarkdownDiagnosticsChanged', modeline = false })
end

function M.setup()
  local group = vim.api.nvim_create_augroup('custom-markdown-diagnostics', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter' }, {
    group = group,
    callback = function(event) refresh(event.buf) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      hidden[event.buf] = nil
      mapped[event.buf] = nil
    end,
  })
end

return M
