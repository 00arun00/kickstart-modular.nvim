-- Controlled conversion completion with real document discovery and placements.
-- The transport cannot verify terminal pixels; tests assert emitted UI grids.
local M = {}

function M.transport()
  local f = { images = {}, cached = {}, starts = {}, pending = {}, conversions = {}, hold = false }
  local image_id, placement_id = 100, 200
  local function info(src)
    local inline = src:match '%.inline%-math%.tex$' ~= nil
    return { size = { width = inline and 70 or 280, height = inline and 22 or 80 }, dpi = { width = 96, height = 96 } }
  end
  local function complete(c, failed)
    c._done, c._err = true, failed and 'controlled conversion failure' or nil
    c.steps[1].done = not failed
    f.cached[c.src] = not failed
    if c.opts.on_done then c.opts.on_done(c) end
  end
  Snacks.image.convert.convert = function(opts)
    local c =
      { opts = opts, src = opts.src, file = opts.src .. '.test.png', steps = { { done = f.cached[opts.src] == true } }, meta = { info = info(opts.src) } }
    function c:error() return self._err end
    function c:done() return self._done == true end
    function c:run()
      if self._done then return end
      if f.cached[self.src] then return complete(self) end
      f.starts[#f.starts + 1] = self.src
      if f.hold then
        f.pending[#f.pending + 1] = self
      else
        complete(self)
      end
    end
    f.conversions[#f.conversions + 1] = c
    return c
  end
  function f.finish(index, failed)
    local c = assert(table.remove(f.pending, index or 1), 'no pending conversion')
    complete(c, failed)
    return c.src
  end
  function f.finish_all(failed)
    local pending = f.pending
    f.pending = {}
    for _, c in ipairs(pending) do
      complete(c, failed)
    end
  end
  Snacks.image.image.new = function(src)
    if not f.images[src] then
      image_id = image_id + 1
      f.images[src] = {
        src = src,
        id = image_id,
        file = src,
        info = info(src),
        placements = {},
        ready = function() return true end,
        failed = function() return false end,
        place = function(self, p)
          if not p.id then
            placement_id = placement_id + 1
            p.id = placement_id
          end
          self.placements[p.id] = p
        end,
        del = function(self, id) self.placements[id] = nil end,
      }
    end
    return f.images[src]
  end
  return f
end

return M
