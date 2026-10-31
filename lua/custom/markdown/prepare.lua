-- One distance-ordered queue for Markdown math, including table equations.
-- Conversion stays in Snacks; background jobs only populate its disk cache.
local M = {}
local buffers, jobs, prepared, failed = {}, {}, {}, {}
local active, timer, pump, raw_find, raw_convert, image_run
local epoch, sequence, quiet_until = 0, 0, 0
local installed, exiting = false, false
local chunk_lines, idle_ms = 128, 120

local function now() return vim.uv.hrtime() / 1e6 end

local function kick()
  if exiting then return end
  if M.on_update then M.on_update() end
  timer:stop()
  timer:start(math.max(1, math.ceil(quiet_until - now())), 0, vim.schedule_wrap(pump))
end

local function current(buf, state)
  return buffers[buf] == state
    and state.epoch == epoch
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].filetype == 'markdown'
    and vim.api.nvim_buf_get_changedtick(buf) == state.tick
end

local function state_for(buf)
  if not buffers[buf] or not current(buf, buffers[buf]) then
    sequence = sequence + 1
    buffers[buf] = {
      tick = vim.api.nvim_buf_get_changedtick(buf),
      epoch = epoch,
      unseen = { { 1, vim.api.nvim_buf_line_count(buf) } },
      requests = {},
      sources = {},
      order = math.huge,
    }
  end
  return buffers[buf]
end

local function distance(buf, first, last, views)
  if not views[buf] then
    views[buf] = {}
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then views[buf][#views[buf] + 1] = vim.fn.getwininfo(win)[1] end
    end
  end
  local best, anchor = math.huge, first
  for _, view in ipairs(views[buf]) do
    local d = math.max(view.topline - last, first - view.botline, 0)
    if d < best then
      best, anchor = d, math.max(first, math.min(last, view.topline))
    end
  end
  return best, anchor
end

local function observe(buf, state, images)
  for _, image in ipairs(images) do
    if image.type == 'math' and image.src and image.range then state.sources[image.src] = true end
    if image.type == 'math' and image.src and image.range and not prepared[image.src] then
      local job = jobs[image.src]
      if not job then
        sequence = sequence + 1
        job = { src = image.src, owners = {}, order = sequence, failed = failed[image.src] }
        jobs[image.src] = job
      end
      local owner = job.owners[buf]
      if not owner or owner.state ~= state then
        owner = { state = state, ranges = {} }
        job.owners[buf] = owner
      end
      owner.ranges[table.concat(image.range, ':')] = { image.range[1], image.range[3] }
    end
  end
  kick()
end

local function cached(convert)
  for _, step in ipairs(convert.steps) do
    if not step.done then return false end
  end
  return true
end

local function finish(job, result)
  local error = result:error() ~= nil
  prepared[job.src], failed[job.src] = not error or nil, error or nil
  jobs[job.src] = nil
  active = nil
  -- A visible placement may have arrived during a background conversion. Its
  -- own converter now follows the ordinary cached path, with its own callbacks.
  if job.image and not job.started_image then
    if error then
      -- Let a foreground request report its own error through Snacks, still
      -- under the concurrency limit. Background failures never retry in a loop.
      job.failed, job.convert = false, nil
      jobs[job.src] = job
    else
      image_run(job.image)
    end
  end
  kick()
end

pump = function()
  if exiting or active or not Snacks.image.supports_terminal() or vim.fn.mode():match '^[iR]' then return end
  if now() < quiet_until then return kick() end
  local best, priority, order = nil, math.huge, math.huge
  -- Snapshot per buffer once, not one window/tick query per queued equation.
  local views, valid = {}, {}
  local function fresh(buf, state)
    if valid[buf] == nil then valid[buf] = buffers[buf] and current(buf, buffers[buf]) or false end
    return valid[buf] and buffers[buf] == state
  end
  local function consider(candidate, d, serial)
    if d < priority or (d == priority and d < math.huge and serial < order) then
      best, priority, order = candidate, d, serial
    end
  end
  for src, job in pairs(jobs) do
    local owned = false
    for buf, owner in pairs(job.owners) do
      if fresh(buf, owner.state) then
        owned = true
        for _, range in pairs(owner.ranges) do
          if not job.failed then consider(job, distance(buf, range[1], range[2], views), job.order) end
        end
      else
        job.owners[buf] = nil
      end
    end
    -- Pending image objects belong to Snacks' cache. Park them until requested
    -- again; aborting would poison that cache entry. Unrequested work is dropped.
    if not owned and not job.image then jobs[src] = nil end
  end
  for buf, state in pairs(buffers) do
    if fresh(buf, state) then
      for _, request in pairs(state.requests) do
        consider(request, distance(buf, request.first, request.last, views), request.order)
      end
      for index, range in ipairs(state.unseen) do
        local d, anchor = distance(buf, range[1], range[2], views)
        consider({ buf = buf, state = state, index = index, anchor = anchor }, d, state.order)
      end
    end
  end
  if not best then return end -- Hidden buffers wait for BufWinEnter; no polling.
  active = best
  if best.src then
    if best.image then
      best.started_image = true
      local convert = best.image._convert
      local done = convert.opts.on_done
      convert.opts.on_done = function(result)
        if done then done(result) end
        finish(best, result)
      end
      image_run(best.image)
    else
      best.convert = raw_convert { src = best.src, on_done = function(result) finish(best, result) end }
      best.convert:run()
    end
  else
    local state = best.state
    local first, last = best.first, best.last
    if first then
      state.requests[best.key] = nil
      local remaining = {}
      for _, range in ipairs(state.unseen) do
        if range[2] < first or range[1] > last then
          remaining[#remaining + 1] = range
        else
          if range[1] < first then remaining[#remaining + 1] = { range[1], first - 1 } end
          if last < range[2] then remaining[#remaining + 1] = { last + 1, range[2] } end
        end
      end
      state.unseen = remaining
    else
      local range = table.remove(state.unseen, best.index)
      first = math.max(range[1], math.min(best.anchor, range[2] - chunk_lines + 1))
      last = math.min(range[2], first + chunk_lines - 1)
      if range[1] < first then state.unseen[#state.unseen + 1] = { range[1], first - 1 } end
      if last < range[2] then state.unseen[#state.unseen + 1] = { last + 1, range[2] } end
    end
    local function find()
      raw_find(best.buf, function(images)
        if current(best.buf, state) then
          observe(best.buf, state, images)
          for _, callback in ipairs(best.callbacks or {}) do
            callback(images)
          end
          sequence = sequence + 1
          state.order = sequence
        end
        active = nil
        kick()
      end, { from = first, to = last })
    end
    -- Snacks' query bounds are one-based, but its ranged parser call passes
    -- them through unchanged. Prime the correct zero-based range first so the
    -- first source line's injected LaTeX tree is not missed.
    local ok, parser = pcall(vim.treesitter.get_parser, best.buf)
    if ok then
      Snacks.util.parse(parser, { first - 1, last }, find)
    else
      find()
    end
  end
end

-- Tables need all cells together to calculate column widths, but their source
-- discovery obeys the same queue/distance rule as individual equation work.
function M.find(buf, first, last, callback)
  if not installed then return Snacks.image.doc.find(buf, callback) end
  local state, key = state_for(buf), first .. ':' .. last
  local request = state.requests[key]
  if not request then
    sequence = sequence + 1
    request = { buf = buf, state = state, first = first, last = last, key = key, order = sequence, callbacks = {} }
    state.requests[key] = request
  end
  request.callbacks[#request.callbacks + 1] = callback
  kick()
end

-- Snapshot for progress consumers. Counts unique conversions, not occurrences.
function M.status(buf)
  local state = buffers[buf]
  if not state or not current(buf, state) then return end
  local status = { version = state, ready = 0, failed = 0, total = 0 }
  for src in pairs(state.sources) do
    status.total = status.total + 1
    if prepared[src] then
      status.ready = status.ready + 1
    elseif failed[src] and not (jobs[src] and not jobs[src].failed) then
      status.failed = status.failed + 1
    end
  end
  status.discovering = #state.unseen > 0 or next(state.requests) ~= nil or (active ~= nil and active.state == state)
  status.done = not status.discovering and status.ready + status.failed == status.total
  status.paused = vim.fn.mode():match '^[iR]' ~= nil
  return status
end

function M.setup()
  if installed then return end
  installed = true
  timer = vim.uv.new_timer()
  local doc, image = Snacks.image.doc, Snacks.image.image
  raw_find, raw_convert, image_run = doc.find, Snacks.image.convert.convert, image.run
  doc.find = function(buf, callback, opts)
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    if vim.bo[buf].filetype ~= 'markdown' then return raw_find(buf, callback, opts) end
    -- Serialize viewport queries too: concurrent ranged Tree-sitter parses can
    -- otherwise deliver incomplete injection results to the image controller.
    return M.find(buf, opts and opts.from or 1, opts and opts.to or vim.api.nvim_buf_line_count(buf), callback)
  end
  image.run = function(self)
    local job = jobs[self.src]
    if not job or prepared[self.src] then return image_run(self) end
    if cached(self._convert) then
      if active ~= job then jobs[self.src] = nil end
      prepared[self.src] = true
      return image_run(self)
    end
    job.image = self
    job.failed = false
    kick()
  end
  local group = vim.api.nvim_create_augroup('custom-markdown-prepare', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = function(event)
      if vim.bo[event.buf].filetype ~= 'markdown' or not Snacks.image.supports_terminal() then return end
      state_for(event.buf)
      quiet_until = now() + idle_ms
      kick()
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled', 'ModeChanged', 'WinEnter', 'TabEnter' }, {
    group = group,
    callback = function()
      quiet_until = now() + idle_ms
      kick()
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      epoch = epoch + 1
      buffers = {}
      quiet_until = now() + idle_ms
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'markdown' then state_for(buf) end
      end
      kick()
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      buffers[event.buf] = nil
      kick()
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      exiting = true
      timer:stop()
      timer:close()
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'markdown' then state_for(buf) end
  end
  quiet_until = now() + idle_ms
  kick()
end

return M
