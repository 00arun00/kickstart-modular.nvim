-- Markdown $...$: one typographic scale and baseline, not one scale per crop.
local M = {}
local installed = false
local font_pt, above_em, below_em = 12, 0.95, 0.4

local function inline(buf, text, row, col)
  if vim.bo[buf].filetype ~= 'markdown' or text:sub(1, 1) ~= '$' or text:sub(1, 2) == '$$' or text:sub(-1) ~= '$' or text:find '\n' then return false end
  -- Table math already has its own layout/sizing policy.
  local parser = vim.treesitter.get_parser(buf, 'markdown')
  local node = parser:parse()[1]:root():named_descendant_for_range(row, col, row, col)
  while node do
    if node:type() == 'pipe_table' then return false end
    node = node:parent()
  end
  return true
end

function M.setup()
  if installed then return end
  installed = true
  local doc = Snacks.image.doc
  local latex = doc.transforms.latex
  doc.transforms.latex = function(img, ctx)
    local text = vim.trim(img.content or '')
    local r = img.range
    if img.ext ~= 'math.tex' or not r or not inline(ctx.buf, text, r[1] - 1, r[2]) then return latex(img, ctx) end
    local cell = Snacks.image.terminal.size()
    local aspect = cell.cell_width / cell.cell_height
    -- lrbox starts with \begin, so Snacks preserves our text-style math rather
    -- than wrapping it in display math. Its template still supplies packages,
    -- document headers and theme color. A strut keeps a common transparent
    -- height/depth; taller content grows naturally rather than being clipped.
    -- Quantize the WIDTH with transparent space, never by stretching glyphs.
    img.content = ([[\begin{lrbox}{0}\fontsize{%d}{%d}\selectfont
\kern.04em\(\textstyle %s\)\kern.04em\end{lrbox}
\fontsize{%d}{%d}\selectfont
\dimen0=%sem\dimen2=%.8f\dimen0
\count0=\wd0\count2=\dimen2
\advance\count0 by\count2\advance\count0 by-1
\divide\count0 by\count2\multiply\dimen2 by\count0
\dimen4=\dimen2\advance\dimen4 by-\wd0
\hbox{\vrule width0pt height%sem depth%sem\box0\kern\dimen4}]]):format(
      font_pt,
      font_pt + 2,
      text:sub(2, -2),
      font_pt,
      font_pt + 2,
      above_em + below_em,
      aspect,
      above_em,
      below_em
    )
    latex(img, ctx)
    -- Separate conversion/cache identity: ordinary/display math keeps -trim.
    img.ext = 'inline-math.tex'
  end
end

-- Called by the existing document placement hook, after image conversion.
function M.prepare(p)
  if p._markdown_inline then return end
  p._markdown_inline = true
  local state = p.state
  p.state = function(self)
    local result = state(self)
    local src, info, r = self.img.src or '', self.img.info, self.opts.range
    if not (self.opts.inline and self.opts.type == 'math' and src:match '%.inline%-math%.tex$' and info and r and r[1] == r[3]) then return result end
    local text = table.concat(vim.api.nvim_buf_get_text(self.buf, r[1] - 1, r[2], r[3] - 1, r[4], {}))
    if not inline(self.buf, text, r[1] - 1, r[2]) then return result end
    -- PDF points -> raster pixels. Allow a pixel of rasterization rounding at
    -- either edge. Oversize structures retain Snacks' existing fallback.
    local height = font_pt * (above_em + below_em) / 72.27 * info.dpi.height
    if info.size.height > height + 2 then return result end
    local cell = Snacks.image.terminal.size()
    local width = math.max(1, math.floor(info.size.width / info.size.height * cell.cell_height / cell.cell_width + 0.5))
    local limit = self.opts.max_width or math.huge
    for _, win in ipairs(self:wins()) do
      local view = vim.fn.getwininfo(win)[1]
      limit = math.min(limit, view.width - view.textoff)
    end
    if width > limit then return result end
    result.loc.width, result.loc.height = width, 1
    return result
  end
end

return M
