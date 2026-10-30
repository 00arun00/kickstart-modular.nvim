local M = {}

local function display_equation(p)
  if p.opts.type ~= 'math' or not p.opts.inline or vim.bo[p.buf].filetype ~= 'markdown' then return false end
  local r = p.opts.range
  if not r then return false end
  local lines = vim.api.nvim_buf_get_lines(p.buf, r[1] - 1, r[3], false)
  if #lines == 0 then return false end
  if lines[1]:sub(1, r[2]):find '%S' or lines[#lines]:sub(r[4] + 1):find '%S' then return false end
  local text = table.concat(vim.api.nvim_buf_get_text(p.buf, r[1] - 1, r[2], r[3] - 1, r[4], {}), '\n')
  return text:match '^%$%$' ~= nil and text:match '%$%$$' ~= nil
end

-- Called by Snacks before updating a document image. Keep its source range
-- intact; only shift the generated image decorations, never buffer text.
function M.prepare(p)
  if not p._markdown_math then
    p._markdown_math = { max_width = p.opts.max_width }
    local state, render = p.state, p._render
    -- Include the offset in Snacks' state so resizing also redraws equations
    -- whose image dimensions stay the same.
    p.state = function(self)
      local result = state(self)
      local width = self._markdown_math.width
      if width then result.loc[2] = math.max(0, math.floor((width - result.loc.width) / 2)) end
      return result
    end
    p._render = function(self, marks)
      if self._markdown_math.width and self._state then
        local offset = self._state.loc[2]
        for _, mark in ipairs(marks) do
          if mark.virt_text then
            mark.virt_text_pos = 'overlay'
            mark.virt_text_win_col = offset
          end
          for _, line in ipairs(mark.virt_lines or {}) do
            local padding = { string.rep(' ', offset) }
            if line[1] and not line[1][2] then
              line[1] = padding
            else
              table.insert(line, 1, padding)
            end
          end
        end
      end
      return render(self, marks)
    end
  end

  local saved = p._markdown_math
  saved.width = nil
  p.opts.max_width = saved.max_width
  if not display_equation(p) then return end
  -- Decorations are buffer-scoped, like Snacks' image sizing. Fit the smallest
  -- visible text area when the note is shown in differently sized splits.
  for _, win in ipairs(p:wins()) do
    local info = vim.fn.getwininfo(win)[1]
    local width = math.max(1, info.width - info.textoff)
    saved.width = math.min(saved.width or width, width)
  end
  if saved.width then p.opts.max_width = math.min(saved.max_width or saved.width, saved.width) end
end

return M
