local M = {}

local function storage() return vim.fn.stdpath 'data' .. '/scratch/scoped' end

local function git(dir, ...)
  local args = { 'git', '-C', dir }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true }):wait(2000)
  return result.code == 0 and vim.trim(result.stdout) or nil
end

local function context()
  local saved = vim.b.scoped_scratch_context
  if saved then return saved end
  local file = vim.api.nvim_buf_get_name(0)
  local dir = vim.bo.buftype == '' and file ~= '' and vim.fs.dirname(file) or vim.fn.getcwd()
  return { dir = vim.uv.fs_realpath(dir) or dir }
end

local function record(scope, ctx)
  if scope == 'global' then return { scope = scope, name = 'Global' } end
  if vim.fn.isdirectory(ctx.dir) == 0 then
    vim.notify('Scratch source directory no longer exists: ' .. ctx.dir, vim.log.levels.WARN)
    return
  end
  local root = git(ctx.dir, 'rev-parse', '--show-toplevel')
  local project = root and git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')
  -- Git's common directory identifies the repository across linked worktrees.
  -- Outside Git, use the nearest project marker, then the source directory.
  root = root or vim.fs.root(ctx.dir, { 'pyproject.toml', 'package.json', 'Cargo.toml', 'go.mod', 'Makefile' }) or ctx.dir
  project = project or root
  project = vim.uv.fs_realpath(project) or project
  local label = vim.fs.basename(root)
  if project:sub(-5) == '/.git' then label = vim.fs.basename(vim.fs.dirname(project)) end
  local ret = { scope = scope, project = project, dir = root, name = 'Project · ' .. label }
  if scope == 'branch' then
    local branch = git(root, 'symbolic-ref', '--quiet', '--short', 'HEAD')
    if not branch then
      local commit = git(root, 'rev-parse', '--verify', 'HEAD')
      if not commit then
        vim.notify('Branch scratch requires a Git repository.', vim.log.levels.INFO)
        return
      end
      branch = 'detached:' .. commit
    end
    ret.branch = branch
    ret.name = 'Branch · ' .. label .. ' · ' .. branch
  end
  return ret
end

local function path(note)
  local identity = vim.json.encode { note.scope, note.project or '', note.branch or '' }
  return storage() .. '/' .. vim.fn.sha256(identity) .. '.md'
end

local function open(note, ctx)
  vim.fn.mkdir(storage(), 'p')
  local file = path(note)
  vim.fn.writefile({ vim.json.encode(note) }, file .. '.json')
  local win = Snacks.scratch.open {
    file = file,
    name = note.name,
    ft = 'markdown',
    autowrite = true,
    win = { footer_keys = false },
  }
  if win then
    vim.b[win.buf].scoped_scratch_context = ctx
    -- Counts must not imply additional notes: there is exactly one per scope.
    win:set_title(' ' .. note.name .. ' ')
    local function refresh()
      win.opts.footer = {
        { '   ' .. (require('custom.markdown_diagnostics').is_enabled() and 'on' or 'off') .. '  · ', 'Comment' },
        { ' q ', 'SnacksFooterKey' },
        { ' close  ', 'SnacksFooterDesc' },
      }
      win:update()
    end
    refresh()
    -- Keep every open scratch footer in sync with the shared Markdown toggle.
    local group = vim.api.nvim_create_augroup('scratch-diagnostics-' .. win.buf, { clear = true })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'MarkdownDiagnosticsChanged',
      callback = function()
        if win:valid() then refresh() end
      end,
    })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = group,
      buffer = win.buf,
      once = true,
      callback = function() vim.api.nvim_del_augroup_by_id(group) end,
    })
  end
end

function M.toggle(scope)
  local ctx = context()
  local note = record(scope, ctx)
  if note then open(note, ctx) end
end

function M.choose()
  local ctx = context()
  vim.ui.select({ 'branch', 'project', 'global' }, {
    prompt = 'Scratch scope',
    format_item = function(scope) return ({ branch = 'Current branch', project = 'Current project', global = 'Global' })[scope] end,
  }, function(scope)
    if not scope then return end
    local note = record(scope, ctx)
    if note then open(note, ctx) end
  end)
end

function M.find()
  local ctx = context()
  local notes = {}
  for _, meta in ipairs(vim.fn.glob(storage() .. '/*.md.json', false, true)) do
    local ok, note = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(meta), '\n')) end)
    if ok and type(note) == 'table' and note.name and note.scope then
      local file = path(note)
      local stat = vim.uv.fs_stat(file)
      if stat then notes[#notes + 1] = { note = note, file = file, modified = stat.mtime.sec } end
    end
  end
  table.sort(notes, function(a, b) return a.modified > b.modified end)
  if #notes == 0 then return vim.notify('No saved scratch notes yet.', vim.log.levels.INFO) end
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Scratch · All projects and branches',
      finder = require('telescope.finders').new_table {
        results = notes,
        entry_maker = function(entry)
          local label = entry.note.name .. (entry.note.dir and (' · ' .. entry.note.dir) or '')
          return { value = entry, display = label, ordinal = label, filename = entry.file }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      previewer = require('telescope.config').values.file_previewer {},
      attach_mappings = function(prompt_buf)
        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          actions.close(prompt_buf)
          if selected then
            local note = selected.value.note
            open(note, note.scope == 'global' and ctx or { dir = note.dir })
          end
        end)
        return true
      end,
    })
    :find()
end

return M
