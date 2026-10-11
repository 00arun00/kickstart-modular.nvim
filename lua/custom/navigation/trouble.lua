local M = {}

-- Copy locations and producer metadata, not live view state or symbol parents.
-- A selected child symbol should not bring an unselected parent back with it.
local function snapshot(item)
  return require('trouble.item').new {
    source = item.source,
    buf = item.buf,
    filename = item.filename,
    pos = vim.deepcopy(item.pos),
    end_pos = vim.deepcopy(item.end_pos),
    range = vim.deepcopy(item.range),
    item = vim.deepcopy(item.item),
    severity = item.severity,
    code = item.code,
    kind = item.kind,
    text = item.message or (item.symbol and item.symbol.name) or item.text or '',
  }
end

local function open_worklist(items)
  local sources = require 'trouble.sources'
  if not sources.sources.custom_worklist then
    sources.register('custom_worklist', {
      config = {
        modes = {
          worklist = {
            source = 'custom_worklist',
            desc = 'Selected Trouble results',
            groups = { { 'filename', format = '{file_icon} {filename} {count}' } },
            sort = { 'filename', 'pos' },
            format = '{severity_icon} {text} {item.source} {code} {pos}',
          },
        },
      },
      get = function(cb, ctx) cb(ctx.opts.params and ctx.opts.params.items or {}) end,
    })
  end
  -- Each view owns its snapshot; later transfers cannot replace its items.
  require('trouble').open { mode = 'worklist', new = true, focus = true, params = { items = items } }
end

function M.to_trouble(prompt_bufnr)
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
  local entries = picker:get_multi_selection()
  if #entries == 0 and picker.manager then
    for entry in picker.manager:iter() do
      entries[#entries + 1] = entry
    end
  end
  if #entries == 0 then
    vim.notify('No Telescope results to send to Trouble', vim.log.levels.INFO)
    return
  end

  -- Ordinary pickers retain the upstream adapter. Our round-trip picker carries
  -- the original Trouble item so severity/source/code survive the return trip.
  if not entries[1].trouble_item then return require('trouble.sources.telescope').open(prompt_bufnr, { focus = true }) end
  local items = vim.tbl_map(function(entry) return snapshot(entry.trouble_item) end, entries)
  require('telescope.actions').close(prompt_bufnr)
  vim.schedule(function() open_worklist(items) end)
end

function M.to_telescope(view)
  local items = {}
  -- Section items have already passed both mode and interactive filters.
  -- Include folded results too: collapsing a file is not a selection filter.
  for _, section in ipairs(view.sections) do
    for _, item in ipairs(section.items) do
      items[#items + 1] = snapshot(item)
    end
  end
  if #items == 0 then
    vim.notify('No Trouble results to send to Telescope', vim.log.levels.INFO)
    return
  end

  view:goto_main()
  local conf = require('telescope.config').values
  local make_entry = require('telescope.make_entry').gen_from_quickfix()
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Trouble: ' .. view.opts.mode,
      finder = require('telescope.finders').new_table {
        results = items,
        entry_maker = function(item)
          local metadata = {}
          for _, value in ipairs { vim.diagnostic.severity[item.severity] or '', item.item.source or '', item.code or '' } do
            if value ~= '' then metadata[#metadata + 1] = tostring(value) end
          end
          local entry = make_entry {
            bufnr = item.buf,
            filename = item.filename,
            lnum = item.pos[1],
            col = item.pos[2] + 1,
            text = table.concat(metadata, ' ') .. ' ' .. item.text:gsub('\n', ' '),
          }
          entry.trouble_item = item
          return entry
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.qflist_previewer {},
    })
    :find()
end

return M
