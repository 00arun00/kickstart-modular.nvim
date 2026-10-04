local M = {}
local colors = require 'custom.project_home.colors'
local get, blend = colors.get, colors.blend
function M.apply()
  local normal, comment = get 'Normal', get 'Comment'
  local fg, bg = normal.fg, normal.bg
  local accent = get('Title').fg or get('Function').fg or fg
  local green = get('DiagnosticOk').fg or get('String').fg or fg
  local amber = get('DiagnosticWarn').fg or fg
  local red = get('DiagnosticError').fg or fg
  local muted = comment.fg or fg
  local groups = {
    Text = { fg = fg },
    Muted = { fg = muted },
    Title = { fg = blend(fg, accent, 0.20), bold = true },
    Accent = { fg = accent, bold = true },
    Rule = { fg = blend(bg, muted, 0.35) },
    Key = { fg = accent, bg = blend(bg, accent, 0.14), bold = true },
    Tag = { fg = muted },
    Good = { fg = green },
    Warn = { fg = amber },
    Bad = { fg = red },
    Heat0 = { fg = blend(bg, muted, 0.22) },
  }
  for index, amount in ipairs { 0.30, 0.50, 0.75, 1 } do
    groups['Heat' .. index] = { fg = blend(bg, green, amount) }
  end
  for name, value in pairs(groups) do
    vim.api.nvim_set_hl(0, 'ProjectHomeVolt' .. name, value)
  end
end
return M
