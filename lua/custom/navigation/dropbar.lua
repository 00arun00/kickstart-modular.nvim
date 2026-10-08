local M = {}
local installed = false

function M.setup()
  if installed then return end
  installed = true

  -- Compatibility workaround for the pinned Dropbar revision: rebuilding a
  -- bar deletes its symbols and their open menus. Keep the snapshot alive until
  -- navigation finishes, then replay the refresh against the latest source.
  local bars = require('dropbar.bar').dropbar_t
  local menus = require('dropbar.menu').dropbar_menu_t
  local pending = setmetatable({}, { __mode = 'k' })
  local update, close = bars._update, menus.close

  local function has_menu(bar)
    for _, menu in pairs(require('dropbar.utils').menu.get() or {}) do
      local root = menu:root()
      if root.is_opened and root.prev_win == bar.win and root.prev_buf == bar.buf then return true end
    end
    return false
  end

  bars._update = function(self)
    if has_menu(self) then
      pending[self] = true
      return
    end
    pending[self] = nil
    return update(self)
  end

  menus.close = function(self, ...)
    close(self, ...)
    if next(pending) then
      -- Closing can recurse through submenus or be followed by a jump. Wait for
      -- that operation to finish and recheck whether a root menu is still open.
      vim.schedule(function()
        for bar in pairs(pending) do
          if not has_menu(bar) then bar:_update() end
        end
      end)
    end
  end
end

return M
