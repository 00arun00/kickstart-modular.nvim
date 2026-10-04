-- A debugger-owned pause panel. Never infer a pause from a printed message.
local M = {}
local generation = 0
local active, panel_buffer, panel_window

local function close_window()
  if panel_window and vim.api.nvim_win_is_valid(panel_window) then vim.api.nvim_win_close(panel_window, true) end
  panel_window = nil
end

function M.format(frame, event, source_lines, marker)
  local source = frame.source or {}
  local name = source.path and vim.fs.basename(source.path) or source.name or '<source unavailable>'
  local number = tonumber(frame.line) or 0
  local result = {
    ' ' .. marker .. ' break │ ' .. (event.description or event.reason or 'debugger stopped'),
    '    │',
    ('    │  %s:%d · %s'):format(name, number, frame.name or '<unknown frame>'),
    '    │',
  }
  if source_lines and number > 0 and source_lines[number] then
    local first, last = math.max(1, number - 2), math.min(#source_lines, number + 1)
    local width = #tostring(last)
    for row = first, last do
      result[#result + 1] = ('    │  %s %' .. width .. 'd  %s'):format(row == number and '→' or ' ', row, source_lines[row]:gsub('\t', '    '))
    end
    result[#result + 1] = '    ╰─ PAUSED · debugger location marked →'
  else
    result[#result + 1] = '    │  Source text unavailable'
    result[#result + 1] = '    ╰─ PAUSED'
  end
  return result
end

local function show(lines)
  if not panel_buffer or not vim.api.nvim_buf_is_valid(panel_buffer) then
    panel_buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[panel_buffer].buftype = 'nofile'
    vim.bo[panel_buffer].bufhidden = 'hide'
    vim.bo[panel_buffer].swapfile = false
    vim.bo[panel_buffer].filetype = 'nvim-debug-panel'
    vim.keymap.set('n', 'q', close_window, { buffer = panel_buffer, silent = true, desc = 'Close pause panel' })
  end
  vim.bo[panel_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(panel_buffer, 0, -1, false, lines)
  vim.bo[panel_buffer].modifiable = false
  local ns = vim.api.nvim_create_namespace 'nvim-debug-panel'
  vim.api.nvim_buf_clear_namespace(panel_buffer, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(panel_buffer, ns, 0, 0, { end_row = 1, hl_group = 'Title' })
  vim.api.nvim_buf_set_extmark(panel_buffer, ns, #lines - 1, 0, { end_row = #lines, hl_group = 'DiagnosticWarn' })
  if not panel_window or not vim.api.nvim_win_is_valid(panel_window) then
    panel_window = vim.api.nvim_open_win(panel_buffer, false, { split = 'below', win = 0, height = math.min(#lines, 13) })
    vim.wo[panel_window].number = false
    vim.wo[panel_window].relativenumber = false
    vim.wo[panel_window].signcolumn = 'no'
    vim.wo[panel_window].wrap = false
    vim.wo[panel_window].winfixheight = true
  end
end

local function cancel(session)
  if active and active.session == session then
    generation = generation + 1
    active = nil
    close_window()
  end
end

function M.setup(dap)
  dap = dap or require 'dap'
  local key = 'nvim-debug-panel'
  dap.listeners.after.event_stopped[key] = function(session, event)
    generation = generation + 1
    local token = generation
    active = { session = session, token = token }
    close_window()
    local function current() return active and active.session == session and active.token == token end
    local thread = event.threadId or session.stopped_thread_id
    if not thread then return end
    session:request('stackTrace', { threadId = thread, startFrame = 0, levels = 1 }, function(err, response)
      if not current() or err or not response or not response.stackFrames or not response.stackFrames[1] then return end
      local frame = response.stackFrames[1]
      local source = frame.source or {}
      local function display(lines)
        vim.schedule(function()
          if not current() then return end
          local ok, config = pcall(require, 'chainsaw.config.config')
          local marker = ok and config.config.marker or require('custom.chainsaw').marker
          show(M.format(frame, event, lines, marker))
        end)
      end
      if source.sourceReference and source.sourceReference > 0 then
        session:request(
          'source',
          { source = source, sourceReference = source.sourceReference },
          function(source_err, body) display(not source_err and body and body.content and vim.split(body.content, '\n') or nil) end
        )
      elseif source.path and vim.fn.filereadable(source.path) == 1 then
        -- Read the on-disk source; an unsaved editor buffer can differ from the
        -- actual program. Adapters with virtual sources use the source request.
        local ok, lines = pcall(vim.fn.readfile, source.path, '', (frame.line or 0) + 1)
        display(ok and lines or nil)
      else
        display(nil)
      end
    end)
  end
  for _, event in ipairs { 'event_continued', 'event_terminated', 'event_exited' } do
    dap.listeners.before[event][key] = function(session) cancel(session) end
  end
  -- Also invalidate pending responses when a continue/step request completes;
  -- adapters are not required to send a continued event for every request.
  for _, command in ipairs { 'continue', 'next', 'stepIn', 'stepOut', 'disconnect' } do
    dap.listeners.after[command][key] = function(session, err)
      if not err and (command == 'disconnect' or not session.stopped_thread_id) then cancel(session) end
    end
  end
end

function M.toggle_breakpoint()
  local dap = require 'dap'
  M.setup(dap)
  dap.toggle_breakpoint()
  local ft = vim.bo.filetype
  if not dap.configurations[ft] or #dap.configurations[ft] == 0 then
    vim.notify('Breakpoint set/toggled. Configure a ' .. ft .. ' DAP adapter and launch configuration to run to it.', vim.log.levels.INFO)
  end
end

-- Expose read-only state for integration checks and a manual close command.
function M.state() return { buffer = panel_buffer, window = panel_window, active = active ~= nil } end
M.close = close_window
return M
