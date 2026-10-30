-- One quiet, throttled progress item for the current note's preparation queue.
local M = {}
local group_name = 'Markdown math'
local delay_ms, throttle_ms = 750, 250

function M.setup()
  if M.installed then return end
  M.installed = true
  local prepare = require 'custom.markdown_prepare'
  local timer = vim.uv.new_timer()
  local version, started, handle, completed, stopped, owned
  local function clear()
    if handle then
      handle:cancel()
      handle = nil
    end
    if owned then
      require('fidget.notification').clear(group_name)
      owned = false
    end
  end
  local function update()
    local buf = vim.api.nvim_get_current_buf()
    local status = prepare.status(buf)
    local next_version = status and status.version
    if next_version ~= version then
      clear()
      version, started, completed = next_version, vim.uv.hrtime(), false
    end
    if not status or completed then return end
    if status.done and not handle then
      completed = true -- Cached/small notes never need a popup.
      return
    end
    if not handle and (vim.uv.hrtime() - started) / 1e6 < delay_ms then
      M.schedule()
      return
    end
    if not handle then
      local ok, progress = pcall(require, 'fidget.progress')
      if not ok then return end
      handle = progress.handle.create {
        title = 'Math · ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t'),
        lsp_client = { name = group_name },
      }
      owned = true
    end
    local processed = status.ready + status.failed
    local message = status.discovering and (processed .. ' prepared, discovering…') or ('%d/%d prepared'):format(processed, status.total)
    if status.paused and not status.done then message = 'Paused · ' .. message end
    if status.done then
      message = status.failed > 0 and ('%d ready, %d failed'):format(status.ready, status.failed) or ('Ready · %d prepared'):format(status.ready)
    end
    -- A fresh viewport query may briefly reopen discovery after totals were known.
    if status.discovering then handle.percentage = nil end
    handle:report {
      message = message,
      percentage = not status.discovering and (status.total == 0 and 100 or math.floor(processed / status.total * 100)) or nil,
    }
    if status.done then
      handle:finish()
      handle, completed = nil, true
    end
  end
  function M.schedule()
    if stopped or timer:is_active() then return end
    timer:start(
      throttle_ms,
      0,
      vim.schedule_wrap(function()
        if not stopped then update() end
      end)
    )
  end
  prepare.on_update = M.schedule
  local group = vim.api.nvim_create_augroup('custom-markdown-progress', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'ModeChanged' }, { group = group, callback = M.schedule })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      stopped = true
      timer:stop()
      timer:close()
      clear()
    end,
  })
  M.schedule()
end

return M
