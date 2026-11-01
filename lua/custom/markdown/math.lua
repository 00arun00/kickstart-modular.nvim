local M = {}
local installed = false

local function context(buf, r)
  if not r then return end
  local lines = vim.api.nvim_buf_get_lines(buf, r[1] - 1, r[3], false)
  if #lines == 0 then return end
  local prefix = lines[1]:sub(1, r[2])
  local rest, quotes = prefix:gsub('^%s*', ''), 0
  while rest:sub(1, 1) == '>' do
    rest, quotes = rest:sub(2):gsub('^%s*', ''), quotes + 1
  end
  rest = rest:gsub('^[-+*]%s+', ''):gsub('^%d+[.)]%s+', '')
  return {
    left = vim.fn.strdisplaywidth(prefix),
    quotes = quotes,
    standalone = not rest:find '%S' and not lines[#lines]:sub(r[4] + 1):find '%S',
  }
end

function M.setup()
  require('custom.markdown.inline').setup()
  if installed then return end
  installed = true
  local latex = Snacks.image.doc.transforms.latex
  Snacks.image.doc.transforms.latex = function(img, ctx)
    local text = vim.trim(img.content or '')
    local block = img.ext == 'math.tex' and text:match '^%$%$' and context(ctx.buf, img.range)
    if block and block.quotes > 0 then
      -- Tree-sitter's injected LaTeX range still contains Markdown blockquote
      -- prefixes on continuation lines. Remove only that structural depth;
      -- mathematical relations such as x > 0 remain part of the expression.
      local lines = vim.split(img.content, '\n', { plain = true })
      for i = 2, #lines do
        for _ = 1, block.quotes do
          lines[i] = lines[i]:gsub('^[ \t]*>[ \t]?', '', 1)
        end
      end
      img.content = table.concat(lines, '\n')
    end
    return latex(img, ctx)
  end
end

local function display_equation(p)
  if p.opts.type ~= 'math' or not p.opts.inline or vim.bo[p.buf].filetype ~= 'markdown' then return false end
  local r = p.opts.range
  if not r then return false end
  local text = table.concat(vim.api.nvim_buf_get_text(p.buf, r[1] - 1, r[2], r[3] - 1, r[4], {}), '\n')
  if not (text:match '^%$%$' and text:match '%$%$$') then return false end
  local block = context(p.buf, r)
  return block and block.standalone and block or false
end

-- Called by Snacks before updating a document image. Keep its source range
-- intact; only shift the generated image decorations, never buffer text.
function M.prepare(p)
  require('custom.markdown.inline').prepare(p)
  if not p._markdown_math then
    p._markdown_math = { max_width = p.opts.max_width }
    local state, render = p.state, p._render
    -- Include the offset in Snacks' state so resizing also redraws equations
    -- whose image dimensions stay the same.
    p.state = function(self)
      local result = state(self)
      local width = self._markdown_math.width
      if width then result.loc[2] = self._markdown_math.left + math.max(0, math.floor((width - result.loc.width) / 2)) end
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
  local block = display_equation(p)
  if not block then return end
  saved.left = block.left
  -- Decorations are buffer-scoped, like Snacks' image sizing. Fit the smallest
  -- visible text area when the note is shown in differently sized splits.
  for _, win in ipairs(p:wins()) do
    local info = vim.fn.getwininfo(win)[1]
    local width = math.max(1, info.width - info.textoff - block.left)
    saved.width = math.min(saved.width or width, width)
  end
  if saved.width then p.opts.max_width = math.min(saved.max_width or saved.width, saved.width) end
end

return M
