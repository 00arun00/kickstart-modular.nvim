local root = vim.fn.getcwd()
vim.opt.rtp:append(vim.fn.expand '~/.local/share/nvim/lazy/volt')
for _, name in ipairs { 'core', 'volt' } do
  vim.opt.rtp:append(root .. '/plugins/project-home-' .. name)
end
local view, ui = require 'project_home_volt.view', require 'project_home.ui'
local model = {
  name = 'sample',
  root = root,
  branch = 'main',
  git = { available = false },
  recents = { '日本語.lua', 'test.lua' },
  shortcuts = { 'README.md', 'lua/' },
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
-- Run the same keyboard contract against the actual Volt painter.
dofile(root .. '/plugins/project-home-core/tests/keyboard.lua')
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
