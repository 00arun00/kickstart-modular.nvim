-- Run: nvim --headless -n -u NONE -i NONE -l tests/chainsaw_dap.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local panel = require 'custom.chainsaw.dap'
local function listeners()
  return setmetatable({}, {
    __index = function(t, key)
      local value = {}
      rawset(t, key, value)
      return value
    end,
  })
end
local dap = { listeners = { before = listeners(), after = listeners() } }
panel.setup(dap)
local function event(when, name, session, body) dap.listeners[when][name]['nvim-debug-panel'](session, body or {}) end
local function session()
  return {
    pending = {},
    request = function(self, method, args, callback) self.pending[#self.pending + 1] = { method = method, args = args, callback = callback } end,
  }
end
local function visible()
  local state = panel.state()
  return state.window and vim.api.nvim_win_is_valid(state.window)
end
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
for _, ft in ipairs { 'python', 'rust', 'cpp', 'lua' } do
  local file = dir .. '/source.' .. ft
  vim.fn.writefile({ 'first', 'second', 'current_statement', 'next_statement' }, file)
  local s = session()
  event('after', 'event_stopped', s, { reason = 'breakpoint', threadId = 1 })
  assert(not visible(), 'No panel before actual frame data')
  s.pending[1].callback(nil, { stackFrames = { { id = 1, name = 'training_step', line = 3, source = { path = file } } } })
  assert(vim.wait(1000, visible, 10))
  local text = table.concat(vim.api.nvim_buf_get_lines(panel.state().buffer, 0, -1, false), '\n')
  assert(text:find('PAUSED', 1, true) and text:find('→ 3  current_statement', 1, true), text)
  event('before', 'event_continued', s, { threadId = 1 })
  assert(not visible())
  print('PASS: ' .. ft .. ' pause panel from DAP frames and continued event')
end
-- Resume before an asynchronous frame/source response: never reopen stale UI.
local s = session()
event('after', 'event_stopped', s, { threadId = 1, reason = 'step' })
event('before', 'event_continued', s, { threadId = 1 })
s.pending[1].callback(nil, { stackFrames = { { name = 'stale', line = 1 } } })
vim.wait(20, function() return false end)
assert(not visible())
event('after', 'event_stopped', s, { threadId = 1, reason = 'step' })
s.pending[2].callback(nil, { stackFrames = { { name = 'virtual', line = 2, source = { name = 'remote.py', sourceReference = 42 } } } })
assert(s.pending[3].method == 'source')
event('before', 'event_terminated', s, {})
s.pending[3].callback(nil, { content = 'a\nb\nc' })
vim.wait(20, function() return false end)
assert(not visible())
-- A successful virtual source is rendered, without reading a guessed local path.
event('after', 'event_stopped', s, { threadId = 1, reason = 'step' })
s.pending[4].callback(nil, { stackFrames = { { name = 'virtual', line = 2, source = { name = 'remote.py', sourceReference = 42 } } } })
s.pending[5].callback(nil, { content = 'a\nb\nc' })
assert(vim.wait(1000, visible, 10))
local text = table.concat(vim.api.nvim_buf_get_lines(panel.state().buffer, 0, -1, false), '\n')
assert(text:find('remote.py:2', 1, true) and text:find('→ 2  b', 1, true), text)
-- A late step response must not close the newer stop's panel.
s.stopped_thread_id = 1
dap.listeners.after.next['nvim-debug-panel'](s, nil)
assert(visible())
s.stopped_thread_id = nil
dap.listeners.after.next['nvim-debug-panel'](s, nil)
assert(not visible())
-- Events from another session must not dismiss this session's pause.
event('after', 'event_stopped', s, { threadId = 1, reason = 'breakpoint' })
s.pending[6].callback(nil, { stackFrames = { { name = 'unknown', line = 0 } } })
assert(vim.wait(1000, visible, 10))
event('before', 'event_exited', session(), {})
assert(visible())
event('before', 'event_exited', s, {})
assert(not visible())
vim.fn.delete(dir, 'rf')
print 'PASS: stale-response protection, virtual sources, unavailable sources, and session isolation'
