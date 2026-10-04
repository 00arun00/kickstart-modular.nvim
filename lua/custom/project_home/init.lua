local M = { renderers = {}, contexts = {}, options = { default = 'volt', startup = true } }
local ui = require 'custom.project_home.ui'
local state = require 'custom.project_home.state'
local function root_for(path)
  path = path or vim.fn.getcwd()
  return vim.fs.root(path, { '.git' }) or vim.fn.getcwd()
end
local function save_session(root)
  local session = require('custom.project_home.sessions').capture(root)
  if session then return state.update(root, 'session', session) end
  return false, 'Open a project file before saving a workspace.'
end
local function empty_buffer(buf)
  return vim.bo[buf].buftype == ''
    and vim.api.nvim_buf_get_name(buf) == ''
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '') == ''
end
function M.register(name, renderer)
  assert(type(name) == 'string' and type(renderer) == 'function', 'register requires a layout name and renderer')
  M.renderers[name] = renderer
end
function M.layouts()
  local names = vim.tbl_keys(M.renderers)
  table.sort(names)
  return names
end
function M.open(layout, opts)
  opts = opts or {}
  local explicit = layout ~= nil
  layout = layout or M.options.default
  if not explicit and not M.renderers[layout] then layout = M.renderers.volt and 'volt' or M.layouts()[1] end
  if not M.renderers[layout] then
    vim.notify('Project home layout is not registered: ' .. tostring(layout), vim.log.levels.WARN)
    return
  end
  M.options.default = layout
  local existing = M.contexts[vim.api.nvim_get_current_buf()]
  local initial_root = vim.fs.normalize(
    opts.root or (existing and existing.model.root) or root_for(vim.api.nvim_buf_get_name(0) ~= '' and vim.api.nvim_buf_get_name(0) or vim.fn.getcwd())
  )
  initial_root = vim.uv.fs_realpath(initial_root) or initial_root
  if existing and ui.valid(existing) and existing.model.root == initial_root then
    if existing.layout ~= layout then existing.keyboard_section = nil end
    existing.layout = layout
    existing.home()
    return existing
  end
  local original_options = existing and existing.original_options or ui.capture_options(vim.api.nvim_get_current_win())
  local owned_tab = false
  if existing then opts.reuse = true end
  if not opts.reuse and not empty_buffer(vim.api.nvim_get_current_buf()) then
    save_session(initial_root)
    vim.cmd.tabnew()
    owned_tab = true
  end
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  local ctx = {
    owned_tab = owned_tab,
    original_options = original_options,
    buf = buf,
    win = win,
    layout = layout,
    generation = 0,
    scope = 'repo',
    pages = {},
    previous = previous,
    model = {
      root = initial_root,
      name = vim.fs.basename(initial_root),
      title = vim.fs.basename(initial_root),
      branch = '',
      git = { available = false, loading = true, changes = {} },
      prs = { items = {}, status = 'loading' },
      worktrees = {},
      activity = { days = {}, status = 'loading' },
      recents = {},
    },
  }
  M.contexts[buf] = ctx
  ctx.guard = function(fn)
    local generation = ctx.generation
    return function(...)
      if ui.valid(ctx) and generation == ctx.generation then return fn(...) end
    end
  end
  ctx.render = function()
    if not ui.valid(ctx) then return end
    ctx.model.scope = ctx.scope
    if #ctx.pages > 0 then
      local page = ctx.pages[#ctx.pages]
      ui.draw(ctx, page)
      return
    end
    local ok, page = pcall(M.renderers[ctx.layout], ctx.model, vim.api.nvim_win_get_width(ctx.win), vim.api.nvim_win_get_height(ctx.win))
    if ok and type(page) == 'table' then
      ui.draw(ctx, page)
    else
      ui.draw(ctx, ui.page('Project home', 'Layout failed to render', { { label = tostring(page) } }))
    end
  end
  ctx.remember_focus = function()
    local position = vim.api.nvim_win_get_cursor(ctx.win)
    local focus = { position = position }
    for _, item in ipairs(ctx.items or {}) do
      if item.line == position[1] and (item.col or 0) == position[2] then
        focus.action = item.action
        focus.value = item.value
        focus.section = item.section
        break
      end
    end
    if #ctx.pages > 0 then
      ctx.pages[#ctx.pages]._focus = focus
    else
      ctx.home_focus = focus
    end
  end
  ctx.show = function(page)
    if ctx.updating_live and #ctx.pages > 0 then
      ctx.pages[#ctx.pages] = page
    else
      ctx.remember_focus()
      ctx.pages[#ctx.pages + 1] = page
    end
    ctx.render()
  end
  ctx.replace = function(page)
    ctx.force_focus = true
    if #ctx.pages == 0 then
      ctx.pages[1] = page
    else
      ctx.pages[#ctx.pages] = page
    end
    ctx.render()
  end
  ctx.home = function()
    ctx.pages = {}
    ctx.render()
  end
  ctx.refresh = function()
    if ctx.cancel then ctx.cancel() end
    local load_generation = (ctx.load_generation or 0) + 1
    ctx.load_generation = load_generation
    ctx.cancel = require('custom.project_home.providers').load(initial_root, function(model)
      if not ui.valid(ctx) or ctx.load_generation ~= load_generation then return end
      model.title = model.name or vim.fs.basename(model.root)
      local stored = state.get(model.root)
      model.recents = {}
      for _, path in ipairs(type(stored.recents) == 'table' and stored.recents or {}) do
        if type(path) == 'string' and path:sub(1, #model.root + 1) == model.root .. '/' and vim.fn.filereadable(path) == 1 then
          model.recents[#model.recents + 1] =
            { path = path, label = path:sub(1, #model.root + 1) == model.root .. '/' and path:sub(#model.root + 2) or vim.fs.basename(path) }
        end
      end
      model.session = require('custom.project_home.sessions').inspect(stored.session, false, model.root) and stored.session or nil
      if ctx.scope_root ~= model.root then
        ctx.scope = stored.scope == 'you' and 'you' or 'repo'
        ctx.scope_root = model.root
      end
      model.show_activity = stored.activity_visible
      if type(model.show_activity) ~= 'boolean' then model.show_activity = M.options.activity ~= false end
      ctx.model = model
      local page = ctx.pages[#ctx.pages]
      if page and page.live_action then
        ctx.updating_live = true
        require('custom.project_home.actions').dispatch(ctx, page.live_action)
        ctx.updating_live = false
      end
      ctx.render()
    end)
  end
  ctx.dispatch = function(action, value)
    if value == vim.NIL then value = nil end
    if not ui.valid(ctx) then return end
    ctx.generation = ctx.generation + 1
    if action == 'keyboard_help' then
      require('custom.project_home.keyboard').help(ctx)
    elseif action == 'home' then
      ctx.home()
    elseif action == 'back' then
      table.remove(ctx.pages)
      ctx.restore_focus = #ctx.pages > 0 and ctx.pages[#ctx.pages]._focus or ctx.home_focus
      ctx.render()
    elseif action == 'refresh' then
      ctx.refresh()
    elseif action == 'activity_visibility' then
      ctx.model.show_activity = not ctx.model.show_activity
      state.update(ctx.model.root, 'activity_visible', ctx.model.show_activity)
      ctx.home()
    elseif action == 'close' then
      ui.restore_options(ctx)
      if ctx.owned_tab and #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd.tabclose()
        return
      end
      if vim.api.nvim_buf_is_valid(ctx.previous) then
        vim.api.nvim_win_set_buf(ctx.win, ctx.previous)
      else
        vim.api.nvim_win_set_buf(ctx.win, vim.api.nvim_create_buf(true, false))
      end
      ui.restore_options(ctx)
    else
      local ok, err = pcall(require('custom.project_home.actions').dispatch, ctx, action, value)
      if not ok then vim.notify('Project home: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  end
  ui.attach(ctx)
  ui.highlights()
  ctx.render()
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if ctx.cancel then ctx.cancel() end
      M.contexts[buf] = nil
    end,
  })
  ctx.refresh()
  return ctx
end
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.options, opts or {})
  local group = vim.api.nvim_create_augroup('ProjectHomeCore', { clear = true })
  ui.highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      ui.highlights()
      for _, ctx in pairs(M.contexts) do
        ctx.render()
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      for _, ctx in pairs(M.contexts) do
        ctx.render()
      end
    end,
  })
  vim.api.nvim_create_user_command(
    'ProjectHome',
    function(args) M.open(args.args ~= '' and args.args or nil) end,
    { nargs = '?', complete = function() return M.layouts() end, force = true }
  )
  vim.api.nvim_create_user_command('ProjectHomeActivity', function()
    local ctx = M.contexts[vim.api.nvim_get_current_buf()]
    if ctx then
      ctx.dispatch 'activity_visibility'
    else
      local root = root_for(vim.fn.getcwd())
      local visible = state.get(root).activity_visible ~= false
      state.update(root, 'activity_visible', not visible)
      vim.notify('Project activity ' .. (visible and 'hidden' or 'shown'))
    end
  end, { force = true })
  vim.api.nvim_create_user_command('ProjectHomeSessionSave', function()
    local ok, err = save_session(root_for(vim.api.nvim_buf_get_name(0)))
    vim.notify(ok and 'Workspace session saved.' or tostring(err), ok and vim.log.levels.INFO or vim.log.levels.WARN)
  end, { force = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].buftype ~= '' then return end
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path == '' or vim.fn.filereadable(path) ~= 1 then return end
      local root = root_for(path)
      if path:sub(1, #root + 1) ~= root .. '/' then return end
      local recent = { path }
      for _, p in ipairs(type(state.get(root).recents) == 'table' and state.get(root).recents or {}) do
        if type(p) == 'string' and p ~= path and #recent < 30 then recent[#recent + 1] = p end
      end
      state.update(root, 'recents', recent)
    end,
  })
  vim.api.nvim_create_autocmd({ 'TabLeave', 'VimLeavePre' }, { group = group, callback = function() save_session(root_for(vim.fn.getcwd())) end })
  local stdin = false
  vim.api.nvim_create_autocmd('StdinReadPre', { group = group, callback = function() stdin = true end })
  local function startup()
    if not M.options.startup or stdin or vim.v.this_session ~= '' then return end
    for _, arg in ipairs(vim.v.argv) do
      if arg == '-' or arg == '-S' or arg:match '^%-S.' then return end
    end
    -- Explicit paths belong to the directory/file handler (Oil in this config).
    if vim.fn.argc() > 0 or not empty_buffer(vim.api.nvim_get_current_buf()) then return end
    M.open(nil, { root = vim.fn.getcwd(), reuse = true })
  end
  if vim.v.vim_did_enter == 1 then
    vim.schedule(startup)
  else
    vim.api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = function() vim.schedule(startup) end })
  end
end
return M
