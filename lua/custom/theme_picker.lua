local M = {}

function M.open(opts)
  local favorites_store = require 'custom.theme_favorites'
  local favorites = favorites_store.read()
  local function has_favorites()
    for name in pairs(favorites) do
      if opts.registry[name] then return true end
    end
    return false
  end
  local scope = opts.scope or favorites_store.read_scope() or (has_favorites() and 'favorites' or 'all')
  assert(scope == 'all' or scope == 'favorites', 'ThemePicker expects all or favorites')
  local function remember_scope()
    if favorites_store.read_scope() == scope then return end
    local ok, err = pcall(favorites_store.save_scope, scope)
    if not ok then vim.notify('Could not save theme picker view: ' .. tostring(err), vim.log.levels.WARN) end
  end
  local background = 'any'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local finder = require 'telescope.finders'
  local picker, pending, watcher
  local confirmed, closed = false, false
  local empty_ns = vim.api.nvim_create_namespace 'ThemePickerEmpty'

  local function sort_key(name) return vim.fn.tolower(opts.labels[name]):gsub('é', 'e'):gsub('ō', 'o') end

  local function entries()
    local result = {}
    for _, name in ipairs(opts.themes) do
      if (scope == 'all' or favorites[name]) and (background == 'any' or opts.registry[name].background == background) then result[#result + 1] = name end
    end
    table.sort(result, function(a, b) return sort_key(a) < sort_key(b) end)
    return result
  end

  local function make_finder()
    return finder.new_table {
      results = entries(),
      entry_maker = function(name)
        return {
          value = name,
          display = (name == opts.current and '● ' or '  ') .. (favorites[name] and '★ ' or '  ') .. opts.labels[name],
          -- Background metadata and internal IDs should not influence matching.
          ordinal = opts.labels[name]:gsub(' %([^)]*%)$', ''),
        }
      end,
    }
  end

  local function update_ui()
    local count = picker.manager and picker.manager:num_results() or 0
    local title = string.format('Themes · %s · %s · %d/%d', scope == 'all' and 'All' or 'Favorites', background, count, #opts.themes)
    picker.prompt_title = title
    if picker.layout and picker.layout.prompt.border then picker.layout.prompt.border:change_title(title) end
    if picker.layout and picker.layout.results.border then
      picker.layout.results.border:change_title('Tab view · C-s ★ · C-l bg · Enter apply · Esc cancel', 'S')
    end
    vim.api.nvim_buf_clear_namespace(picker.results_bufnr, empty_ns, 0, -1)
    if count == 0 then
      local message = scope == 'favorites' and not has_favorites() and 'No favorites yet — Tab to browse all themes'
        or 'No themes match — Tab changes view; C-l changes background'
      vim.api.nvim_buf_set_extmark(picker.results_bufnr, empty_ns, 0, 0, { virt_text = { { message, 'Comment' } }, virt_text_pos = 'overlay' })
    end
  end

  local function refresh()
    if closed then return end
    local entry = picker:get_selection()
    pending = { name = entry and entry.value, index = entry and picker.manager:find_entry(entry) or 1 }
    picker:refresh(make_finder(), { reset_prompt = false })
  end

  local function reload_favorites()
    local latest = favorites_store.read()
    if not vim.deep_equal(favorites, latest) then
      favorites = latest
      refresh()
    end
  end

  local initial = entries()
  local selected = 1
  for index, name in ipairs(initial) do
    if name == opts.current then selected = index end
  end
  picker = require('telescope.pickers').new(
    require('telescope.themes').get_dropdown {
      previewer = false,
    },
    {
      prompt_title = 'Themes',
      scroll_strategy = 'limit',
      -- Honor the opening theme only with an empty query. Typing selects the
      -- best fuzzy match instead of reusing that row in the filtered results.
      selection_strategy = 'closest',
      default_selection_index = selected,
      finder = make_finder(),
      sorter = require('telescope.config').values.generic_sorter {},
      tiebreak = function(a, b) return sort_key(a.value) < sort_key(b.value) end,
      attach_mappings = function(prompt_bufnr, map)
        local function bind(key, callback)
          map('i', key, callback)
          map('n', key, callback)
        end
        bind('<C-n>', actions.move_selection_next)
        bind('<C-p>', actions.move_selection_previous)
        bind('<Tab>', function()
          favorites = favorites_store.read()
          scope = scope == 'all' and 'favorites' or 'all'
          remember_scope()
          refresh()
        end)
        bind('<C-l>', function()
          background = ({ any = 'dark', dark = 'light', light = 'any' })[background]
          favorites = favorites_store.read()
          refresh()
        end)
        bind('<C-s>', function()
          if picker.manager:num_results() == 0 then return end
          local entry = action_state.get_selected_entry()
          if not entry then return end
          local ok, err = pcall(function()
            favorites = favorites_store.read()
            favorites_store.set(entry.value, not favorites[entry.value])
            favorites = favorites_store.read()
          end)
          if not ok then return vim.notify('Could not save theme favorite: ' .. tostring(err), vim.log.levels.ERROR) end
          refresh()
        end)
        bind('<Esc>', function() actions.close(prompt_bufnr) end)
        actions.select_default:replace(function()
          if picker.manager:num_results() == 0 then return end
          local entry = action_state.get_selected_entry()
          if not entry then return end
          confirmed = true
          actions.close(prompt_bufnr)
          opts.select(entry.value)
        end)
        return true
      end,
    }
  )

  local set_selection = picker.set_selection
  picker.set_selection = function(self, row)
    if closed then return end
    set_selection(self, row)
    local entry = self:get_selection()
    if entry and not pending then opts.preview(entry.value) end
  end
  picker:register_completion_callback(function(self)
    if closed then return end
    if pending then
      local target = pending
      pending = nil
      local index = math.min(target.index or 1, self.manager:num_results())
      for entry in self.manager:iter() do
        if entry.value == target.name then index = self.manager:find_entry(entry) end
      end
      if index > 0 then self:set_selection(self:get_row(index)) end
    end
    update_ui()
  end)
  local close_windows = picker.close_windows
  picker.close_windows = function(status)
    closed = true
    if watcher then
      watcher:stop()
      watcher:close()
      watcher = nil
    end
    close_windows(status)
    opts.close(confirmed)
  end
  picker:find()
  remember_scope()

  -- Keep open pickers in sync too. Markers live in a separate directory from
  -- confirmed theme choices, so starring never triggers terminal publication.
  local directory_ok = pcall(vim.fn.mkdir, favorites_store.directory(), 'p')
  if not directory_ok then return picker end -- Browsing still works if state is read-only.
  watcher = vim.uv.new_fs_event()
  if watcher then
    local started = watcher:start(
      favorites_store.directory(),
      {},
      vim.schedule_wrap(function(err)
        if not closed and not err then reload_favorites() end
      end)
    )
    if not started then
      watcher:close()
      watcher = nil
    end
  end
  return picker
end

return M
