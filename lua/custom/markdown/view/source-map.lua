local function bounds(pos)
  local first, last
  -- Tables and nested blocks may report several source ranges separated by
  -- semicolons. Normalize to their outer range instead of losing the anchor.
  for a, b, c, d in pos:gmatch '(%d+):(%d+)%-(%d+):(%d+)' do
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if not first or a < first[1] or (a == first[1] and b < first[2]) then first = { a, b } end
    if not last or c > last[1] or (c == last[1] and d > last[2]) then last = { c, d } end
  end
  return first, last
end

local function marker(pos, finish)
  local first, last = bounds(pos)
  if not first then return pandoc.RawBlock('typst', '') end
  if finish then first = last end
  local normalized = ('@%d:%d-%d:%d'):format(first[1], first[2], last[1], last[2])
  return pandoc.RawBlock('typst', '#metadata(' .. string.format('%q', normalized) .. ') <md-anchor>')
end

function Div(el)
  local pos = el.attributes['data-pos']
  if not pos then return el end
  table.insert(el.content, 1, marker(pos))
  -- CommonMark source positions wrap each paragraph in a Div. These wrappers
  -- are provenance, not layout: Typst's default block shrinks to its contents,
  -- making display equations center within their own width instead of the
  -- text column. Keep real attributed Divs, but flatten parser-only wrappers.
  if el.attributes.wrapper == '1' and el.identifier == '' and #el.classes == 0 then
    for name in pairs(el.attributes) do
      if name ~= 'data-pos' and name ~= 'wrapper' then return el end
    end
    return el.content
  end
  return el
end

function Header(el)
  local pos = el.attributes['data-pos']
  if pos then return { marker(pos), el } end
end

function CodeBlock(el)
  local pos = el.attributes['data-pos']
  if pos then return { marker(pos), el } end
end

function Table(el)
  -- Pandoc places tables in a centered figure. Unspecified Markdown columns
  -- should still read from the left edge rather than inherit that centering.
  for _, column in ipairs(el.colspecs) do
    if column[1] == 'AlignDefault' then column[1] = 'AlignLeft' end
  end
  local pos = el.attributes['data-pos']
  if pos then return { marker(pos), el, marker(pos, true) } end
end
