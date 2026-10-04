local M = {}
local ns = vim.api.nvim_create_namespace 'project_home_keyboard'
local order = { 'actions', 'recent', 'git', 'prs', 'activity' }
local names = { actions = 'Actions', recent = 'Recent files', git = 'Git workspace', prs = 'Pull requests', activity = 'Activity' }
local jumps = { r = 'recent', g = 'git', p = 'prs' }
local utility = { recents = true, prs = true, keyboard_help = true }
local function entries(ctx, section)
  local result = {}
  if not section then return result end
  for _, item in ipairs(ctx.items or {}) do
    if item.section == section then result[#result + 1] = item end
  end
  table.sort(result, function(a, b)
    if not not utility[a.action] ~= not not utility[b.action] then return not utility[a.action] end
    return a.line == b.line and a.col < b.col or a.line < b.line
  end)
  if result[1] and not utility[result[1].action] then result = vim.tbl_filter(function(item) return not utility[item.action] end, result) end
  return result
end
local function focus(ctx, item)
  if item then vim.api.nvim_win_set_cursor(ctx.win, { item.line, item.col or 0 }) end
  require('custom.project_home.ui').update_selection(ctx)
end
function M.section(ctx, section)
  ctx.keyboard_section = section
  focus(ctx, entries(ctx, section)[1])
end
function M.move(ctx, delta)
  if not ctx.keyboard_active then return false end
  local section = ctx.keyboard_section or 'actions'
  ctx.keyboard_section = section
  local items = entries(ctx, section)
  if #items == 0 then return true end
  local cursor, index = vim.api.nvim_win_get_cursor(ctx.win), 0
  for i, item in ipairs(items) do
    if cursor[1] >= item.line and cursor[1] <= (item.end_line or item.line) and cursor[2] >= item.col then index = i end
  end
  focus(ctx, items[(index - 1 + delta) % #items + 1])
  return true
end
function M.refresh(ctx)
  vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1)
  if not ctx.keyboard_active then return end
  local section = ctx.keyboard_section
  local items = entries(ctx, section)
  local heading = (ctx.keyboard_sections or {})[section]
  if heading then
    vim.api.nvim_buf_set_extmark(ctx.buf, ns, heading.line - 1, heading.col, {
      end_col = heading.col + #heading.label,
      hl_group = 'ProjectHomeWorkspaceAccent',
      priority = 210,
    })
  end
  for i, item in ipairs(items) do
    if i > 9 then break end
    -- Number badges occupy the existing gutter, without moving hit targets.
    vim.api.nvim_buf_set_extmark(ctx.buf, ns, item.line - 1, math.max(0, item.col - 2), {
      virt_text = { { tostring(i) .. ' ', 'ProjectHomeWorkspaceAccent' } },
      virt_text_pos = 'overlay',
      priority = 220,
    })
  end
  local footer = ctx.keyboard_footer
  if footer then
    local hint = section and ('1–' .. math.min(#items, 9) .. ' open · j/k select · Tab section · Enter open · Esc back · ? help')
      or 'r recent · p PRs · g Git · Tab sections · ? help'
    if #items == 0 and section then hint = 'Tab next section · Esc back · ? help' end
    local again = ({ recent = 'r all recent', prs = 'p all PRs' })[section]
    if again and vim.api.nvim_win_get_width(ctx.win) > 110 then hint = hint .. ' · ' .. again end
    local line = vim.api.nvim_buf_get_lines(ctx.buf, footer - 1, footer, false)[1] or ''
    local margin = #(line:match '^%s*' or '')
    local available = vim.api.nvim_win_get_width(ctx.win) - margin - 1
    hint = require('custom.project_home.layout').clip(hint, available)
    vim.api.nvim_buf_set_extmark(ctx.buf, ns, footer - 1, margin, {
      virt_text = { { hint .. string.rep(' ', math.max(0, #line - margin - vim.fn.strdisplaywidth(hint))), 'ProjectHomeMuted' } },
      virt_text_win_col = margin,
      priority = 220,
    })
  end
end
function M.help(ctx)
  if ctx.help_win and vim.api.nvim_win_is_valid(ctx.help_win) then return end
  local section = ctx.keyboard_section
  local lines = {
    'Keyboard help · ' .. (names[section] or 'Dashboard'),
    '',
    'r  Recent files',
    'p  Pull requests    g  Git workspace',
    'Tab / Shift-Tab     Next / previous section',
    'j / k              Move within section',
    '1–9                Open numbered item',
    'Enter              Open selected item',
    'Esc                Leave section / go back',
    '',
    'f Find   / Search   e Browse   n New',
    'u Resume (if saved)  w Worktrees',
    'a Toggle activity scope   h History',
    'R Refresh',
    'm More actions      q Close dashboard',
    '',
  }
  local again = ({ recent = 'Press r again for all recent files.', prs = 'Press p again for all pull requests.' })[section]
  if again then lines[#lines + 1] = again end
  lines[#lines + 1] = 'Esc / q / ? closes this help'
  local width = math.max(1, math.min(53, vim.o.columns - 4))
  local wrapped = {}
  for _, line in ipairs(lines) do
    while vim.fn.strdisplaywidth(line) > width do
      local chunk = require('custom.project_home.layout').clip(line, width - 1):gsub('…$', '')
      if chunk == '' then chunk = vim.fn.strcharpart(line, 0, 1) end
      wrapped[#wrapped + 1] = chunk
      line = line:sub(#chunk + 1)
    end
    wrapped[#wrapped + 1] = line
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, wrapped)
  vim.bo[buf].modifiable = false
  local height = math.max(1, math.min(#wrapped, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    border = 'rounded',
    style = 'minimal',
  })
  ctx.help_win = win
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    ctx.help_win = nil
  end
  for _, key in ipairs { '<Esc>', 'q', '?' } do
    vim.keymap.set('n', key, close, { buffer = buf, silent = true })
  end
  vim.api.nvim_create_autocmd('BufLeave', { buffer = buf, once = true, callback = function() vim.schedule(close) end })
end
function M.bind(ctx, page)
  ctx.keyboard_active = page.presentation == 'workspace'
  ctx.keyboard_sections, ctx.keyboard_footer = page.sections, page.keyboard_footer
  if not ctx.keyboard_active then return end
  local function map(key, callback)
    ctx.keymaps[key] = true
    vim.keymap.set('n', key, callback, { buffer = ctx.buf, silent = true })
  end
  for key, section in pairs(jumps) do
    map(key, function()
      local action = ({ recent = 'recents', prs = 'prs', git = 'git' })[section]
      -- Empty/loading sections have no cursor target; open their utility directly.
      if ctx.keyboard_section == section or #entries(ctx, section) == 0 then
        ctx.dispatch(action)
      else
        M.section(ctx, section)
      end
    end)
  end
  for i = 1, 9 do
    map(tostring(i), function()
      local item = entries(ctx, ctx.keyboard_section)[i]
      if item then
        focus(ctx, item)
        ctx.dispatch(item.action, item.value)
      end
    end)
  end
  local function cycle(delta)
    local available, index = {}, 0
    for _, section in ipairs(order) do
      if #entries(ctx, section) > 0 then
        available[#available + 1] = section
        -- Empty/loading sections have no cursor target; open their utility directly.
        if ctx.keyboard_section == section or #entries(ctx, section) == 0 then index = #available end
      end
    end
    if #available > 0 then M.section(ctx, available[(index - 1 + delta) % #available + 1]) end
  end
  map('<Tab>', function() cycle(1) end)
  map('<S-Tab>', function() cycle(-1) end)
  map('?', function() M.help(ctx) end)
  map('m', function() ctx.dispatch 'more' end)
end
return M
