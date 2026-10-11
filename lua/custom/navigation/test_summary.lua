local installed = false

-- Neotest's follow event queues a canvas render. Its default renderer moves the
-- summary cursor whenever another window is focused, including an output popup.
-- Guard at render time: rejecting new follow events alone misses queued renders.
return function()
  if not installed then
    installed = true
    -- This adapter targets the canvas API in the pinned Neotest revision.
    local canvas = require 'neotest.consumers.summary.canvas'
    local new = canvas.new
    canvas.new = function(...)
      local instance = new(...)
      local render = instance.render_buffer
      instance.render_buffer = function(self, buffer)
        local position = self.position
        if vim.bo.filetype == 'neotest-output' then self.position = nil end
        -- Keep rendering results and mappings, but leave the user's summary
        -- selection alone while reading output. Source-buffer following stays on.
        local ok, result, err = pcall(render, self, buffer)
        self.position = position
        if not ok then error(result, 0) end
        return result, err
      end
      return instance
    end
  end
  return {}
end
