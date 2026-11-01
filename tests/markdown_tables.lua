-- Real render-markdown/Snacks integration with deterministic image conversion.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/snacks.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/lazy/render-markdown.nvim')
vim.opt.rtp:append(vim.fn.stdpath 'data' .. '/site')
local cache = vim.fn.tempname()
require('snacks').setup { image = { enabled = false, cache = cache } }
local terminal = Snacks.image.terminal
terminal.env = function() return { supported = true, placeholders = true } end
terminal.size = function() return { cell_width = 10, cell_height = 20, scale = 1 } end
terminal.request = function() end
local transport = assert(loadfile(vim.fn.getcwd() .. '/tests/support/markdown_document.lua'))().transport()
local images = transport.images
local held, hold = {}, false
local find = Snacks.image.doc.find
Snacks.image.doc.find = function(buf, cb, opts)
  find(buf, function(matches)
    if hold then
      held[#held + 1] = function() cb(matches) end
    else
      cb(matches)
    end
  end, opts)
end
local source = {
  '# Transport',
  '',
  '| Ordinary | Table |',
  '| --- | --- |',
  '| Native | Text |',
  '',
  '| Branch | Quantity $\\psi$ | Governing equation |',
  '| --- | --- | --- |',
  '| **Mass Transport** | Density $\\rho$ | **Continuity**<br>$$\\frac{\\partial\\rho}{\\partial t}=0$$ |',
  '| **Momentum Transport** | Momentum $\\rho\\mathbf{v}$ | **Navier–Stokes**<br>$$\\rho\\mathbf{v}=\\mathbf{f}$$ |',
  '| **Energy Transport** | Energy $\\rho e$ | **Energy equation**<br>$$e=q+s$$ |',
}
local file = vim.fn.tempname() .. '.md'
-- The same formula appears inline and in a display cell at different sizes.
source[7] = '| Branch | Quantity $e=q+s$ | Governing equation |'
vim.fn.writefile(source, file)
vim.cmd.edit(file)
vim.bo.filetype = 'markdown'
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local tick = vim.api.nvim_buf_get_changedtick(buf)
local disk = table.concat(vim.fn.readfile(file, 'b'), '\n')
local spec = require('custom.plugins.render-markdown')[1]
-- Keep the existing cursor-reveal checks in Editing mode.
require('custom.markdown.reading').toggle()
spec.config(nil, vim.tbl_deep_extend('force', spec.opts, { debounce = 0, render_modes = true, anti_conceal = { enabled = false } }))
vim.cmd 'runtime plugin/render-markdown.lua'
local controller = require('custom.markdown.document').new(buf)
local renderer = require 'render-markdown'
local ns = require('render-markdown.core.ui').ns
local function marks()
  local result = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  vim.list_extend(result, vim.api.nvim_buf_get_extmarks(buf, require('custom.markdown.tables').ns, 0, -1, { details = true }))
  return result
end
local function table_mark()
  for _, mark in ipairs(marks()) do
    if mark[2] == 6 and mark[4].virt_lines and mark[4].conceal == '' then return mark end
  end
end
local function wait_for(fn, message) assert(vim.wait(5000, fn), message) end
renderer.render { buf = buf }
wait_for(table_mark, 'inline table did not render')
local function check()
  local mark = assert(table_mark())
  local rows = {}
  local all = marks()
  for _, anchor in ipairs(all) do
    if anchor[2] >= 6 and anchor[2] <= 10 and anchor[4].conceal == '' and anchor[4].virt_text then
      vim.list_extend(rows, anchor[4].virt_lines or {})
      rows[#rows + 1] = anchor[4].virt_text
      for _, other in ipairs(all) do
        if other[2] == anchor[2] and other[4].virt_lines and not other[4].virt_lines_above then vim.list_extend(rows, other[4].virt_lines) end
      end
    end
  end
  local ids, text = {}, {}
  for _, row in ipairs(rows) do
    local width, words = 0, ''
    for _, chunk in ipairs(row) do
      width = width + vim.fn.strdisplaywidth(chunk[1])
      if type(chunk[2]) == 'string' and chunk[2]:match '^SnacksImage%d+$' then
        ids[chunk[2]] = true
      else
        words = words .. chunk[1]
      end
    end
    assert(width <= vim.api.nvim_win_get_width(win), 'inline table overflowed')
    text[#text + 1] = words
  end
  assert(vim.tbl_count(ids) == 7, 'missing/duplicated table equations')
  assert(table.concat(text, '\n'):find('Continuity', 1, true), 'native labels missing')
  assert(mark[4].conceal == '', 'raw table text was not concealed')
  local ordinary = false
  for _, m in ipairs(marks()) do
    if m[2] >= 2 and m[2] <= 4 then ordinary = true end
    assert(m[2] ~= 5, 'native table border remained above the custom table')
  end
  assert(ordinary, 'ordinary table renderer was removed')
  return table.concat(text, '\n')
end
check()
local wide_width = vim.api.nvim_win_get_width(win)
local narrow_width = math.floor(wide_width * 0.45)
local function rendered_width()
  local mark = table_mark()
  if not mark then return 0 end
  local width = 0
  for _, chunk in ipairs(mark[4].virt_text) do
    width = width + vim.fn.strdisplaywidth(chunk[1])
  end
  return width
end
vim.cmd 'vsplit'
local other = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(win, narrow_width)
renderer.render { buf = buf }
wait_for(function() return rendered_width() == narrow_width end, 'inline table did not reflow for narrow splits')
check()
vim.api.nvim_win_close(other, true)
renderer.render { buf = buf }
wait_for(function() return rendered_width() == wide_width end, 'inline table did not restore after closing split')
assert(vim.api.nvim_get_current_buf() == buf and #vim.api.nvim_list_tabpages() == 1, 'rendering opened a different buffer/tab')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source))
assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo.modified, 'rendering changed the source')
vim.cmd 'silent write'
assert(table.concat(vim.fn.readfile(file, 'b'), '\n') == disk, 'saving wrote rendered content')

-- Enter any source row to reveal the whole original table; leave to render it.
vim.api.nvim_win_set_cursor(win, { 10, 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
wait_for(function() return not table_mark() end, 'table source was not revealed')
for _, mark in ipairs(marks()) do
  assert(mark[2] < 6, 'partial table concealment remained while editing')
end
vim.api.nvim_win_set_cursor(win, { 1, 0 })
vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
wait_for(table_mark, 'leaving table did not restore rendering')

-- The document owner must not independently place table equations.
for _, img in pairs(controller.imgs) do
  assert(img.opts.type ~= 'math' or img.opts.range[1] < 7, 'duplicate Snacks table equation')
end

-- An obsolete serialized discovery must yield to the latest source revision.
hold = true
source[9] = source[9]:gsub('Mass Transport', 'Intermediate label')
vim.api.nvim_buf_set_lines(buf, 8, 9, false, { source[9] })
controller:update()
wait_for(function() return #held >= 1 end, 'first parse was not held')
source[9] = source[9]:gsub('Intermediate label', 'Final label')
vim.api.nvim_buf_set_lines(buf, 8, 9, false, { source[9] })
controller:update()
hold = false
for _, callback in ipairs(held) do
  callback()
end
wait_for(function() return table_mark() and check():find('Final label', 1, true) end, 'stale parsing overwrote current layout')
assert(not check():find('Intermediate label', 1, true))

-- Renderer toggling removes/reinstates all inline table decorations.
renderer.buf_disable()
wait_for(function() return #marks() == 0 end, 'disabled renderer left table artifacts')
renderer.buf_enable()
wait_for(table_mark, 'enabled renderer did not restore table')
check()
vim.cmd 'enew!'
vim.api.nvim_buf_delete(buf, { force = true })
for _, img in pairs(images) do
  assert(vim.tbl_isempty(img.placements), 'equation listener leaked')
end
vim.fn.delete(file)
vim.fn.delete(cache, 'rf')
print 'Inline math tables: virtual cells, EOF, native tables, source reveal, byte-exact saves, async edit ordering and cleanup passed'
