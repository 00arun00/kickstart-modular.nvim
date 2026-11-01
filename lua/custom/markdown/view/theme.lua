-- Snapshot semantic colors from the editor that is actually on screen. This
-- deliberately does not consult the named-theme palette cache: an arbitrary
-- :colorscheme or picker preview can make that cache describe another theme.
local M = {}
local roles = { 'background', 'foreground', 'muted', 'heading', 'link', 'math', 'panel', 'header', 'border', 'code', 'figure_background' }
local syntax = { 'comment', 'keyword', 'string', 'function', 'type', 'constant', 'operator', 'punctuation', 'tag' }

local function color(name, field)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
  if hl.reverse then field = field == 'fg' and 'bg' or 'fg' end
  return hl[field] and string.format('#%06x', hl[field]) or nil
end

local function blend(a, b, weight)
  local result = '#'
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    result = result .. string.format('%02x', math.floor(x + (y - x) * weight + 0.5))
  end
  return result
end

local function contrast(a, b)
  local function luminance(color)
    local channels = {}
    for i = 2, 6, 2 do
      local value = tonumber(color:sub(i, i + 1), 16) / 255
      channels[#channels + 1] = value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    return channels[1] * 0.2126 + channels[2] * 0.7152 + channels[3] * 0.0722
  end
  local x, y = luminance(a), luminance(b)
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

local function surface(candidate, fg, bg)
  -- NormalFloat/CursorLine can be readable only with their own foreground.
  -- We inherit document ink, so avoid creating a worse cross-pairing. This
  -- preserves exact user colors and even their native low-contrast choices.
  return contrast(fg, candidate) < math.min(4.5, contrast(fg, bg)) and bg or candidate
end

function M.capture(win)
  -- Normal lookup follows the current window's winhighlight remapping, even in
  -- namespace zero. Read from source rather than our own old preview background
  -- or a picker window, which would feed presentation colors back into input.
  if win then
    return vim.api.nvim_win_call(win, function() return M.capture() end)
  end
  local light = vim.o.background == 'light'
  local bg = color('Normal', 'bg') or (light and '#ffffff' or '#1e1e1e')
  local fg = color('Normal', 'fg') or color('NormalFloat', 'fg') or (light and '#202020' or '#dddddd')
  local panel = color('NormalFloat', 'bg')
  if not panel or panel == bg then panel = blend(bg, fg, 0.05) end
  panel = surface(panel, fg, bg)
  local heading = color('Title', 'fg') or color('@markup.heading', 'fg') or fg
  local c = {
    background = bg,
    foreground = fg,
    muted = color('Comment', 'fg') or blend(bg, fg, 0.65),
    heading = heading,
    link = color('@markup.link', 'fg') or color('Underlined', 'fg') or color('Special', 'fg') or fg,
    math = color('SnacksImageMath', 'fg') or fg,
    panel = panel,
    header = surface(color('CursorLine', 'bg') or panel, heading, bg),
    border = color('WinSeparator', 'fg') or blend(bg, fg, 0.25),
    code = fg,
    -- Authored figures retain their own colors. A stable paper backing keeps
    -- transparent black labels readable without changing size across themes.
    figure_background = '#ffffff',
    syntax = {},
  }
  local highlights = require('custom.terminal_palette').highlights()
  for _, role in ipairs(syntax) do
    c.syntax[role] = highlights[role] or (role == 'comment' and c.muted or fg)
  end
  return c
end

function M.fingerprint(c)
  local values = {}
  for _, role in ipairs(roles) do
    values[#values + 1] = role .. '=' .. c[role]
  end
  for _, role in ipairs(syntax) do
    values[#values + 1] = role .. '=' .. c.syntax[role]
  end
  return vim.fn.sha256(table.concat(values, '\n'))
end

return M
