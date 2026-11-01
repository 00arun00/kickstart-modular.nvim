-- A document revision owns its presentation. Scrolling only moves through the
-- existing decorations; discovery and conversion run after source/style changes.
local M = {}
local documents, converting = {}, {}
local style = 0
local Controller = {}
Controller.__index = Controller

local function valid(self)
  return not self.closed and vim.api.nvim_buf_is_valid(self.buf) and vim.api.nvim_buf_is_loaded(self.buf) and vim.bo[self.buf].filetype == 'markdown'
end

local function editing(self) return vim.api.nvim_get_current_buf() == self.buf and require('custom.markdown.reading').is_editing() end

local function convert(src, callback)
  if converting[src] then
    converting[src][#converting[src] + 1] = callback
    return
  end
  converting[src] = { callback }
  local function done(result)
    local callbacks = converting[src]
    converting[src] = nil
    for _, notify in ipairs(callbacks or {}) do
      notify(result:error())
    end
  end
  local ok, err = pcall(function() Snacks.image.convert.convert({ src = src, on_done = done }):run() end)
  if not ok then done { error = function() return err end } end
end

local function retire(placement) placement:close() end

function Controller:_clear()
  for _, placement in pairs(self.imgs) do
    retire(placement)
  end
  self.imgs, self.idx = {}, {}
  if self.tables then require('custom.markdown.tables').release(self.tables) end
  self.tables = nil
  self.ready = false
end

function Controller:close()
  if self.closed then return end
  self.closed = true
  self.version = self.version + 1
  self:_clear()
  documents[self.buf] = nil
  if vim.api.nvim_buf_is_valid(self.buf) then vim.b[self.buf].snacks_image_attached = nil end
  pcall(vim.api.nvim_del_augroup_by_id, self.group)
end

function Controller:_current(version)
  return valid(self) and self.version == version and self.tick == vim.api.nvim_buf_get_changedtick(self.buf) and self.style == style
end

function Controller:conceal()
  if not valid(self) then return end
  local reading = require 'custom.markdown.reading'
  local current = vim.api.nvim_get_current_buf() == self.buf
  if current or reading.is_enabled() then
    local mode = vim.fn.mode():sub(1, 1)
    local row, other = vim.fn.line '.', vim.fn.line '.'
    if mode == 'v' or mode == 'V' or mode == '\22' then other = vim.fn.line 'v' end
    local from, to = math.min(row, other), math.max(row, other)
    local reveal = current and (reading.is_enabled() and editing(self) or not reading.is_enabled() and not vim.wo.concealcursor:find(mode:lower(), 1, true))
    for _, placement in pairs(self.imgs) do
      local range = placement.opts.range
      if reveal and placement.opts.conceal and range and from <= range[3] and to >= range[1] then
        placement:hide()
      else
        placement:show()
      end
    end
  end
  if self.tables then require('custom.markdown.tables').publish(self.tables) end
end

function Controller:_settle(version)
  if self.materializing or not self:_current(version) or self.published ~= version then return end
  for _, placement in pairs(self.imgs) do
    if not placement._state then return end
  end
  local tables = require 'custom.markdown.tables'
  if self.tables then
    tables.publish(self.tables)
    if not tables.ready(self.tables) then return end
  end
  self.ready, self.phase = true, 'ready'
  self:conceal()
end

function Controller:_publish(items, failed, version)
  if not self:_current(version) then return end
  if editing(self) then
    self.dirty, self.phase = true, 'editing'
    return
  end
  local previous = self.imgs
  self.imgs, self.idx = {}, {}
  self.ready, self.materializing = false, true
  self.phase, self.published = 'rendering', version
  local tables = require 'custom.markdown.tables'
  if self.tables then tables.release(self.tables) end
  self.tables = tables.build(self.buf, items)
  self.tables.on_change = function() self:_settle(version) end
  tables.prepare(self.tables, failed)
  local conceal = Snacks.image.config.doc.conceal
  for _, item in ipairs(items) do
    if not failed[item.src] and not tables.contains(self.tables, item) then
      local opts = vim.tbl_extend('force', {}, Snacks.image.config.doc, {
        pos = item.pos,
        range = item.range,
        inline = true,
        type = item.type,
        conceal = vim.b[self.buf].snacks_image_conceal or (type(conceal) == 'function' and conceal(item.lang, item.type) or conceal == true),
        on_update = function(p)
          if not self:_current(version) then return end
          for _, id in ipairs(p.eids) do
            self.idx[id] = p
          end
          self:_settle(version)
        end,
      })
      local placement
      -- Styling math must not recreate unaffected charts or attachments.
      for id, old in pairs(previous) do
        if item.type ~= 'math' and old.opts.type == item.type and old.img.src == item.src and vim.deep_equal(old.opts.range, item.range) then
          placement, previous[id] = old, nil
          placement.opts = opts
          break
        end
      end
      placement = placement or Snacks.image.placement.new(self.buf, item.src, opts)
      self.imgs[placement.id] = placement
      for _, id in ipairs(placement.eids) do
        self.idx[id] = placement
      end
    end
  end
  for _, placement in pairs(previous) do
    retire(placement)
  end
  -- The instance method debounces updates. Establish this complete revision
  -- through Snacks' native implementation before marking the document ready.
  for _, placement in pairs(self.imgs) do
    Snacks.image.placement.update(placement)
  end
  self.materializing = false
  vim.schedule(function() self:_settle(version) end)
end

function Controller:_prepare(items, version)
  if not self:_current(version) then return end
  if editing(self) then
    self.dirty, self.phase = true, 'editing'
    return
  end
  self.phase = 'converting'
  local sources, failed = {}, {}
  for _, item in ipairs(items) do
    if item.src then sources[item.src] = true end
  end
  self.total, self.completed, self.failed = vim.tbl_count(sources), 0, 0
  local remaining = self.total
  if remaining == 0 then return self:_publish(items, failed, version) end
  for src in pairs(sources) do
    local function done(err)
      if not self:_current(version) then return end
      if err then
        failed[src], self.failures[src] = true, err
        self.failed = self.failed + 1
      end
      self.completed = self.completed + 1
      remaining = remaining - 1
      if remaining == 0 then self:_publish(items, failed, version) end
    end
    if self.failures[src] then
      done(self.failures[src])
    else
      convert(src, done)
    end
  end
end

function Controller:_start()
  self.queued = false
  if not valid(self) or not self.dirty or self.parsing then return end
  if editing(self) then
    self.phase = 'editing'
    return
  end
  self.dirty, self.parsing = false, true
  self.tick, self.style = vim.api.nvim_buf_get_changedtick(self.buf), style
  self.phase = 'discovering'
  local version = self.version
  local ok, err = pcall(Snacks.image.doc.find, self.buf, function(items)
    self.parsing = false
    if not self:_current(version) then
      if valid(self) and self.dirty then self:update() end
      return
    end
    self:_prepare(items, version)
  end)
  if not ok then
    self.parsing = false
    if self:_current(version) then
      self.phase, self.error = 'failed', tostring(err)
      vim.notify('Markdown rendering: ' .. tostring(err), vim.log.levels.WARN)
    end
  end
end

function Controller:update(force)
  if not valid(self) then return self:close() end
  local changed = self.tick ~= vim.api.nvim_buf_get_changedtick(self.buf)
  if force or changed or self.style ~= style then
    if not self.dirty or force then self.version = self.version + 1 end
    self.dirty, self.ready, self.error = true, false, nil
    self.phase = editing(self) and 'editing' or 'discovering'
    if changed then self:_clear() end
    if force then self.failures = {} end
  end
  if not self.dirty then return self:conceal() end
  if self.queued then return end
  self.queued = true
  vim.schedule(function() self:_start() end)
end

function Controller:resize()
  if not valid(self) then return end
  if self.published == self.version then
    self.ready, self.phase = false, 'rendering'
  end
  for _, placement in pairs(self.imgs) do
    Snacks.image.placement.update(placement)
  end
  self:conceal()
  self:_settle(self.version)
end

function Controller:status()
  return {
    phase = self.closed and 'closed' or editing(self) and 'editing' or self.phase,
    ready = self.ready and not editing(self),
    version = self.version,
    total = self.total,
    completed = self.completed,
    failed = self.failed,
    error = self.error,
  }
end

function M.status(buf)
  local self = documents[(not buf or buf == 0) and vim.api.nvim_get_current_buf() or buf]
  return self and self:status() or nil
end

function M.new(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  if documents[buf] then return documents[buf] end
  M.setup()
  local self =
    setmetatable({ buf = buf, imgs = {}, idx = {}, version = 0, failures = {}, phase = 'discovering', total = 0, completed = 0, failed = 0 }, Controller)
  documents[buf] = self
  self.group = vim.api.nvim_create_augroup('custom-markdown-document-' .. buf, { clear = true })
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if not valid(self) then return true end
      -- Old range coordinates no longer describe the edited source. Retire its
      -- decorations immediately; the next reading revision is built afterward.
      self.version = self.version + 1
      self.dirty = true
      self:_clear()
      self:update()
    end,
    on_detach = function() self:close() end,
  })
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged', 'ModeChanged' }, {
    group = self.group,
    buffer = buf,
    callback = function() self:update() end,
  })
  vim.api.nvim_create_autocmd('CursorMoved', { group = self.group, buffer = buf, callback = function() self:conceal() end })
  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, { group = self.group, buffer = buf, callback = function() self:close() end })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
    group = self.group,
    buffer = buf,
    callback = function()
      self:update()
      self:resize()
    end,
  })
  self:update()
  return self
end

function M.setup()
  if M.installed then return end
  M.installed = true
  local group = vim.api.nvim_create_augroup('custom-markdown-documents', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      style = style + 1
      vim.schedule(function()
        for _, self in pairs(documents) do
          self:update()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = group,
    callback = function()
      for _, self in pairs(documents) do
        self:resize()
      end
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(event)
      if documents[event.buf] then documents[event.buf]:update() end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'MarkdownReadingChanged',
    callback = function()
      for _, self in pairs(documents) do
        self:conceal()
      end
    end,
  })
end

return M
