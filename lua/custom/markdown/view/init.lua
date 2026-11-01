local M = {}
local api = vim.api
local root = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local ns = api.nvim_create_namespace 'markdown-rich-view'
local canvas = require 'custom.markdown.view.canvas'
local theme = require 'custom.markdown.view.theme'
local actions = { 'continuous', 'paged', 'zoom', 'close', 'refresh', 'status', 'check' }
local closing = {}

local function notify(message, level) vim.notify('Markdown view: ' .. message, level or vim.log.levels.INFO) end

local function background(palette) api.nvim_set_hl(0, 'MarkdownViewNormal', { fg = palette.foreground, bg = palette.background }) end

local function executable(name)
  local path = vim.fn.exepath(name)
  if path ~= '' then return path end
  path = vim.fs.joinpath(vim.fn.stdpath 'data', 'markdown-view', 'bin', name)
  return vim.fn.executable(path) == 1 and path or nil
end

function M.dependencies()
  local deps = { python = require('custom.python.host').executable 'python', pandoc = executable 'pandoc', typst = executable 'typst', errors = {} }
  if vim.fn.executable(deps.python) ~= 1 then deps.errors[#deps.errors + 1] = 'Neovim Python host is missing; run scripts/setup-python.sh.' end
  for _, name in ipairs { 'pandoc', 'typst' } do
    if not deps[name] then deps.errors[#deps.errors + 1] = name .. ' is missing; run scripts/setup-markdown-view.sh or add it to PATH.' end
  end
  return deps
end

local function valid(s)
  return M.session == s
    and not s.closed
    and api.nvim_buf_is_valid(s.source)
    and api.nvim_buf_is_valid(s.buf)
    and api.nvim_win_is_valid(s.source_win)
    and api.nvim_win_is_valid(s.win)
    and api.nvim_win_get_buf(s.source_win) == s.source
    and api.nvim_win_get_buf(s.win) == s.buf
    and api.nvim_win_get_tabpage(s.source_win) == s.tab
    and api.nvim_win_get_tabpage(s.win) == s.tab
end

local function active(s)
  local win = api.nvim_get_current_win()
  return valid(s) and (win == s.source_win or win == s.win)
end

local function view(win)
  return api.nvim_win_call(win, function()
    local current = vim.fn.winsaveview()
    current.height = api.nvim_win_get_height(win)
    current.winline = vim.fn.winline()
    return current
  end)
end

local function remember(s, win) s.views[win] = view(win) end

local function setview(s, win, row, top)
  local count = api.nvim_buf_line_count(api.nvim_win_get_buf(win))
  row, top = math.max(1, math.min(count, row)), math.max(1, math.min(count, top))
  s.syncing = true
  local ok, err = pcall(api.nvim_win_call, win, function()
    api.nvim_win_set_cursor(win, { row, 0 })
    vim.fn.winrestview { lnum = row, col = 0, topline = top, leftcol = 0, skipcol = 0 }
  end)
  s.syncing = false
  if not ok then error(err) end
  remember(s, win)
end

local function interpolate(points, value, key, target)
  local a, b = points[1], points[#points]
  if not a then return 1 end
  if value <= a[key] then return a[target] end
  if value >= b[key] then return b[target] end
  for i = 1, #points - 1 do
    a, b = points[i], points[i + 1]
    if a[key] <= value and value < b[key] then
      return math.floor(a[target] + (value - a[key]) / math.max(1, b[key] - a[key]) * (b[target] - a[target]) + 0.5)
    end
  end
  return b[target]
end

local function forward(s, row) return interpolate(s.forward, row, 'source', 'row') end
local function backward(s, row) return interpolate(s.backward, row, 'row', 'source') end

local function title(s)
  if not api.nvim_win_is_valid(s.win) then return end
  local phase = s.error and ('Error: ' .. s.error:gsub('[\r\n].*', '')) or s.phase
  vim.wo[s.win].winbar = (' Rich reading · %s · %s  |  m mode · z maximize · Enter source · q close'):format(s.mode, phase:gsub('%%', '%%%%'))
end

function M.sync(kind)
  local s = M.session
  if not s or not active(s) or s.syncing or not s.manifest then return end
  if s.manifest.tick ~= api.nvim_buf_get_changedtick(s.source) then return end
  local win = api.nvim_get_current_win()
  local current, previous = view(win), s.views[win]
  if previous and previous.lnum == current.lnum and previous.col == current.col and previous.topline == current.topline then return end
  s.views[win] = current
  local target = win == s.win and s.source_win or s.win
  local row = win == s.win and backward(s, current.lnum) or forward(s, current.lnum)
  local top
  if kind == 'scroll' then
    top = win == s.win and backward(s, current.topline) or forward(s, current.topline)
  else
    local fraction = (current.winline - 1) / math.max(1, current.height - 1)
    top = row - math.floor(fraction * math.max(1, api.nvim_win_get_height(target) - 1))
  end
  s.anchor = win == s.win and backward(s, current.lnum) or current.lnum
  setview(s, target, row, top)
  s.sync_count = s.sync_count + 1
end

-- A generation remains pinned while its PNG files are displayed or its worker
-- is running. Process completion, rather than a timer, permits directory removal.
local function prune(s)
  for version, task in pairs(s.tasks) do
    if task.finished and task ~= s.frame_task and task ~= s.task then
      vim.fn.delete(task.folder, 'rf')
      s.tasks[version] = nil
    end
  end
  if s.closed and not next(s.tasks) then
    vim.fn.delete(s.tmp, 'rf')
    closing[s] = nil
  end
end

local function cancel(task)
  if not task or task.finished or task.cancelled then return end
  task.cancelled = true
  task.job:kill(15)
  vim.defer_fn(function()
    if not task.finished then task.job:kill(9) end
  end, 1000)
end

local function failed(s, task, message)
  s.task = nil
  s.failed, s.error, s.phase = true, message, 'failed'
  prune(s)
  title(s)
  notify(message:gsub('[\r\n].*', '') .. ' (:MarkdownView status for details)', vim.log.levels.WARN)
end

local function publish(s, task, result)
  if not valid(s) or task ~= s.task or task.cancelled or task.theme_epoch ~= s.theme_epoch then return prune(s) end
  if result.tick ~= api.nvim_buf_get_changedtick(s.source) then
    s.task, s.signature = nil, nil
    prune(s)
    return M.request()
  end
  local ok, frame = pcall(canvas.prepare, s.buf, result)
  if not ok then return failed(s, task, tostring(frame)) end
  if not valid(s) or task ~= s.task or task.theme_epoch ~= s.theme_epoch or result.tick ~= api.nvim_buf_get_changedtick(s.source) then
    canvas.dispose(frame)
    if s.task == task then
      s.task, s.signature = nil, nil
    end
    prune(s)
    return M.request()
  end
  local old, anchor = s.frame, s.anchor or api.nvim_win_get_cursor(s.source_win)[1]
  -- Colors do not change document geometry. Capture the latest viewport here,
  -- after worker completion, so navigation during rendering/picker preview is
  -- preserved exactly instead of restoring an earlier source-block anchor.
  local same_geometry = s.frame_task and s.frame_task.geometry == task.geometry
  local latest_view = same_geometry and view(s.win) or nil
  s.syncing = true
  ok, frame.error = pcall(canvas.publish, s.buf, ns, frame)
  s.syncing = false
  if not ok then
    canvas.dispose(frame)
    return failed(s, task, tostring(frame.error))
  end
  s.manifest, s.frame, s.frame_task, s.task = result, frame, task, nil
  s.frame_palette, s.frame_palette_hash = task.palette, task.palette_hash
  background(s.frame_palette)
  s.forward, s.backward = vim.deepcopy(result.points), vim.deepcopy(result.points)
  table.sort(s.forward, function(a, b) return a.source == b.source and a.col < b.col or a.source < b.source end)
  table.sort(s.backward, function(a, b) return a.row == b.row and a.source < b.source or a.row < b.row end)
  s.phase, s.error, s.ready = #(result.warnings or {}) > 0 and 'ready (warnings)' or 'ready', nil, true
  if latest_view then
    s.syncing = true
    api.nvim_win_call(s.win, function() vim.fn.winrestview(latest_view) end)
    s.syncing = false
  elseif api.nvim_get_current_win() == s.source_win then
    local current = view(s.source_win)
    setview(s, s.win, forward(s, current.lnum), forward(s, current.topline))
  else
    local row = forward(s, anchor)
    setview(s, s.win, row, math.max(1, row - 3))
  end
  remember(s, s.source_win)
  remember(s, s.win)
  canvas.dispose(old)
  prune(s)
  title(s)
end

function M.render()
  local s = M.session
  if not s or not valid(s) or s.theme_pending or api.nvim_get_current_tabpage() ~= s.tab then return end
  local width = api.nvim_win_get_width(s.win)
  if width < 24 then
    s.phase = 'hidden'
    return title(s)
  end
  local size = canvas.size()
  local cw, ch =
    math.max(1, math.floor(size.cell_width > 0 and size.cell_width or 10)), math.max(1, math.floor(size.cell_height > 0 and size.cell_height or 20))
  local cols = math.max(20, math.min(180, width - 2))
  local tick = api.nvim_buf_get_changedtick(s.source)
  local origin = api.nvim_buf_get_name(s.source)
  if origin == '' then origin = vim.fs.joinpath(api.nvim_win_call(s.source_win, vim.fn.getcwd), 'untitled.md') end
  local geometry = table.concat({ tick, s.mode, cols, cw, ch, origin }, ':')
  local signature = geometry .. ':' .. s.palette_hash
  if signature == s.signature and (s.task or s.ready or s.failed) then
    if s.phase == 'hidden' then
      s.phase = s.error and 'failed' or (s.ready and 'ready' or 'rendering')
      title(s)
    end
    return
  end
  s.signature, s.version = signature, s.version + 1
  cancel(s.task)
  s.task = nil
  prune(s)
  s.phase, s.error, s.ready, s.failed = 'rendering', nil, false, false
  title(s)
  local task = {
    version = s.version,
    folder = vim.fs.joinpath(s.tmp, tostring(s.version)),
    geometry = geometry,
    theme_epoch = s.theme_epoch,
    palette = vim.deepcopy(s.palette),
    palette_hash = s.palette_hash,
  }
  s.task, s.tasks[task.version] = task, task
  vim.fn.mkdir(task.folder, 'p')
  local path = vim.fs.joinpath(task.folder, 'request.json')
  local request = {
    output = task.folder,
    origin = origin,
    text = table.concat(api.nvim_buf_get_lines(s.source, 0, -1, false), '\n') .. '\n',
    mode = s.mode,
    columns = cols,
    cell_width = cw,
    cell_height = ch,
    pandoc = s.dependencies.pandoc,
    typst = s.dependencies.typst,
    palette = task.palette,
  }
  vim.fn.writefile({ vim.json.encode(request) }, path)
  local ok, job = pcall(vim.system, { s.dependencies.python, root .. '/render.py', path }, { text = true, timeout = 25000 }, function(result)
    task.finished = true
    vim.schedule(function()
      if not valid(s) or task.cancelled or s.task ~= task or task.theme_epoch ~= s.theme_epoch then return prune(s) end
      if api.nvim_buf_get_changedtick(s.source) ~= tick then
        s.task, s.signature = nil, nil
        prune(s)
        return M.request()
      end
      local decoded, data = pcall(vim.json.decode, result.stdout or '')
      if not decoded or type(data) ~= 'table' or result.code ~= 0 or data.error then
        local message = decoded and type(data) == 'table' and data.error or nil
        return failed(s, task, message or (result.stderr ~= '' and result.stderr) or 'Renderer failed')
      end
      data.tick = tick
      publish(s, task, data)
    end)
  end)
  if ok then
    task.job = job
  else
    task.finished = true
    failed(s, task, tostring(job))
  end
end

function M.request()
  local s = M.session
  if not s or not valid(s) then return end
  if s.manifest and s.manifest.tick ~= api.nvim_buf_get_changedtick(s.source) then
    s.ready, s.phase = false, 'updating'
    title(s)
  end
  s.request = s.request + 1
  local request = s.request
  vim.defer_fn(function()
    if valid(s) and request == s.request then M.render() end
  end, 150)
end

function M.mode(mode)
  local s = M.session
  if not s or not active(s) then return notify 'Open the rich view for this note first.' end
  s.anchor = api.nvim_get_current_win() == s.win and s.manifest and backward(s, api.nvim_win_get_cursor(s.win)[1]) or api.nvim_win_get_cursor(s.source_win)[1]
  s.mode, s.signature = mode or (s.mode == 'continuous' and 'paged' or 'continuous'), nil
  M.render()
end

function M.zoom()
  local s = M.session
  if not s or not active(s) then return notify 'Focus the source or rich reading pane first.' end
  if s.restore then
    vim.cmd(s.restore)
    s.restore = nil
  else
    s.restore = vim.fn.winrestcmd()
    vim.cmd 'wincmd |'
    vim.cmd 'wincmd _'
  end
  M.request()
end

function M.close()
  local s = M.session
  if not s then return end
  local return_to_source = api.nvim_get_current_win() == s.win
  s.closed, M.session, closing[s] = true, nil, true
  pcall(api.nvim_del_augroup_by_id, s.group)
  for _, task in pairs(s.tasks) do
    cancel(task)
  end
  s.task, s.frame_task = nil, nil
  canvas.dispose(s.frame)
  if s.restore and api.nvim_win_is_valid(s.source_win) then pcall(api.nvim_win_call, s.source_win, function() vim.cmd(s.restore) end) end
  if api.nvim_win_is_valid(s.win) then pcall(api.nvim_win_close, s.win, true) end
  if api.nvim_buf_is_valid(s.buf) then pcall(api.nvim_buf_delete, s.buf, { force = true }) end
  if return_to_source and api.nvim_win_is_valid(s.source_win) then api.nvim_set_current_win(s.source_win) end
  prune(s)
end

function M.source()
  local s = M.session
  if not s or not valid(s) then return end
  M.sync 'cursor'
  api.nvim_set_current_win(s.source_win)
end

local function theme_changed(s)
  if not valid(s) then return end
  -- Invalidate synchronously: even a completed worker whose scheduled callback
  -- runs before deferred palette capture must not publish an obsolete theme.
  s.theme_epoch, s.theme_pending = s.theme_epoch + 1, true
  s.ready, s.error, s.phase = false, nil, 'styling'
  cancel(s.task)
  s.task = nil
  prune(s)
  background(s.frame_palette or s.palette)
  title(s)
  local epoch = s.theme_epoch
  vim.schedule(function()
    if not valid(s) or epoch ~= s.theme_epoch then return end
    -- Other ColorScheme handlers may resolve custom semantic highlights. Keep
    -- displaying the old coherent page/background until its replacement exists.
    background(s.frame_palette or s.palette)
    s.palette = theme.capture(s.source_win)
    s.palette_hash = theme.fingerprint(s.palette)
    s.theme_pending, s.signature = false, nil
    M.request()
  end)
end

local function map_toggle(buf) vim.keymap.set('n', '<leader>Tv', M.toggle, { buffer = buf, silent = true, desc = '[T]oggle rich Markdown [v]iew' }) end

function M.open(mode)
  if vim.bo.filetype ~= 'markdown' then return notify 'Open a Markdown source buffer first.' end
  local dependencies = M.dependencies()
  if #dependencies.errors > 0 then return notify(table.concat(dependencies.errors, '\n'), vim.log.levels.WARN) end
  local snacks, err = canvas.check()
  if not snacks then return notify(err, vim.log.levels.WARN) end
  M.close()
  local palette = theme.capture()
  local source, source_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  vim.cmd 'botright vsplit'
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)
  api.nvim_buf_set_name(buf, 'markdown-view://' .. source)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
  vim.bo[buf].filetype, vim.bo[buf].modifiable = 'markdown-view', false
  for key, value in pairs {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    foldenable = false,
    cursorline = false,
    cursorcolumn = false,
    scrolloff = 0,
    sidescrolloff = 0,
    list = false,
    spell = false,
    winfixbuf = true,
  } do
    vim.wo[win][key] = value
  end
  background(palette)
  vim.wo[win].winhighlight = 'Normal:MarkdownViewNormal,NormalNC:MarkdownViewNormal,EndOfBuffer:MarkdownViewNormal'
  vim.wo[win].fillchars = 'eob: '
  local s = {
    source = source,
    source_win = source_win,
    buf = buf,
    win = win,
    tab = api.nvim_get_current_tabpage(),
    mode = mode or 'continuous',
    version = 0,
    request = 0,
    views = {},
    tasks = {},
    sync_count = 0,
    tmp = vim.fn.tempname() .. '-markdown-view',
    dependencies = dependencies,
    phase = 'starting',
    palette = palette,
    palette_hash = theme.fingerprint(palette),
    theme_epoch = 0,
  }
  s.group = api.nvim_create_augroup('markdown-rich-view-session', { clear = true })
  M.session = s
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = s.group,
    callback = function(event)
      if event.buf == s.source or event.buf == s.buf then M.sync 'cursor' end
    end,
  })
  api.nvim_create_autocmd('WinScrolled', {
    group = s.group,
    callback = function()
      if vim.v.event[tostring(api.nvim_get_current_win())] then M.sync 'scroll' end
    end,
  })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave', 'BufFilePost' }, { group = s.group, buffer = source, callback = M.request })
  api.nvim_create_autocmd({ 'WinResized', 'WinEnter', 'TabEnter' }, {
    group = s.group,
    callback = function()
      if valid(s) then M.request() end
    end,
  })
  api.nvim_create_autocmd('WinClosed', {
    group = s.group,
    callback = function(event)
      if tonumber(event.match) == s.win or tonumber(event.match) == s.source_win then
        vim.schedule(function()
          if M.session == s then M.close() end
        end)
      end
    end,
  })
  for _, watched in ipairs { source, buf } do
    api.nvim_create_autocmd('BufWinLeave', {
      group = s.group,
      buffer = watched,
      callback = function()
        vim.schedule(function()
          if M.session == s and not valid(s) then M.close() end
        end)
      end,
    })
    api.nvim_create_autocmd({ 'BufWipeout', 'BufUnload' }, { group = s.group, buffer = watched, callback = M.close })
  end
  api.nvim_create_autocmd('ColorScheme', { group = s.group, callback = function() theme_changed(s) end })
  map_toggle(buf)
  for key, action in pairs {
    m = function() M.mode() end,
    z = M.zoom,
    q = M.close,
    ['<CR>'] = M.source,
    ['<Tab>'] = M.source,
    r = M.refresh,
  } do
    vim.keymap.set('n', key, action, { buffer = buf, silent = true })
  end
  for _, key in ipairs { 'i', 'I', 'a', 'A', 'o', 'O', 'R' } do
    vim.keymap.set('n', key, M.source, { buffer = buf, silent = true, desc = 'Edit in the source pane' })
  end
  remember(s, source_win)
  remember(s, win)
  M.render()
  api.nvim_set_current_win(source_win)
end

function M.toggle()
  if M.session and active(M.session) then return M.close() end
  M.open()
end

function M.refresh()
  local s = M.session
  if not s or not active(s) then return notify 'Focus the source or rich reading pane first.' end
  if not s.theme_pending then
    s.palette = theme.capture(s.source_win)
    s.palette_hash = theme.fingerprint(s.palette)
  end
  s.signature = nil
  M.render()
end

function M.status()
  local s = M.session
  if not s then return { phase = 'closed' } end
  return {
    phase = s.phase,
    error = s.error,
    mode = s.mode,
    version = s.version,
    source = s.source,
    source_win = s.source_win,
    buf = s.buf,
    win = s.win,
    tmp = s.tmp,
    tick = api.nvim_buf_is_valid(s.source) and api.nvim_buf_get_changedtick(s.source) or nil,
    manifest_tick = s.manifest and s.manifest.tick,
    render_ms = s.manifest and s.manifest.render_ms,
    warnings = s.manifest and s.manifest.warnings,
    sync_count = s.sync_count,
    theme_epoch = s.theme_epoch,
    palette_hash = s.palette_hash,
    frame_palette_hash = s.frame_palette_hash,
    theme_pending = s.theme_pending,
  }
end

function M.setup()
  local group = api.nvim_create_augroup('markdown-rich-view', { clear = true })
  api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      M.close()
      -- Closed sessions can still be reaping cancelled workers. At shutdown,
      -- scheduled exit callbacks may never run, so wait before deleting files.
      for s in pairs(closing) do
        for _, task in pairs(s.tasks) do
          if not task.finished then task.finished = task.job:wait(1000) ~= nil end
        end
        prune(s)
      end
    end,
  })
  api.nvim_create_autocmd('FileType', { group = group, pattern = 'markdown', callback = function(event) map_toggle(event.buf) end })
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == 'markdown' then map_toggle(buf) end
  end
  api.nvim_create_user_command('MarkdownView', function(args)
    local action = args.args
    if action == '' then
      M.toggle()
    elseif action == 'continuous' or action == 'paged' then
      if M.session and active(M.session) then
        M.mode(action)
      else
        M.open(action)
      end
    elseif action == 'check' then
      local deps = M.dependencies()
      local _, issue = canvas.check()
      if issue then deps.errors[#deps.errors + 1] = issue end
      notify(vim.inspect(deps), #deps.errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
    elseif action == 'status' then
      notify(vim.inspect(M.status()))
    elseif M[action] and vim.tbl_contains(actions, action) then
      M[action]()
    else
      notify('Use :MarkdownView [' .. table.concat(actions, '|') .. '].', vim.log.levels.WARN)
    end
  end, {
    nargs = '?',
    force = true,
    desc = 'Toggle a synchronized rich Markdown reading pane',
    complete = function(prefix)
      return vim.tbl_filter(function(action) return action:sub(1, #prefix) == prefix end, actions)
    end,
  })
end

return M
