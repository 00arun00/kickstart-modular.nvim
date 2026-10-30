-- Deterministic conversion transport. Real buffer/window events and scheduler.
local root = ...
vim.opt.rtp:prepend(root)
local f = { matches = {}, starts = {}, running = 0, peak = 0, cached = {}, images = {}, delivered = {}, held = {}, scans = {} }
prepare_fixture = f
local convert = {}
function convert.convert(opts)
  local c = { opts = opts, src = opts.src, steps = { { done = f.cached[opts.src] == true } } }
  function c:error() return self._err end
  function c:run()
    self.steps[1].done = self.steps[1].done or f.cached[self.src] == true
    if self.steps[1].done then
      if self.opts.on_done then self.opts.on_done(self) end
      return
    end
    f.running = f.running + 1
    f.peak = math.max(f.peak, f.running)
    f.starts[#f.starts + 1] = self.src
    f.active = self
  end
  return c
end
function f.finish(failed)
  local c = assert(f.active, 'no active conversion')
  f.active = nil
  f.running = f.running - 1
  c.steps[1].done = true
  c._err = failed and 'invalid TeX' or nil
  f.cached[c.src] = not failed
  if c.opts.on_done then c.opts.on_done(c) end
end
local image = {}
function image:run() self._convert:run() end
function image.new(src)
  if f.images[src] then return f.images[src] end
  local img = setmetatable({ src = src }, { __index = image })
  f.images[src] = img
  img._convert = convert.convert {
    src = src,
    on_done = function() f.delivered[src] = true end,
  }
  img:run()
  return img
end
local doc = {}
function doc.find(buf, callback, opts)
  local result = {}
  for _, match in ipairs(f.matches[buf] or {}) do
    if not opts or (match.range[1] <= opts.to and match.range[3] >= opts.from) then result[#result + 1] = match end
  end
  if opts then f.scans[#f.scans + 1] = { opts.from, opts.to } end
  local deliver = function() callback(result) end
  if f.hold then
    f.held[#f.held + 1] = deliver
  else
    deliver()
  end
end
Snacks = {
  util = { parse = function(_, _, callback) callback() end },
  image = { doc = doc, image = image, convert = convert, supports_terminal = function() return true end },
}
function f.buffer(matches, lines)
  vim.cmd 'enew!'
  local buf = vim.api.nvim_get_current_buf()
  local source = {}
  for i = 1, lines or 1000 do
    source[i] = 'line ' .. i
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  vim.bo.filetype = 'markdown'
  vim.bo.modified = false
  f.matches[buf] = {}
  for i, pair in ipairs(matches) do
    f.matches[buf][i] = { src = pair[2], type = 'math', id = tostring(i), range = { pair[1], 0, pair[1], 3 } }
  end
  return buf
end
function f.query(buf, placements)
  doc.find(buf, function(items)
    if placements then
      for _, item in ipairs(items) do
        image.new(item.src)
      end
    end
  end)
end
require('custom.markdown_prepare').setup()
