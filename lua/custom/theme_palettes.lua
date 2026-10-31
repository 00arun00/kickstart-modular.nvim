-- Adapt each family's own palette to the shared roles consumed by custom UI,
-- plots, Markdown, and terminal exports. Read afresh after every ColorScheme.
local M = {}

function M.vesper()
  local p = require 'vesper.colors'
  return {
    base = p.bg,
    mantle = p.bgDark,
    text = p.fg,
    surface0 = p.bgOption,
    surface1 = p.border,
    overlay1 = p.comment,
    subtext0 = p.fgInactive,
    lavender = p.purple,
    red = p.error,
    peach = p.orange,
    yellow = p.yellowDark,
    blue = p.symbol,
    sky = p.info,
    teal = p.greenLight,
    green = p.green,
  }
end

-- Kanagawa Paper and Kansō retain Kanagawa's semantic palette structure.
local function kanagawa(p)
  local ui, syn, diag = p.ui, p.syn, p.diag
  return {
    base = ui.bg,
    mantle = ui.bg_dim,
    text = ui.fg,
    surface0 = ui.bg_visual,
    surface1 = ui.bg_p2,
    overlay1 = syn.comment,
    subtext0 = ui.fg_dim,
    lavender = syn.statement,
    red = diag.error,
    peach = syn.constant,
    yellow = diag.warning,
    blue = syn.fun,
    sky = diag.info,
    teal = syn.type,
    green = syn.string,
  }
end

function M.kanso(name) return kanagawa(require('kanso.colors').setup({ theme = name:match 'kanso%-(.+)' }).theme) end

M['kanagawa-paper'] = function(name) return kanagawa(require('kanagawa-paper.colors').setup({ _theme = name:match 'kanagawa%-paper%-(.+)' }).theme) end

function M.vague()
  local p = require('vague').get_palette()
  return {
    base = p.bg,
    mantle = p.inactiveBg,
    text = p.fg,
    surface0 = p.visual,
    surface1 = p.line,
    overlay1 = p.comment,
    subtext0 = p.property,
    lavender = p.constant,
    red = p.error,
    peach = p.number,
    yellow = p.warning,
    blue = p.keyword,
    sky = p.type,
    teal = p.builtin,
    green = p.plus,
  }
end

function M.flexoki()
  local p = require('flexoki.palette').palette()
  return {
    base = p.bg,
    mantle = p['bg-2'],
    text = p.tx,
    surface0 = p['ui-2'],
    surface1 = p['ui-3'],
    overlay1 = p['tx-2'],
    subtext0 = p['tx-2'],
    lavender = p.pu,
    red = p.re,
    peach = p['or'],
    yellow = p.ye,
    blue = p.bl,
    sky = p.cy,
    teal = p.cy,
    green = p.gr,
  }
end

function M.melange()
  local p = require('melange/palettes/' .. vim.o.background)
  return {
    base = p.a.bg,
    mantle = p.a.float,
    text = p.a.fg,
    surface0 = p.a.sel,
    surface1 = p.a.ui,
    overlay1 = p.a.com,
    subtext0 = p.a.com,
    lavender = p.b.magenta,
    red = p.b.red,
    peach = p.c.yellow,
    yellow = p.b.yellow,
    blue = p.b.blue,
    sky = p.b.cyan,
    teal = p.c.cyan,
    green = p.b.green,
  }
end

function M.oxocarbon()
  local p = require('oxocarbon').oxocarbon
  return {
    base = p.base00,
    mantle = p.base01,
    text = p.base04,
    surface0 = p.base02,
    surface1 = p.base03,
    overlay1 = p.base03,
    subtext0 = p.base04,
    lavender = p.base14,
    red = p.base10,
    peach = p.base12,
    yellow = p.base14,
    blue = p.base11,
    sky = p.base15,
    teal = p.base07,
    green = p.base13,
  }
end

function M.evergarden()
  local p = require('evergarden').colors()
  return {
    base = p.base,
    mantle = p.mantle,
    text = p.text,
    surface0 = p.surface0,
    surface1 = p.surface1,
    overlay1 = p.overlay1,
    subtext0 = p.subtext0,
    lavender = p.purple,
    red = p.red,
    peach = p.orange,
    yellow = p.yellow,
    blue = p.blue,
    sky = p.skye,
    teal = p.aqua,
    green = p.green,
  }
end

function M.mellow()
  local p = require('mellow.colors')[require('mellow.config').config.variant]
  return {
    base = p.bg,
    mantle = p.bg_dark,
    text = p.fg,
    surface0 = p.gray02,
    surface1 = p.gray03,
    overlay1 = p.gray05,
    subtext0 = p.gray06,
    lavender = p.magenta,
    red = p.red,
    peach = p.yellow,
    yellow = p.bright_yellow,
    blue = p.blue,
    sky = p.bright_blue,
    teal = p.cyan,
    green = p.green,
  }
end

function M.oldworld()
  local p = require 'oldworld.palette'
  return {
    base = p.bg,
    mantle = p.bg_dark,
    text = p.fg,
    surface0 = p.gray4,
    surface1 = p.gray3,
    overlay1 = p.subtext4,
    subtext0 = p.subtext2,
    lavender = p.purple,
    red = p.red,
    peach = p.orange,
    yellow = p.yellow,
    blue = p.blue,
    sky = p.cyan,
    teal = p.cyan,
    green = p.green,
  }
end

function M.mellifluous()
  local p = require('mellifluous.colors').get_colors()
  return {
    base = p.bg.hex,
    mantle = p.dark_bg.hex,
    text = p.fg.hex,
    surface0 = p.bg4.hex,
    surface1 = p.bg3.hex,
    overlay1 = p.comments.hex,
    subtext0 = p.fg2.hex,
    lavender = p.purple.hex,
    red = p.red.hex,
    peach = p.orange.hex,
    yellow = p.yellow.hex,
    blue = p.blue.hex,
    sky = p.functions.hex,
    teal = p.types.hex,
    green = p.green.hex,
  }
end

function M.poimandres()
  local p = require 'poimandres.palette'
  return {
    base = p.background2,
    mantle = p.background3,
    text = p.text,
    surface0 = p.background1,
    surface1 = p.blueGray3,
    overlay1 = p.blueGray3,
    subtext0 = p.blueGray1,
    lavender = p.pink2,
    red = p.pink3,
    peach = p.pink1,
    yellow = p.yellow,
    blue = p.blue2,
    sky = p.blue1,
    teal = p.teal1,
    green = p.teal2,
  }
end

function M.nightfox(name)
  local p = require('nightfox.palette').load(name)
  return {
    base = p.bg1,
    mantle = p.bg0,
    text = p.fg1,
    surface0 = p.sel0,
    surface1 = p.bg4,
    overlay1 = p.comment,
    subtext0 = p.fg2,
    lavender = p.magenta.base,
    red = p.red.base,
    peach = p.orange.base,
    yellow = p.yellow.base,
    blue = p.blue.base,
    sky = p.cyan.bright,
    teal = p.cyan.base,
    green = p.green.base,
  }
end

function M.flow()
  local p = require('flow.colors').colors
  return {
    base = p.bg,
    mantle = p.bg_float,
    text = p.fg,
    surface0 = p.bg_visual,
    surface1 = p.grey[4],
    overlay1 = p.comment,
    subtext0 = p.grey[8],
    lavender = p.purple,
    red = p.error,
    peach = p.orange,
    yellow = p.warning,
    blue = p.blue,
    sky = p.sky_blue,
    teal = p.cyan,
    green = p.green,
  }
end

return M
