local M = {}
local enabled = true
local mapped, windows, configs, controllers = {}, {}, {}, {}
local hidden_diagnostics = {}
local snacks_ready = false

function M.is_enabled() return enabled end

function M.is_editing()
  local mode = vim.fn.mode():sub(1, 1)
  return mode == 'i' or mode == 'R'
end

function M.apply_window(win)
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  local markdown = vim.bo[buf].filetype == 'markdown'
  if markdown then
    if not windows[win] then
      local cursor = vim.wo[win].concealcursor
      if enabled and cursor == 'nvc' then
        -- A new split inherits our reading setting from its parent. Preserve
        -- the parent's original setting rather than treating 'nvc' as a default.
        cursor = configs[buf] and configs[buf].cursor or vim.go.concealcursor
        for other, original in pairs(windows) do
          if vim.api.nvim_win_is_valid(other) and vim.api.nvim_win_get_buf(other) == buf then
            cursor = original.concealcursor
            break
          end
        end
      end
      windows[win] = { concealcursor = cursor }
    end
    -- Native conceal and Snacks keep Normal/Visual/command navigation rendered.
    -- Insert and Replace modes still expose source for editing.
    vim.wo[win].concealcursor = enabled and 'nvc' or windows[win].concealcursor
  elseif windows[win] then
    vim.wo[win].concealcursor = windows[win].concealcursor
    windows[win] = nil
  end
end

function M.attach(buf)
  if vim.bo[buf].filetype ~= 'markdown' then return end
  local state = package.loaded['render-markdown.state']
  if not (state and state.config) then return end
  local config = state.get(buf)
  if not configs[buf] or configs[buf].config ~= config then
    configs[buf] = { config = config, anti = config.anti_conceal.enabled, cursor = config.win_options.concealcursor.rendered }
  end
  config.anti_conceal.enabled = not enabled and configs[buf].anti
  config.win_options.concealcursor.rendered = enabled and 'nvc' or configs[buf].cursor
end

local function refresh_buffer(buf)
  local markdown = vim.bo[buf].filetype == 'markdown'
  if markdown and enabled then
    if vim.diagnostic.is_enabled { bufnr = buf } then
      hidden_diagnostics[buf] = true
      -- Suppress decorations/future display updates without clearing data.
      vim.diagnostic.enable(false, { bufnr = buf })
    end
  elseif hidden_diagnostics[buf] then
    hidden_diagnostics[buf] = nil
    vim.diagnostic.enable(true, { bufnr = buf })
  end
  if markdown then
    mapped[buf] = true
    vim.keymap.set('n', '<leader>Tr', M.toggle, { buffer = buf, desc = (enabled and 'Disable' or 'Enable') .. ' Markdown reading mode (all buffers)' })
    M.attach(buf)
  elseif mapped[buf] then
    mapped[buf] = nil
    configs[buf] = nil
    pcall(vim.keymap.del, 'n', '<leader>Tr', { buffer = buf })
  end
end

local function refresh_rendering()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      refresh_buffer(buf)
      if vim.bo[buf].filetype == 'markdown' and package.loaded['render-markdown'] then require('render-markdown').render { buf = buf } end
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.apply_window(win)
  end
  for buf, controller in pairs(controllers) do
    if vim.api.nvim_buf_is_valid(buf) and (enabled or vim.api.nvim_get_current_buf() == buf) then controller:conceal() end
  end
end

function M.toggle()
  enabled = not enabled
  refresh_rendering()
  vim.api.nvim_exec_autocmds('User', { pattern = 'MarkdownReadingChanged', modeline = false })
end

-- Select one document owner before Snacks schedules Markdown attachment.
-- Other document types and terminal fallbacks retain the native Snacks path.
function M.setup_snacks()
  if snacks_ready then return end
  snacks_ready = true
  local inline = Snacks.image.inline
  local new = inline.new
  inline.new = function(buf)
    if vim.bo[buf].filetype ~= 'markdown' or not Snacks.image.terminal.env().placeholders then return new(buf) end
    local controller = require('custom.markdown.document').new(buf)
    controllers[buf] = controller
    return controller
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('custom-markdown-reading', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function(event)
      refresh_buffer(event.buf)
      M.apply_window(vim.api.nvim_get_current_win())
    end,
  })
  vim.api.nvim_create_autocmd('ModeChanged', {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= 'markdown' then return end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        M.attach(buf)
        if package.loaded['render-markdown'] then require('render-markdown').render { buf = buf } end
        if controllers[buf] and vim.api.nvim_get_current_buf() == buf then controllers[buf]:conceal() end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      -- :enew can wipe and reuse the same empty buffer number. Release our
      -- diagnostic suppression before discarding the ownership record.
      if hidden_diagnostics[event.buf] and vim.api.nvim_buf_is_valid(event.buf) then vim.diagnostic.enable(true, { bufnr = event.buf }) end
      hidden_diagnostics[event.buf] = nil
      mapped[event.buf], configs[event.buf], controllers[event.buf] = nil, nil, nil
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(event) windows[tonumber(event.match)] = nil end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then refresh_buffer(buf) end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M.apply_window(win)
  end
end

return M
