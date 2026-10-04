local M = {}
local function clean(s) return tostring(s or ''):gsub('[\r\n\t]', ' ') end
local ns = vim.api.nvim_create_namespace 'project_home'
local selection_ns = vim.api.nvim_create_namespace 'project_home_selection'
local colors = require 'custom.project_home.colors'
function M.highlights()
  for name, target in pairs {
    Normal = 'Normal',
    Title = 'Title',
    Muted = 'Comment',
    Accent = 'Special',
    Selected = 'Visual',
    Warning = 'DiagnosticWarn',
    Success = 'DiagnosticOk',
    Border = 'Comment',
  } do
    vim.api.nvim_set_hl(0, 'ProjectHome' .. name, { default = true, link = target })
  end
  local normal = colors.get 'Normal'
  local accent = colors.get('Title').fg or colors.get('Function').fg or normal.fg
  vim.api.nvim_set_hl(0, 'ProjectHomeWorkspaceAccent', { fg = accent })
  vim.api.nvim_set_hl(0, 'ProjectHomeCanvas', { fg = normal.fg, bg = normal.bg })
  vim.api.nvim_set_hl(0, 'ProjectHomeBackdrop', { fg = normal.fg, bg = normal.bg })
  vim.api.nvim_set_hl(0, 'ProjectHomeWorkspaceSelected', { bg = colors.blend(normal.bg, accent, 0.14) })
end
function M.valid(ctx) return ctx and vim.api.nvim_buf_is_valid(ctx.buf) and vim.api.nvim_win_is_valid(ctx.win) and vim.api.nvim_win_get_buf(ctx.win) == ctx.buf end
-- Item coordinates are bytes on their first row. Rectangles on subsequent rows
-- need matching display columns, because filename and metadata UTF-8 differ.
local function display_to_byte(text, target)
  local byte = 0
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    local nextbyte = byte + #char
    if vim.fn.strdisplaywidth(text:sub(1, nextbyte)) > target then return byte end
    byte = nextbyte
  end
  return byte
end
local function item_bounds(ctx, item, row)
  local start = item.col or 0
  local finish = item.end_col or start + (item.width or #(item.label or ''))
  local first = vim.api.nvim_buf_get_lines(ctx.buf, item.line - 1, item.line, false)[1] or ''
  local text = row == item.line and first or vim.api.nvim_buf_get_lines(ctx.buf, row - 1, row, false)[1] or ''
  if row == item.line then return math.min(start, #text), math.min(finish, #text) end
  local left = vim.fn.strdisplaywidth(first:sub(1, start))
  local right = vim.fn.strdisplaywidth(first:sub(1, finish))
  return display_to_byte(text, left), display_to_byte(text, right)
end
local function item_at_cursor(ctx)
  local position = vim.api.nvim_win_get_cursor(ctx.win)
  local chosen, distance
  for _, item in ipairs(ctx.items or {}) do
    if position[1] >= item.line and position[1] <= (item.end_line or item.line) then
      local col, finish = item_bounds(ctx, item, position[1])
      local inside = position[2] >= col and position[2] < finish
      local delta = inside and 0 or math.abs(col - position[2]) + 1
      if not distance or delta < distance then
        chosen, distance = item, delta
      end
    end
  end
  return chosen
end
function M.update_selection(ctx)
  if not M.valid(ctx) then return end
  require('custom.project_home.keyboard').refresh(ctx)
  vim.api.nvim_buf_clear_namespace(ctx.buf, selection_ns, 0, -1)
  if not ctx.bounded_selection then return end
  local item = item_at_cursor(ctx)
  if not item then return end
  local total = vim.api.nvim_buf_line_count(ctx.buf)
  for row = item.line, math.min(item.end_line or item.line, total) do
    local left, right = item_bounds(ctx, item, row)
    if right > left then
      vim.api.nvim_buf_set_extmark(
        ctx.buf,
        selection_ns,
        row - 1,
        left,
        { end_row = row - 1, end_col = right, hl_group = 'ProjectHomeWorkspaceSelected', hl_mode = 'combine', priority = 200 }
      )
    end
  end
end
function M.draw(ctx, page)
  if not M.valid(ctx) then return end
  if ctx.clear_presentation then
    ctx.clear_presentation()
    ctx.clear_presentation = nil
  end
  local previous_item = item_at_cursor(ctx)
  local navigation = ctx.force_focus or ctx.draw_generation ~= ctx.generation
  if ctx.keyboard_active and page.presentation == 'workspace' and ctx.keyboard_section and previous_item and previous_item.section == ctx.keyboard_section then
    navigation = false
  end
  ctx.force_focus = nil
  ctx.draw_generation = ctx.generation
  local name = 'project-home://' .. ctx.layout .. '/' .. ctx.buf
  if vim.api.nvim_buf_get_name(ctx.buf) ~= name then vim.api.nvim_buf_set_name(ctx.buf, name) end
  local label = clean((ctx.model and (ctx.model.name or ctx.model.title)) or 'Project'):gsub('%%', '%%%%')
  vim.wo[ctx.win].statusline = '  Project home · ' .. label .. ' / ' .. ctx.layout .. ' %=  j/k move · Enter open  '
  local lines = page.lines or { 'Project home' }
  if #lines == 0 then lines = { 'Nothing to show.' } end
  ctx.textview = page.textview
  ctx.bounded_selection = page.presentation == 'workspace' or page.cursorline == false
  vim.wo[ctx.win].cursorline = not ctx.bounded_selection
  local original_hl = ctx.original_options.winhighlight or ''
  if page.presentation == 'workspace' then
    local mappings = {}
    for entry in original_hl:gmatch '[^,]+' do
      if not entry:match '^Normal:' and not entry:match '^NormalNC:' then mappings[#mappings + 1] = entry end
    end
    mappings[#mappings + 1] = 'Normal:ProjectHomeBackdrop'
    mappings[#mappings + 1] = 'NormalNC:ProjectHomeBackdrop'
    vim.wo[ctx.win].winhighlight = table.concat(mappings, ',')
  else
    vim.wo[ctx.win].winhighlight = original_hl
  end
  ctx.items = page.items or {}
  table.sort(ctx.items, function(a, b) return a.line == b.line and (a.col or 0) < (b.col or 0) or a.line < b.line end)
  vim.bo[ctx.buf].modifiable = true
  vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
  vim.bo[ctx.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1)
  for _, h in ipairs(page.highlights or {}) do
    if h.line and h.line >= 1 and h.line <= #lines then
      pcall(vim.api.nvim_buf_set_extmark, ctx.buf, ns, h.line - 1, h.start_col or 0, {
        end_row = h.line - 1,
        end_col = h.end_col and h.end_col >= 0 and h.end_col or #lines[h.line],
        hl_group = h.group or 'Normal',
        priority = h.priority or 100,
      })
    end
  end
  local cursor = vim.api.nvim_win_get_cursor(ctx.win)
  if cursor[1] > #lines then vim.api.nvim_win_set_cursor(ctx.win, { #lines, 0 }) end
  if not ctx.textview and #ctx.items > 0 then
    local focus
    if navigation then
      local hint = page.initial_focus
      if hint then
        for _, item in ipairs(ctx.items) do
          if
            (hint.line and item.line == hint.line and (item.col or 0) == (hint.col or 0))
            or (not hint.line and hint.action == item.action and vim.deep_equal(hint.value, item.value))
          then
            focus = item
            break
          end
        end
      end
      focus = focus or ctx.items[1]
    elseif previous_item then
      for _, item in ipairs(ctx.items) do
        if item.action == previous_item.action and item.section == previous_item.section and vim.deep_equal(item.value, previous_item.value) then
          focus = item
          break
        end
      end
      if not focus and ctx.keyboard_section then
        for _, item in ipairs(ctx.items) do
          if item.section == ctx.keyboard_section then
            focus = item
            break
          end
        end
      end
      focus = focus or ctx.items[1]
    end
    if focus then vim.api.nvim_win_set_cursor(ctx.win, { focus.line, focus.col or 0 }) end
  end
  if ctx.restore_focus then
    local saved = ctx.restore_focus
    ctx.restore_focus = nil
    local position = saved.position
    if saved.action then
      for _, item in ipairs(ctx.items) do
        if item.action == saved.action and item.section == saved.section and vim.deep_equal(item.value, saved.value) then
          position = { item.line, item.col or 0 }
          break
        end
      end
    end
    if position then
      local line = math.max(1, math.min(position[1], #lines))
      vim.api.nvim_win_set_cursor(ctx.win, { line, math.min(position[2], #lines[line]) })
    end
  end
  if ctx.keymaps then
    for key in pairs(ctx.keymaps) do
      pcall(vim.keymap.del, 'n', key, { buffer = ctx.buf })
    end
  end
  ctx.keymaps = {}
  for _, item in ipairs(ctx.items) do
    if item.key and not ctx.keymaps[item.key] then
      ctx.keymaps[item.key] = true
      vim.keymap.set('n', item.key, function() ctx.dispatch(item.action, item.value) end, { buffer = ctx.buf, silent = true, desc = item.label })
    end
  end
  if page.paint then ctx.clear_presentation = page.paint(ctx) end
  require('custom.project_home.keyboard').bind(ctx, page)
  M.update_selection(ctx)
end
function M.page(title, subtitle, entries, live_action)
  local p = {
    live_action = live_action,
    lines = { '', '  ' .. clean(title), '  ' .. clean(subtitle), '' },
    highlights = { { line = 2, start_col = 2, group = 'ProjectHomeTitle' }, { line = 3, start_col = 2, group = 'ProjectHomeMuted' } },
    items = {},
  }
  for _, e in ipairs(entries or {}) do
    p.lines[#p.lines + 1] = '  ' .. clean(e.label)
    local line = #p.lines
    if e.action then p.items[#p.items + 1] = { line = line, col = 2, label = e.label, action = e.action, value = e.value, key = e.key } end
    if e.group then p.highlights[#p.highlights + 1] = { line = line, start_col = 2, group = e.group } end
    if e.detail then
      p.lines[#p.lines + 1] = '    ' .. clean(e.detail)
      p.highlights[#p.highlights + 1] = { line = #p.lines, start_col = 4, group = e.detail_group or 'ProjectHomeMuted' }
    end
    p.lines[#p.lines + 1] = ''
  end
  p.lines[#p.lines + 1] = '  Enter open  ·  j/k move  ·  Backspace back  ·  H home  ·  q close'
  p.highlights[#p.highlights + 1] = { line = #p.lines, start_col = 2, group = 'ProjectHomeMuted' }
  return p
end
function M.restore_options(ctx)
  if vim.api.nvim_win_is_valid(ctx.win) then
    for k, v in pairs(ctx.original_options or {}) do
      pcall(function() vim.wo[ctx.win][k] = v end)
    end
  end
end
function M.capture_options(win)
  local options = {}
  for _, k in ipairs { 'number', 'relativenumber', 'signcolumn', 'foldcolumn', 'wrap', 'cursorline', 'list', 'spell', 'fillchars', 'statusline', 'winhighlight' } do
    options[k] = vim.wo[win][k]
  end
  return options
end
function M.attach(ctx)
  ctx.original_options = ctx.original_options or M.capture_options(ctx.win)
  vim.api.nvim_create_autocmd('BufWinLeave', { buffer = ctx.buf, once = true, callback = function() M.restore_options(ctx) end })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = ctx.buf,
    once = true,
    callback = function()
      if ctx.clear_presentation then
        ctx.clear_presentation()
        ctx.clear_presentation = nil
      end
    end,
  })
  vim.api.nvim_buf_set_name(ctx.buf, 'project-home://' .. ctx.layout .. '/' .. ctx.buf)
  vim.bo[ctx.buf].buftype = 'nofile'
  vim.bo[ctx.buf].bufhidden = 'wipe'
  vim.bo[ctx.buf].swapfile = false
  vim.bo[ctx.buf].filetype = 'projecthome'
  vim.bo[ctx.buf].modifiable = false
  for k, v in pairs { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', wrap = false, cursorline = true, list = false, spell = false } do
    vim.wo[ctx.win][k] = v
  end
  vim.api.nvim_win_call(ctx.win, function() vim.opt_local.fillchars:append { eob = ' ' } end)
  vim.api.nvim_create_autocmd('CursorMoved', { buffer = ctx.buf, callback = function() M.update_selection(ctx) end })
  local function move(delta)
    if not M.valid(ctx) then return end
    if require('custom.project_home.keyboard').move(ctx, delta) then return end
    if ctx.textview or #ctx.items == 0 then
      vim.cmd('normal! ' .. tostring(vim.v.count1) .. (delta > 0 and 'j' or 'k'))
      return
    end
    local pos = vim.api.nvim_win_get_cursor(ctx.win)
    local line, col = pos[1], pos[2]
    local target
    if delta > 0 then
      for _, i in ipairs(ctx.items) do
        if i.line > line or (i.line == line and (i.col or 0) > col) then
          target = i
          break
        end
      end
      target = target or ctx.items[1]
    else
      for j = #ctx.items, 1, -1 do
        if ctx.items[j].line < line or (ctx.items[j].line == line and (ctx.items[j].col or 0) < col) then
          target = ctx.items[j]
          break
        end
      end
      target = target or ctx.items[#ctx.items]
    end
    vim.api.nvim_win_set_cursor(ctx.win, { target.line, target.col or 0 })
    M.update_selection(ctx)
  end
  local map = function(k, f) vim.keymap.set('n', k, f, { buffer = ctx.buf, silent = true }) end
  map('j', function() move(1) end)
  map('k', function() move(-1) end)
  map('<Down>', function() move(1) end)
  map('<Up>', function() move(-1) end)
  local function activate()
    local chosen = item_at_cursor(ctx)
    if chosen then ctx.dispatch(chosen.action, chosen.value) end
  end
  map('<CR>', activate)
  map('<2-LeftMouse>', activate)
  map('<BS>', function() ctx.dispatch 'back' end)
  map('<Esc>', function()
    if ctx.keyboard_active and ctx.keyboard_section then
      ctx.keyboard_section = nil
      for _, item in ipairs(ctx.items) do
        if item.section == 'actions' then
          vim.api.nvim_win_set_cursor(ctx.win, { item.line, item.col or 0 })
          break
        end
      end
      M.update_selection(ctx)
    else
      ctx.dispatch 'back'
    end
  end)
  map('H', function() ctx.dispatch 'home' end)
  map('q', function() ctx.dispatch 'close' end)
end
return M
