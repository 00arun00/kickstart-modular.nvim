local M = {}
local state = function() return require 'custom.project_home.state' end
local function suggestions(root)
  local out = {}
  for _, p in ipairs { 'README.md', 'init.lua', 'package.json', 'pyproject.toml', 'Cargo.toml', 'go.mod', 'src/', 'lua/', 'tests/', 'docs/' } do
    if #out >= 5 then break end
    if (vim.uv or vim.loop).fs_stat(root .. '/' .. p) then out[#out + 1] = p end
  end
  return out
end
local function normalized(root, paths, require_exists)
  local out, seen = {}, {}
  for _, path in ipairs(type(paths) == 'table' and paths or {}) do
    if type(path) == 'string' and path ~= '' and path:sub(1, 1) ~= '/' and not path:find '%z' then
      local absolute = vim.fs.normalize(root .. '/' .. path)
      if absolute:sub(1, #root + 1) == root .. '/' then
        local stat = (vim.uv or vim.loop).fs_stat(absolute)
        local relative = absolute:sub(#root + 2)
        if path:sub(-1) == '/' or (stat and stat.type == 'directory') then relative = relative .. '/' end
        if (stat or not require_exists) and not seen[relative] then
          out[#out + 1] = relative
          seen[relative] = true
          if #out >= 5 then break end
        end
      end
    end
  end
  return out
end
function M.get(root)
  local data = state().get(root)
  if type(data.shortcuts) ~= 'table' then
    data.shortcuts = suggestions(root)
    state().update(root, 'shortcuts', data.shortcuts)
  end
  local entries = {}
  for _, path in ipairs(normalized(root, data.shortcuts, true)) do
    entries[#entries + 1] = { path = path, label = path }
  end
  return entries
end
function M.edit(root, done)
  M.get(root)
  local draft = normalized(root, state().get(root).shortcuts, false)
  local menu
  local function save()
    local ok, err = state().update(root, 'shortcuts', draft)
    if not ok then
      vim.notify('Could not save shortcuts: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    done()
  end
  local function add()
    if #draft >= 5 then
      vim.notify 'Keep up to five project shortcuts.'
      menu()
      return
    end
    vim.ui.input({ prompt = 'Existing project-relative file or folder: ' }, function(p)
      if p and p ~= '' then
        local absolute = vim.fs.normalize(root .. '/' .. p)
        if p:sub(1, 1) == '/' or absolute:sub(1, #root + 1) ~= root .. '/' or not (vim.uv or vim.loop).fs_stat(absolute) then
          vim.notify('Choose an existing path inside this project.', vim.log.levels.WARN)
        else
          local relative = absolute:sub(#root + 2)
          if vim.fn.isdirectory(absolute) == 1 then relative = relative:gsub('/$', '') .. '/' end
          if vim.tbl_contains(draft, relative) then
            vim.notify 'That shortcut already exists.'
          else
            draft[#draft + 1] = relative
          end
        end
      end
      menu()
    end)
  end
  menu = function()
    local items = {}
    for i, p in ipairs(draft) do
      items[#items + 1] = { label = i .. '. ' .. p .. ((vim.uv or vim.loop).fs_stat(root .. '/' .. p) and '' or ' · missing'), index = i }
    end
    for _, a in ipairs { 'Add shortcut', 'Restore suggestions', 'Save shortcuts', 'Discard changes' } do
      items[#items + 1] = { label = a }
    end
    vim.ui.select(items, { prompt = 'Edit shortcuts · saved order stays fixed', format_item = function(i) return i.label end }, function(choice)
      if not choice or choice.label == 'Discard changes' then return end
      if choice.index then
        vim.ui.select({ 'Move up', 'Move down', 'Remove' }, { prompt = draft[choice.index] }, function(action)
          local i = choice.index
          if action == 'Remove' then
            table.remove(draft, i)
          elseif action == 'Move up' and i > 1 then
            draft[i], draft[i - 1] = draft[i - 1], draft[i]
          elseif action == 'Move down' and i < #draft then
            draft[i], draft[i + 1] = draft[i + 1], draft[i]
          end
          menu()
        end)
      elseif choice.label == 'Add shortcut' then
        add()
      elseif choice.label == 'Restore suggestions' then
        draft = suggestions(root)
        menu()
      elseif choice.label == 'Save shortcuts' then
        save()
      end
    end)
  end
  menu()
end
return M
