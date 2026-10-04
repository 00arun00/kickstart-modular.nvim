local root = vim.fn.getcwd()
vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
vim.opt.rtp:prepend(root)
local view, ui = require 'custom.project_home.volt.view', require 'custom.project_home.ui'
local model = {
  name = 'sample',
  root = root,
  branch = 'main',
  git = { available = false },
  recents = { '日本語.lua', 'test.lua' },
  activity = { status = 'loading' },
}
for _, width in ipairs { 24, 40, 60, 80, 120, 166 } do
  for _, status in ipairs { 'loading', 'unavailable', 'ready' } do
    model.activity.status = status
    local p = view.render(model, width, 50)
    for _, line in ipairs(p.lines) do
      assert(vim.fn.strdisplaywidth(line) <= width)
    end
    for _, item in ipairs(p.items) do
      assert(item.col < item.end_col, 'no empty keyboard targets')
    end
  end
end
-- Recent files use spare rows without hiding the activity chart or footer.
local dense = vim.deepcopy(model)
dense.git = { available = true, changes = {} }
dense.activity = { status = 'ready', identity = 'me', days = {} }
dense.recents = {}
for i = 1, 20 do
  dense.recents[i] = ('file-%02d.lua'):format(i)
end
for _, size in ipairs { { 90, 40 }, { 120, 50 }, { 166, 60 } } do
  local page = view.render(dense, size[1], size[2])
  local count = 0
  for _, item in ipairs(page.items) do
    if item.section == 'recent' and item.action == 'file' then
      count = count + 1
      assert(item.value == dense.recents[count], 'recent order is preserved')
    end
  end
  assert(count > 5 and count <= 9, 'spare space exposes more keyboard-addressable files')
  assert(#page.lines <= size[2], 'expanded recents leave activity and footer visible')
end
dense.prs = { items = { { number = 1, title = 'First' }, { number = 2, title = 'Second' }, { number = 3, title = 'Third' } } }
dense.prs.items[1].statusCheckRollup = { { conclusion = 'FAILURE' } }
dense.git.latest = { hash = 'abcdef', subject = 'Latest commit', date = '2026-10-05' }
for _, size in ipairs { { 60, 32 }, { 80, 40 }, { 90, 40 }, { 120, 45 }, { 166, 50 } } do
  local page = view.render(dense, size[1], size[2])
  local text = table.concat(page.lines, '\n')
  assert(#page.lines <= size[2], 'main content fits ' .. size[1] .. 'x' .. size[2])
  if size[1] == 60 then assert(text:find('1 needs attention', 1, true), 'compact PR summary retains failures') end
  for _, label in ipairs { '█', 'Recent files', 'Git workspace', 'Pull requests', 'Worktrees', 'Activity' } do
    assert(text:find(label, 1, true), 'resize retains ' .. label)
  end
end
local narrow = view.render(dense, 60, 60)
local count = 0
for _, item in ipairs(narrow.items) do
  if item.section == 'recent' and item.action == 'file' then count = count + 1 end
end
assert(count >= 1 and count <= 5, 'stacked layout keeps recent list compact')
-- Run the same keyboard contract against the actual Volt painter.
dofile(root .. '/tests/project_home_keyboard.lua')
local namespace = vim.api.nvim_get_namespaces().project_home_volt
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(not require('volt.state')[buf], 'child without painter cleared Volt state')
local ctx =
  { buf = buf, win = win, layout = 'volt', model = model, generation = 1, items = {}, original_options = ui.capture_options(win), dispatch = function() end }
ui.draw(ctx, view.render(model, 120, 50))
assert(#vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}) > 0, 'visible output is painted by Volt')
assert(require('volt.state')[buf] and not vim.g.extmarks_events, 'Volt rendering does not install global mouse hooks')
-- Empty remote sections retain a real keyboard target after another selection.
local invoked
ctx.dispatch = function(name) invoked = name end
ui.attach(ctx)
model.git = { available = true, changes = {} }
for _, status in ipairs { 'ready', 'loading', 'unavailable' } do
  model.prs = { status = status, items = {} }
  ui.draw(ctx, view.render(model, 120, 50))
  vim.fn.maparg('r', 'n', false, true).callback()
  vim.fn.maparg('p', 'n', false, true).callback()
  invoked = nil
  vim.fn.maparg('<CR>', 'n', false, true).callback()
  assert(invoked == 'prs', status .. ' PR section cannot activate the previously focused file')
end
for _, git in ipairs { { available = false }, { loading = true } } do
  model.git = git
  for key, action in pairs { g = 'git', p = 'prs' } do
    ctx.keyboard_section = nil
    ui.draw(ctx, view.render(model, 120, 50))
    vim.fn.maparg('r', 'n', false, true).callback()
    invoked = nil
    vim.fn.maparg(key, 'n', false, true).callback()
    assert(invoked == action, 'missing section opens its utility instead of leaving a file active')
  end
end
local opened
ctx.dispatch = function(action, value)
  if action == 'file' then opened = value end
end
ctx.keyboard_section = nil
ui.draw(ctx, view.render(dense, 166, 60))
vim.fn.maparg('r', 'n', false, true).callback()
vim.fn.maparg('9', 'n', false, true).callback()
assert(opened == dense.recents[9], 'key 9 opens ninth visible file')
ui.draw(ctx, view.render(dense, 60, 60))
opened = nil
vim.fn.maparg('9', 'n', false, true).callback()
assert(not opened, 'resize removes hidden numbered targets')
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(opened == dense.recents[1], 'resize restores focus to a visible recent file')
local key_before = vim.api.nvim_get_hl(0, { name = 'ProjectHomeVoltKey', link = true })
vim.api.nvim_set_hl(0, 'Title', { fg = 0xCC5588 })
ui.draw(ctx, view.render(model, 120, 50))
assert(vim.api.nvim_get_hl(0, { name = 'ProjectHomeVoltKey', link = true }).fg ~= key_before.fg, 'theme refreshed')
local child = ui.page('Pull request', 'Checks', { { label = 'Check log', action = 'url', value = 'https://example.test' } })
ui.draw(ctx, child)
assert(not require('volt.state')[buf] and not ctx.keyboard_active, 'native detail page clears Volt state and section navigation')
ui.draw(ctx, ui.page('Original', '', {}))
assert(not require('volt.state')[buf] and #vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}) == 0, 'switching renderer clears state and marks')
print 'Volt passed: real rendering, responsive states, keyboard parity, theme refresh, child views, lifecycle isolation'
