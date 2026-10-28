-- Shared terminal roles. Slots stay fixed across theme changes so
-- running applications can retain indices while Ghostty changes their colours.
local M = {}
M.slots = {
  muted = 245,
  border = 244,
  selection = 238,
  cursor = 237,
  search = 58,
  diff_add_bg = 22,
  diff_del_bg = 52,
  keyword = 141,
  string = 114,
  ['function'] = 75,
  type = 180,
  constant = 173,
  operator = 81,
  punctuation = 250,
  tag = 168,
}

local function blend(a, b, weight)
  local result = '#'
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    result = result .. string.format('%02x', math.floor(x + (y - x) * weight + 0.5))
  end
  return result
end

-- Read the active theme's semantic groups only at export time; render() stays
-- deterministic and usable by tests without loading any installed plugins.
function M.highlights()
  local result = {}
  local groups = {
    muted = { 'Comment', 'fg' },
    border = { 'WinSeparator', 'fg' },
    selection = { 'Visual', 'bg' },
    cursor = { 'CursorLine', 'bg' },
    search = { 'Search', 'bg' },
    diff_add_bg = { 'DiffAdd', 'bg' },
    diff_del_bg = { 'DiffDelete', 'bg' },
    keyword = { 'Keyword', 'fg' },
    string = { 'String', 'fg' },
    ['function'] = { 'Function', 'fg' },
    type = { 'Type', 'fg' },
    constant = { 'Constant', 'fg' },
    operator = { 'Operator', 'fg' },
    punctuation = { 'Delimiter', 'fg' },
    tag = { 'Tag', 'fg' },
  }
  for role, group in pairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = group[1], link = false, create = false })
    local field = group[2]
    if hl.reverse then field = field == 'fg' and 'bg' or 'fg' end
    local value = hl[field]
    if value then result[role] = string.format('#%06x', value) end
  end
  return result
end

function M.render(c, highlights)
  local colors = {
    muted = c.overlay1,
    border = c.surface1,
    selection = c.surface0,
    cursor = c.mantle,
    search = blend(c.base, c.yellow, 0.22),
    diff_add_bg = blend(c.base, c.green, 0.12),
    diff_del_bg = blend(c.base, c.red, 0.12),
    keyword = c.lavender,
    string = c.green,
    ['function'] = c.blue,
    type = c.yellow,
    constant = c.peach,
    operator = c.sky,
    punctuation = c.subtext0,
    tag = c.red,
  }
  for role, color in pairs(highlights or {}) do
    if colors[role] and type(color) == 'string' and color:match '^#%x%x%x%x%x%x$' then colors[role] = color end
  end
  -- A search background sits behind syntax text, not Neovim's paired Search
  -- foreground. Blend it towards the normal background to keep that text legible.
  if highlights and highlights.search then colors.search = blend(c.base, colors.search, 0.3) end
  local lines = {}
  for _, role in ipairs(vim.tbl_keys(M.slots)) do
    lines[#lines + 1] = 'palette = ' .. M.slots[role] .. '=' .. colors[role]
  end
  table.sort(lines)
  return lines
end

return M
