-- Resolve global highlight links without inheriting window-local remappings.
local M = {}
function M.get(name)
  for _ = 1, 32 do
    local h = vim.api.nvim_get_hl(0, { name = name, link = true })
    if not h.link then return h end
    name = h.link
  end
  return {}
end
function M.blend(a, b, ratio)
  if not a or not b then return a or b end
  local color = 0
  for _, shift in ipairs { 16, 8, 0 } do
    local x, y = math.floor(a / 2 ^ shift) % 256, math.floor(b / 2 ^ shift) % 256
    color = color + math.floor(x + (y - x) * ratio + 0.5) * 2 ^ shift
  end
  return color
end
return M
