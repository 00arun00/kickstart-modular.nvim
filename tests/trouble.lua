-- Run with: nvim --headless -n -u NONE -i NONE -l tests/trouble.lua
-- Requires the installed Trouble, Telescope, and Plenary plugins.
local function run()
  vim.opt.rtp:prepend(vim.fn.getcwd())
  vim.o.swapfile = false
  vim.g.mapleader = ' '
  local root = vim.env.NVIM_TEST_PLUGIN_ROOT or (vim.fn.stdpath 'data' .. '/lazy')
  for _, name in ipairs { 'plenary.nvim', 'telescope.nvim', 'trouble.nvim' } do
    assert(vim.fn.isdirectory(root .. '/' .. name) == 1, 'Missing test dependency: ' .. name)
    vim.opt.rtp:append(root .. '/' .. name)
  end
  dofile('lua/kickstart/plugins/telescope.lua')[1].config()
  local opts = dofile('lua/custom/plugins/trouble.lua')[1].opts
  local trouble = require 'trouble'
  trouble.setup(opts)
  local bridge = require 'custom.navigation.trouble'
  local mappings = require('telescope.config').values.mappings
  local actions = require 'telescope.actions'
  for _, mode in ipairs { 'i', 'n' } do
    assert(type(mappings[mode]['<C-t>']) == 'function')
    assert(mappings[mode]['<M-t>'] == actions.select_tab)
    assert(mappings[mode]['<C-g>'] == nil)
  end

  local function wait_for(fn, label) assert(vim.wait(3000, fn, 10), label) end
  local function visible(view, count)
    wait_for(function() return view.win:valid() and #view.sections[1].items == count end, 'View did not render expected items')
  end
  local function picker_with(count)
    local picker
    wait_for(function()
      if vim.bo.filetype ~= 'TelescopePrompt' then return false end
      picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
      return picker and picker.manager and picker.manager:num_results() == count
    end, 'Picker did not populate expected items')
    return picker
  end
  local function returned(count)
    local view
    wait_for(function()
      view = require('trouble.api')._find_last 'worklist'
      return view and view.win:valid() and vim.api.nvim_get_current_win() == view.win.win and #view.sections[1].items == count
    end, 'Selected worklist did not open')
    return view
  end

  local file = vim.fn.tempname() .. '.py'
  vim.fn.writefile({ 'import os', 'artifact = 1', 'other = 2' }, file)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  local other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(other, file .. '.other')
  local ns = vim.api.nvim_create_namespace 'trouble-roundtrip-test'
  local diagnostics = {
    { lnum = 0, col = 0, message = 'Unused import', severity = 1, source = 'ruff', code = 'F401' },
    { lnum = 1, col = 0, message = 'Artifact aliases', severity = 1, source = 'basedpyright', code = 'reportAttributeAccessIssue' },
    { lnum = 2, col = 0, message = 'Spelling warning', severity = 2, source = 'codebook' },
  }
  vim.diagnostic.set(ns, buf, diagnostics)
  vim.diagnostic.set(ns, other, { { lnum = 0, col = 0, message = 'Different file', severity = 1 } })
  vim.fn.setqflist { { bufnr = buf, lnum = 3, text = 'Keep my quickfix list' } }
  local quickfix = vim.fn.getqflist()

  local live = trouble.open { mode = 'diagnostics', focus = true }
  visible(live, 4)
  opts.keys.gs.action(live)
  live:filter({ buf = buf }, { id = 'buffer' })
  visible(live, 2)
  live:action 'fold_close_all'
  opts.keys['<C-t>'].action(live)
  local picker = picker_with(2)
  picker:set_prompt 'Artifact'
  picker_with(1)
  mappings.i['<C-t>'](picker.prompt_bufnr)
  local selected = returned(1)
  local item = selected.sections[1].items[1]
  assert(item.severity == 1 and item.item.source == 'basedpyright')
  assert(item.code == 'reportAttributeAccessIssue' and item.pos[1] == 2 and item.pos[2] == 0)
  assert(trouble.is_open 'diagnostics', 'Original live view closed')
  assert(vim.deep_equal(quickfix, vim.fn.getqflist()), 'Transfer modified quickfix')
  opts.keys.gs.action(selected)
  visible(selected, 1)
  opts.keys.gs.action(selected)
  visible(selected, 0)
  selected:filter({}, { id = 'severity', del = true })
  visible(selected, 1)

  -- Live diagnostics can change without changing the captured worklist.
  vim.diagnostic.set(ns, buf, { diagnostics[3] })
  wait_for(function() return #live.sections[1].items == 0 end, 'Live diagnostics did not update')
  assert(#selected.sections[1].items == 1 and item.item.message == 'Artifact aliases')
  bridge.to_telescope(selected)
  picker = picker_with(1)
  mappings.n['<C-t>'](picker.prompt_bufnr)
  local again = returned(1)
  wait_for(function() return require('trouble.api')._find_last 'worklist' ~= selected end, 'Round trip reused original snapshot')
  again = require('trouble.api')._find_last 'worklist'
  assert(again.sections[1].items[1].code == item.code)

  -- Marks take precedence over the rest of the matches.
  vim.diagnostic.set(ns, buf, diagnostics)
  visible(live, 2)
  bridge.to_telescope(live)
  picker = picker_with(2)
  picker:set_selection(picker:get_row(1))
  actions.toggle_selection(picker.prompt_bufnr)
  local marked = picker:get_multi_selection()[1].trouble_item
  mappings.i['<C-t>'](picker.prompt_bufnr)
  wait_for(function() return require('trouble.api')._find_last 'worklist' ~= again end, 'Marked selection did not open')
  local marked_view = returned(1)
  assert(marked_view.sections[1].items[1].code == marked.code)

  -- Option-T still performs Telescope's standard new-tab action.
  bridge.to_telescope(marked_view)
  picker = picker_with(1)
  picker:set_selection(picker:get_row(1))
  local tabs = #vim.api.nvim_list_tabpages()
  mappings.i['<M-t>'](picker.prompt_bufnr)
  assert(#vim.api.nvim_list_tabpages() == tabs + 1)
  assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(file), vim.api.nvim_buf_get_name(0))

  -- An ordinary file picker still uses the upstream Trouble adapter.
  require('telescope.pickers')
    .new({}, {
      finder = require('telescope.finders').new_table { results = { file }, entry_maker = require('telescope.make_entry').gen_from_file() },
      sorter = require('telescope.config').values.generic_sorter {},
    })
    :find()
  picker = picker_with(1)
  mappings.i['<C-t>'](picker.prompt_bufnr)
  wait_for(function() return #trouble.get_items 'telescope_files' == 1 end, 'Ordinary Telescope export failed')
  vim.fn.delete(file)
  print 'Trouble round-trip, filtering, metadata, selection, quickfix isolation, and new-tab checks passed'
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
