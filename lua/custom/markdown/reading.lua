local M = {}
local enabled = true
local mapped, windows, configs, controllers = {}, {}, {}, {}
local hidden_diagnostics = {}
local snacks_ready = false
local math_generation = 0

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

-- Install after Snacks loads, before its scheduled Markdown image attachment.
function M.setup_snacks()
  if snacks_ready then return end
  snacks_ready = true
  local inline = Snacks.image.inline
  -- A parse begun under an old theme must not restore old-colored placements
  -- after the new theme's refresh has completed.
  local visible = Snacks.image.doc.find_visible
  local visible_requests = {}
  Snacks.image.doc.find_visible = function(buf, callback)
    if vim.bo[buf].filetype ~= 'markdown' then return visible(buf, callback) end
    local generation = math_generation
    local request = (visible_requests[buf] or 0) + 1
    visible_requests[buf] = request
    visible(buf, function(images)
      if generation == math_generation and visible_requests[buf] == request then callback(images) end
    end)
  end
  local new, conceal = inline.new, inline.conceal
  inline.new = function(buf)
    local controller = new(buf)
    controllers[buf] = controller
    return controller
  end
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('custom-markdown-math-colors', { clear = true }),
    callback = function()
      math_generation = math_generation + 1
      local generation = math_generation
      -- Run after all ColorScheme handlers have applied the new highlight.
      vim.schedule(function()
        if generation ~= math_generation then return end
        for buf, controller in pairs(controllers) do
          if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'markdown' then
            for id, p in pairs(controller.imgs) do
              if p.opts.type == 'math' then
                p:close()
                -- An already queued debounce/conversion update must stay closed.
                p.ready = function() return false end
                controller.imgs[id] = nil
              end
            end
            for id, p in pairs(controller.idx) do
              if p.opts.type == 'math' then controller.idx[id] = nil end
            end
            controller:update()
          end
        end
      end)
    end,
  })
  inline.conceal = function(self)
    if vim.bo[self.buf].filetype ~= 'markdown' then return conceal(self) end
    local current = vim.api.nvim_get_current_buf() == self.buf
    if not current and not enabled then return end
    local from, to = vim.fn.line 'v', vim.fn.line '.'
    from, to = math.min(from, to), math.max(from, to)
    local mode = vim.fn.mode():sub(1, 1):lower()
    local reveal = current and (enabled and M.is_editing() or not enabled and not vim.wo.concealcursor:find(mode, 1, true))
    for _, img in pairs(self.imgs) do
      local range = img.opts.range
      -- Use the source range, not extmarks: conversion can finish after the
      -- cursor enters Insert mode, before the first grid has been displayed.
      if reveal and img.opts.conceal and range and from <= range[3] and to >= range[1] then
        img:hide()
      else
        img:show()
      end
    end
  end
  local place = Snacks.image.placement.new
  Snacks.image.placement.new = function(buf, src, opts)
    if opts and opts.inline and opts.on_update and vim.bo[buf].filetype == 'markdown' then
      opts = vim.tbl_extend('force', {}, opts)
      local update = opts.on_update
      opts.on_update = function(p)
        update(p)
        vim.schedule(function()
          if controllers[buf] and vim.api.nvim_buf_is_valid(buf) then controllers[buf]:conceal() end
        end)
      end
    end
    return place(buf, src, opts)
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
