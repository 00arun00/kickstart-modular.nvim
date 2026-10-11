-- Each scenario runs in a fresh editor via tests/python/test_trouble.py.
local function run()
  vim.opt.rtp:prepend(vim.fn.getcwd())
  vim.o.swapfile = false
  vim.g.mapleader = ' '
  local root = vim.env.NVIM_TEST_PLUGIN_ROOT or (vim.fn.stdpath 'data' .. '/lazy')
  for _, name in ipairs { 'plenary.nvim', 'telescope.nvim', 'trouble.nvim' } do
    vim.opt.rtp:append(root .. '/' .. name)
  end
  dofile('lua/kickstart/plugins/telescope.lua')[1].config()
  local opts = dofile('lua/custom/plugins/trouble.lua')[1].opts
  local trouble = require 'trouble'
  trouble.setup(opts)
  local bridge = require 'custom.navigation.trouble'
  local export = require('telescope.config').values.mappings.i['<C-t>']
  local function wait(fn, label) assert(vim.wait(3000, fn, 10), label) end
  local function messages(items)
    local ret = {}
    for _, item in ipairs(items) do
      ret[#ret + 1] = item.message
    end
    table.sort(ret)
    return ret
  end
  local function expect(items, expected) assert(vim.deep_equal(messages(items), expected), vim.inspect(messages(items))) end
  local function remove(view, predicate)
    view.win:focus()
    view:action 'fold_open_all'
    local row
    wait(function()
      for line, loc in pairs(view.renderer._locations) do
        if loc.node and predicate(loc.node) then
          row = line
          return true
        end
      end
    end, 'Deletion target did not render')
    vim.api.nvim_win_set_cursor(view.win.win, { row, 0 })
    local before = #view:flatten()
    -- Invoke the installed dd mapping synchronously; Telescope's queued mode
    -- transitions should not decide when this deletion stimulus executes.
    assert(vim.fn.maparg('dd', 'n', false, true).callback)()
    wait(function() return #view:flatten() < before end, 'dd did not remove the target')
  end
  local function remove_message(view, message)
    remove(view, function(node) return not node.group and node.item and node.item.message == message end)
  end
  local function picker_items(picker)
    local items = {}
    for entry in picker.manager:iter() do
      items[#items + 1] = entry.trouble_item
    end
    return items
  end
  local function to_picker(view, expected)
    bridge.to_telescope(view)
    local picker
    wait(function()
      if vim.bo.filetype ~= 'TelescopePrompt' then return false end
      picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
      return picker and picker.manager and picker.manager:num_results() == #expected
    end, 'Wrong exported result count')
    expect(picker_items(picker), expected)
    return picker
  end
  local function to_worklist(picker, expected, previous)
    export(picker.prompt_bufnr)
    local view
    wait(function()
      view = require('trouble.api')._find_last 'worklist'
      return view and view ~= previous and view.win:valid() and vim.api.nvim_get_current_win() == view.win.win and #view:flatten() == #expected
    end, 'New snapshot did not open')
    expect(view:flatten(), expected)
    return view
  end

  local files, buffers = {}, {}
  for i = 1, 2 do
    files[i] = vim.env.TROUBLE_TEST_PROJECT .. '/file' .. i .. '.py'
    vim.fn.writefile({ 'one', 'two', 'three' }, files[i])
    vim.cmd.edit(files[i])
    buffers[i] = vim.api.nvim_get_current_buf()
  end
  local ns = vim.api.nvim_create_namespace 'trouble-deletion-test'
  vim.diagnostic.set(ns, buffers[1], {
    { lnum = 0, col = 0, message = 'A', severity = 1, source = 'ruff', code = 'A100' },
    { lnum = 1, col = 0, message = 'B', severity = 1, source = 'ruff', code = 'B100' },
  })
  vim.diagnostic.set(ns, buffers[2], {
    { lnum = 2, col = 1, message = 'C', severity = 2, source = 'ruff', code = 'C100' },
  })
  vim.fn.setqflist { { bufnr = buffers[1], lnum = 1, text = 'Keep this list' } }
  local quickfix = vim.fn.getqflist()
  local live = trouble.open { mode = 'diagnostics', focus = true }
  wait(function() return live.win:valid() and #live:flatten() == 3 end, 'Initial diagnostics did not render')
  local scenario = vim.env.TROUBLE_TEST_SCENARIO
  if scenario == 'row' or scenario == 'roundtrip' then
    remove_message(live, 'B')
    local picker = to_picker(live, { 'A', 'C' })
    if scenario == 'roundtrip' then
      local first = to_worklist(picker, { 'A', 'C' })
      remove_message(first, 'A')
      local second = to_worklist(to_picker(first, { 'C' }), { 'C' }, first)
      local item = picker_items(to_picker(second, { 'C' }))[1]
      assert(item.filename == files[2] and item.pos[1] == 3 and item.pos[2] == 1)
      assert(item.severity == 2 and item.item.source == 'ruff' and item.code == 'C100')
      expect(live:flatten(), { 'A', 'C' })
      expect(first:flatten(), { 'C' })
    end
  elseif scenario == 'group' then
    remove(live, function(node) return node.group and vim.tbl_contains(node.group.fields or {}, 'filename') and node.item.filename == files[1] end)
    to_picker(live, { 'C' })
  elseif scenario == 'folded' then
    live:action 'fold_close_all'
    to_picker(live, { 'A', 'B', 'C' })
  elseif scenario == 'empty' then
    for _, message in ipairs { 'A', 'B', 'C' } do
      remove_message(live, message)
    end
    local notified
    local notify = vim.notify
    vim.notify = function(message) notified = message end
    bridge.to_telescope(live)
    vim.notify = notify
    assert(notified == 'No Trouble results to send to Telescope', tostring(notified))
    assert(vim.api.nvim_get_current_win() == live.win.win, 'Empty export changed focus')
  else
    error('Unknown scenario: ' .. tostring(scenario))
  end
  assert(#vim.diagnostic.get(nil, { namespace = ns }) == 3, 'Deletion changed underlying diagnostics')
  assert(vim.deep_equal(quickfix, vim.fn.getqflist()), 'Export changed quickfix')
  print('PASS: Trouble deletion export ' .. scenario)
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
