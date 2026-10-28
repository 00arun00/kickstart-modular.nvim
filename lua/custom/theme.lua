local M = {}

-- Each entry owns its background so light/dark variants restore consistently.
local choices = {
  { 'catppuccin-latte', 'Catppuccin Latte', 'light', 'catppuccin' },
  { 'catppuccin-frappe', 'Catppuccin Frappé', 'dark', 'catppuccin' },
  { 'catppuccin-macchiato', 'Catppuccin Macchiato', 'dark', 'catppuccin' },
  { 'catppuccin-mocha', 'Catppuccin Mocha', 'dark', 'catppuccin' },
  { 'rose-pine-main', 'Rosé Pine Default', 'dark', 'rose-pine' },
  { 'rose-pine-moon', 'Rosé Pine Moon', 'dark', 'rose-pine' },
  { 'rose-pine-dawn', 'Rosé Pine Dawn', 'light', 'rose-pine' },
  { 'onedark', 'One Dark', 'dark', 'one' },
  { 'onelight', 'One Light', 'light', 'one' },
  { 'onedark_vivid', 'One Dark Vivid', 'dark', 'one' },
  { 'onedark_dark', 'One Dark Dark', 'dark', 'one' },
  { 'vaporwave', 'One Vaporwave', 'dark', 'one' },
  { 'ayu-dark', 'Ayu Dark', 'dark', 'ayu' },
  { 'ayu-mirage', 'Ayu Mirage', 'dark', 'ayu' },
  { 'ayu-light', 'Ayu Light', 'light', 'ayu' },
  { 'tokyonight-night', 'Tokyo Night Night', 'dark', 'tokyonight' },
  { 'tokyonight-storm', 'Tokyo Night Storm', 'dark', 'tokyonight' },
  { 'tokyonight-moon', 'Tokyo Night Moon', 'dark', 'tokyonight' },
  { 'tokyonight-day', 'Tokyo Night Day', 'light', 'tokyonight' },
}
local themes, labels, registry = {}, {}, {}
for _, choice in ipairs(choices) do
  local name, label, background, family = unpack(choice)
  themes[#themes + 1] = name
  labels[name] = label .. ' (' .. background .. ')'
  registry[name] = { background = background, family = family }
end

local function state_path() return vim.fn.stdpath 'state' .. '/theme-choice' end

local function current_theme()
  -- These plugins report a family name rather than the selected variant.
  if vim.g.colors_name == 'ayu' then
    if vim.o.background == 'light' then return 'ayu-light' end
    return require('ayu.config').mirage and 'ayu-mirage' or 'ayu-dark'
  end
  if vim.g.colors_name == 'rose-pine' then return 'rose-pine-' .. require('rose-pine.config').options.variant end
  return vim.g.colors_name
end

local function blend(a, b, weight)
  local result = '#'
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    result = result .. string.format('%02x', math.floor(x + (y - x) * weight + 0.5))
  end
  return result
end

local palette_cache
local function build_palette()
  local name = current_theme()
  local family = registry[name] and registry[name].family
  local c
  if family == 'catppuccin' then
    c = vim.deepcopy(require('catppuccin.palettes').get_palette(name:match 'catppuccin%-(.+)'))
  elseif family == 'rose-pine' then
    local p = require 'rose-pine.palette'
    c = {
      base = p.base,
      mantle = p.surface,
      text = p.text,
      surface0 = p.highlight_med,
      surface1 = p.highlight_high,
      overlay1 = p.subtle,
      subtext0 = p.subtle,
      lavender = p.iris,
      red = p.love,
      peach = p.gold,
      yellow = p.gold,
      blue = p.foam,
      sky = p.foam,
      teal = p.pine,
      green = p.leaf,
    }
  elseif family == 'one' then
    local p = require('onedarkpro.helpers').get_colors(name)
    c = {
      base = p.bg,
      mantle = p.float_bg,
      text = p.fg,
      surface0 = p.selection,
      surface1 = p.indentline,
      overlay1 = p.comment,
      subtext0 = p.fg,
      lavender = p.purple,
      red = p.red,
      peach = p.orange,
      yellow = p.yellow,
      blue = p.blue,
      sky = p.cyan,
      teal = p.cyan,
      green = p.green,
    }
  elseif family == 'ayu' then
    local p = require 'ayu.colors'
    c = {
      base = p.bg,
      mantle = p.panel_bg,
      text = p.fg,
      surface0 = p.selection_bg,
      surface1 = p.guide_active,
      overlay1 = p.ui,
      subtext0 = p.fg,
      lavender = p.constant,
      red = p.error,
      peach = p.keyword,
      yellow = p.accent,
      blue = p.entity,
      sky = p.tag,
      teal = p.regexp,
      green = p.string,
    }
  elseif family == 'tokyonight' then
    local p = require('tokyonight.colors').setup { style = name:match 'tokyonight%-(.+)' }
    c = {
      base = p.bg,
      mantle = p.bg_dark,
      text = p.fg,
      surface0 = p.bg_visual,
      surface1 = p.fg_gutter,
      overlay1 = p.comment,
      subtext0 = p.fg_dark,
      lavender = p.magenta,
      red = p.red,
      peach = p.orange,
      yellow = p.yellow,
      blue = p.blue,
      sky = p.cyan,
      teal = p.teal,
      green = p.green,
    }
  else
    c = vim.deepcopy(require('catppuccin.palettes').get_palette 'mocha')
  end
  -- Darken light-mode custom foregrounds while retaining the theme's own hue.
  if vim.o.background == 'light' then
    for _, key in ipairs { 'overlay1', 'lavender', 'red', 'peach', 'yellow', 'blue', 'sky', 'teal', 'green' } do
      c[key] = blend(c[key], c.text, 0.3)
    end
  end
  c.task_active, c.task_quarter = c.teal, blend(c.teal, c.green, 0.25)
  c.task_half, c.task_three_quarters, c.task_done = blend(c.teal, c.green, 0.5), blend(c.teal, c.green, 0.75), c.green
  -- Preserve the original Mocha task colours.
  if name == 'catppuccin-mocha' then
    c.task_active, c.task_quarter, c.task_half = '#64c9bc', '#74bdb9', '#65d5b5'
    c.task_three_quarters, c.task_done = '#83df9b', '#45e779'
  end
  return c
end

function M.palette()
  if not palette_cache then palette_cache = build_palette() end
  return palette_cache
end

function M.apply_highlights()
  if not vim.tbl_contains(themes, current_theme()) then return end
  palette_cache = build_palette()
  local colors = palette_cache
  local highlights = {
    CustomBlameAccent = { fg = colors.lavender },
    Folded = { bg = colors.mantle },
    FoldColumn = { fg = colors.overlay1, bg = colors.base },
    CursorLineFold = { fg = colors.lavender, bg = colors.base, bold = true },
    FoldSummary = { fg = colors.subtext0, bg = colors.mantle },
    DiagnosticError = { fg = colors.red },
    DiagnosticWarn = { fg = colors.peach },
    DiagnosticSignError = { fg = colors.red },
    DiagnosticSignWarn = { fg = colors.peach },
    -- Task progress stays in one teal -> mint -> green color family.
    MarkdownTaskPending = { fg = colors.overlay1 },
    MarkdownTaskActive = { fg = colors.task_active },
    MarkdownTaskQuarter = { fg = colors.task_quarter },
    MarkdownTaskHalf = { fg = colors.task_half },
    MarkdownTaskThreeQuarters = { fg = colors.task_three_quarters },
    MarkdownTaskDone = { fg = colors.task_done },
    MarkdownTaskDeferred = { fg = colors.lavender },
    MarkdownTaskBlocked = { fg = colors.red },
    MarkdownTaskQuestion = { fg = colors.sky },
    NeoTreeNormal = { fg = colors.text, bg = colors.mantle },
    NeoTreeNormalNC = { fg = colors.text, bg = colors.mantle },
    NeoTreeRootName = { fg = colors.lavender, bold = true },
    NeoTreeCursorLine = { bg = colors.surface0 },
    NeoTreeIndentMarker = { fg = colors.surface1 },
    NeoTreeExpander = { fg = colors.overlay1 },
    NeoTreeTabActive = { fg = colors.lavender, bg = colors.surface0, bold = true },
    NeoTreeTabInactive = { fg = colors.subtext0, bg = colors.mantle },
    NeoTreeTabSeparatorActive = { fg = colors.mantle, bg = colors.mantle },
    NeoTreeTabSeparatorInactive = { fg = colors.mantle, bg = colors.mantle },
  }
  for name, value in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

local function apply(name)
  if current_theme() == name and vim.o.background == registry[name].background then return end
  vim.o.background = registry[name].background
  vim.cmd.colorscheme(name)
end

-- Previewing does not write state; only a confirmed choice is remembered.
function M.select(name)
  if not registry[name] then return false end
  apply(name)
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fn.stdpath 'state', 'p')
    local path = state_path()
    local temporary = path .. '.' .. vim.fn.getpid() .. '.tmp'
    local written, failure = pcall(function()
      assert(vim.fn.writefile({ name }, temporary) == 0, 'Could not write theme choice')
      local renamed, rename_error = vim.uv.fs_rename(temporary, path)
      assert(renamed, rename_error)
    end)
    if not written then
      vim.uv.fs_unlink(temporary)
      error(failure)
    end
  end)
  if not ok then vim.notify('Theme applied, but could not save selection: ' .. tostring(err), vim.log.levels.WARN) end
  require('custom.theme_sync').publish()
  return true
end

function M.restore()
  local ok, saved = pcall(vim.fn.readfile, state_path())
  local name = ok and saved[1] or nil
  if not vim.tbl_contains(themes, name) then name = 'catppuccin-mocha' end
  vim.o.background = registry[name].background
  local applied = pcall(vim.cmd.colorscheme, name)
  if not applied then
    vim.o.background = 'dark'
    vim.cmd.colorscheme 'catppuccin-mocha'
  end
end

local picking = false
local function pull_selection()
  if picking then return end
  local ok, saved = pcall(vim.fn.readfile, state_path())
  local name = ok and saved[1] or nil
  if registry[name] and (current_theme() ~= name or vim.o.background ~= registry[name].background) then
    apply(name)
    -- Update tmux's pane contents even when this instance is not focused.
    vim.cmd 'redraw!'
  end
end

local selection_watcher
local function stop_selection_watcher()
  if not selection_watcher then return end
  selection_watcher:stop()
  selection_watcher:close()
  selection_watcher = nil
end

local function watch_selection()
  stop_selection_watcher()
  -- Watch the directory: confirmed choices replace the file atomically.
  local directory = vim.fn.stdpath 'state'
  local created = pcall(vim.fn.mkdir, directory, 'p')
  if not created then return end -- FocusGained remains the fallback.
  local watcher = vim.uv.new_fs_event()
  if not watcher then return end
  selection_watcher = watcher
  local queued = false
  local started = watcher:start(directory, {}, function(err, filename)
    if selection_watcher ~= watcher then return end
    if not err and filename and filename ~= 'theme-choice' then return end
    if queued then return end
    queued = true
    vim.schedule(function()
      queued = false
      if selection_watcher ~= watcher then return end
      if err then
        stop_selection_watcher()
        return
      end
      pull_selection()
    end)
  end)
  if not started then stop_selection_watcher() end
end

function M.pick()
  pull_selection()
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local original, original_background = current_theme(), vim.o.background
  local confirmed = false
  picking = true
  local selected = 1
  for i, name in ipairs(themes) do
    if name == current_theme() then selected = i end
  end
  local picker = require('telescope.pickers').new(require('telescope.themes').get_dropdown { previewer = false }, {
    prompt_title = 'Theme',
    default_selection_index = selected,
    finder = require('telescope.finders').new_table {
      results = themes,
      entry_maker = function(name) return { value = name, display = labels[name], ordinal = labels[name] .. ' ' .. name } end,
    },
    sorter = require('telescope.config').values.generic_sorter {},
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        confirmed = true
        actions.close(prompt_bufnr)
        M.select(entry.value)
      end)
      return true
    end,
  })

  -- Use the same per-picker hooks as Telescope's built-in colorscheme preview.
  -- set_selection covers navigation, mouse selection, and fuzzy-filter updates.
  local set_selection = picker.set_selection
  picker.set_selection = function(self, row)
    set_selection(self, row)
    local entry = self:get_selection()
    if entry then apply(entry.value) end
  end
  local close_windows = picker.close_windows
  picker.close_windows = function(status)
    close_windows(status)
    picking = false
    if not confirmed then
      vim.o.background = original_background
      vim.cmd.colorscheme(original)
      pull_selection()
    end
  end
  picker:find()
end

function M.setup()
  require('custom.theme_sync_setup').commands()
  local group = vim.api.nvim_create_augroup('CustomTheme', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply_highlights })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = pull_selection,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = stop_selection_watcher })
  watch_selection()
  vim.api.nvim_create_user_command('ThemePicker', M.pick, { desc = 'Choose a theme with live preview' })
  vim.keymap.set('n', '<leader>Tt', '<cmd>ThemePicker<CR>', { desc = '[T]heme picker: choose [t]heme' })
end

return M
