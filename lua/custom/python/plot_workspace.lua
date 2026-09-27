local M = {}
local api = vim.api
local active
local folders = {}
local ns = api.nvim_create_namespace 'python-plot-ui'
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('python-plot-files', { clear = true }),
  callback = function()
    for _, folder in ipairs(folders) do
      vim.fn.delete(folder, 'rf')
    end
  end,
})
local function geometry()
  local w, h = math.max(1, math.min(100, vim.o.columns - 6)), math.max(1, math.min(29, vim.o.lines - 6))
  return {
    relative = 'editor',
    width = w,
    height = h,
    row = math.max(0, math.floor((vim.o.lines - h) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - w) / 2)),
    border = 'rounded',
    style = 'minimal',
    title = ' Plot setup ',
    title_pos = 'center',
    footer = w < 85 and ' Enter draw · v view · b browser · e export · ? · q '
      or ' Enter draw · v preview · b browser · e export · ? help · q close ',
    footer_pos = 'center',
  }
end
function M.open(opts)
  if active and api.nvim_win_is_valid(active.win) then api.nvim_win_close(active.win, true) end
  local return_win = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local s = {
    buf = buf,
    win = api.nvim_open_win(buf, true, geometry()),
    serial = 0,
    dirty = true,
    settings = {
      style = 'line',
      x = -1,
      ys = {},
      start = 0,
      limit = 5000,
      bins = 30,
      title = opts.name,
      xlabel = '',
      ylabel = '',
      legend = true,
      slice = opts.slice,
    },
  }
  active = s
  vim.bo[buf].bufhidden, vim.bo[buf].buftype, vim.bo[buf].filetype = 'wipe', 'nofile', 'molten-plot'
  vim.wo[s.win].wrap, vim.wo[s.win].list, vim.wo[s.win].cursorline = true, false, false
  vim.wo[s.win].fillchars = 'eob: '
  vim.wo[s.win].linebreak = true
  local draw, schema, render
  local function column(id)
    if id == -1 then return 'Row position' end
    for _, c in ipairs(s.schema and s.schema.columns or {}) do
      if c.id == id then return c.label:gsub('%c', ' ') .. ' [' .. id .. ']' end
    end
    return '[' .. id .. '] unavailable'
  end
  local function write(lines)
    lines = vim.tbl_map(function(line) return line:gsub('%c', ' ') end, lines)
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, line in ipairs(lines) do
      local group = i == 1 and 'Title'
        or (s.error and line == ' ' .. s.error:gsub('%c', ' ') and 'DiagnosticWarn')
        or (line:match '^  [a-zA-Z?]  ' and 'Special' or 'NormalFloat')
      api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #line, hl_group = group })
    end
  end
  render = function()
    if active ~= s then return end
    api.nvim_win_set_config(s.win, { footer = s.help and ' ? / q back · j/k scroll ' or geometry().footer })
    if s.help then
      return write {
        ' PLOT WORKSPACE',
        '',
        ' t type · x X column · y Y columns (toggle choices, then Done)',
        ' r row range [start, stop) · s point/cell budget · n histogram bins',
        ' l title/axis labels · a toggle legend · R reload schema',
        ' Enter draws a new snapshot using the visible settings.',
        ' v opens its PNG with zoom/pan/fit · q returns here.',
        ' b opens a self-contained interactive HTML chart in your browser.',
        ' e exports PNG, SVG, HTML or JSON (existing files are not overwritten).',
        '',
        ' All column IDs and row positions are zero-based. Stop is exclusive.',
        ' Source is the whole variable or tensor slice, independent of table pages.',
        ' Explorer table sorting/filtering and custom renderers are not applied.',
        ' Lines preserve source row order, including nonmonotonic X.',
        ' Uniform sampling includes range endpoints but can miss narrow spikes.',
        ' Histograms use every selected value (100,000-value safety limit).',
        ' Heatmaps sample rows; selected columns are retained. No averaging.',
        ' Missing/nonfinite values are reported; lines break at missing sampled values.',
        ' Data stays local. HTML embeds its data and JS; no CDN is needed.',
        ' Rendering runs in the editor host. GPU transfers are bounded before copying.',
        '',
        ' ? / q returns to settings',
      }
    end
    local c = s.settings
    local ys = vim.tbl_map(column, c.ys)
    write {
      ' ' .. opts.name .. ' · plot workspace',
      ' ' .. (s.schema and (s.schema.rows .. ' rows · ' .. s.schema.column_count .. ' columns · original variable/slice') or 'Loading schema…'),
      ' Table pages, filters and sorting do not limit this source.',
      '',
      '  t  Type          ' .. c.style,
      '  x  X             ' .. ((c.style == 'histogram' or c.style == 'heatmap') and '(not used for this type)' or column(c.x)),
      (c.style == 'heatmap' and '  y  Columns       ' or c.style == 'histogram' and '  y  Series        ' or '  y  Y columns     ')
        .. (#ys > 0 and table.concat(ys, ', ') or 'Choose numeric columns'),
      '  r  Row range     [' .. c.start .. ', ' .. tostring(c.stop or 'end') .. ')  · stop exclusive',
      '  s  Budget        '
        .. (
          c.style == 'histogram' and 'Exact · all selected values (100,000 maximum)' or (c.limit .. (c.style == 'heatmap' and ' cells' or ' rows per series'))
        ),
      '  n  Histogram     ' .. (c.style == 'histogram' and (c.bins .. ' bins') or '(not used for this type)'),
      '  l  Title         ' .. c.title,
      '     Axis labels   ' .. (c.xlabel == '' and 'automatic' or c.xlabel) .. ' / ' .. (c.ylabel == '' and 'automatic' or c.ylabel),
      '  a  Legend        ' .. (c.legend and 'shown' or 'hidden'),
      '',
      ' '
        .. (
          s.message
          or (
            s.error and 'Correct settings or reload schema with R; Enter retries'
            or s.dirty and 'Settings ready · Enter to draw'
            or 'Snapshot ready · v preview · b interactive browser · e export'
          )
        ),
      ' ' .. (s.caption or ''),
      ' ' .. (s.error or ''),
      '',
      ' Enter draws · R reloads schema · ? explains sampling and controls',
    }
    vim.b[buf].plot_settings = c
  end
  local function change()
    s.serial = s.serial + 1
    if s.job then
      s.job:kill(15)
      s.job = nil
    end
    s.dirty, s.error, s.message = true, nil, nil
    s.caption = nil
    vim.b[buf].plot_snapshot = nil
    render()
  end
  local function query(action, done)
    s.serial = s.serial + 1
    local serial = s.serial
    if s.job then s.job:kill(15) end
    local conn, err = opts.connection()
    if not conn then
      s.error = err
      s.message = nil
      render()
      return
    end
    s.message, s.error = 'Reading kernel…', nil
    render()
    s.job = vim.system(
      {
        opts.python,
        opts.helper,
        conn.path,
        conn.generation,
        vim.json.encode { name = opts.name, path = opts.path, action = action, plot_options = s.settings },
      },
      { text = true, timeout = 6500 },
      vim.schedule_wrap(function(result)
        if active ~= s or serial ~= s.serial then return end
        s.job = nil
        local current, reason = opts.connection()
        local ok, reply = pcall(vim.json.decode, result.stdout or '')
        s.message = nil
        if not current or current.generation ~= conn.generation then
          s.error = reason or 'Kernel restarted; reload schema with R'
        elseif result.code ~= 0 or not ok then
          s.error = 'Kernel request timed out; retry when idle'
        elseif not reply.ok or reply.data.error then
          s.error = reply.error or reply.data.error
        else
          return done(reply.data, serial, conn)
        end
        render()
      end)
    )
  end
  schema = function()
    s.dirty = true
    vim.b[buf].plot_snapshot = nil
    query('plot_schema', function(data)
      local old = s.schema
      s.schema = data.plot
      if s.settings.stop == nil or (old and s.settings.stop == old.rows) then s.settings.stop = data.plot.rows end
      if #s.settings.ys == 0 then
        for _, c in ipairs(data.plot.columns) do
          if c.numeric then
            s.settings.ys = { c.id }
            break
          end
        end
      end
      s.dirty = true
      s.message = data.plot.column_count > 512 and 'Only the first 512 columns are offered; select a narrower variable in Python for others.' or nil
      render()
      vim.b[buf].plot_schema = data.plot
    end)
  end
  draw = function()
    if not s.schema then return schema() end
    s.dirty = true
    vim.b[buf].plot_snapshot = nil
    query('plot_data', function(data, serial, conn)
      s.message, s.caption = 'Rendering chart in editor host…', data.plot.caption
      render()
      local folder = vim.fn.tempname() .. '-plot'
      vim.fn.mkdir(folder, 'p', 448)
      folders[#folders + 1] = folder
      if #folders > 8 then vim.fn.delete(table.remove(folders, 1), 'rf') end
      local input = folder .. '/input.json'
      vim.fn.writefile({ vim.json.encode { data = data.plot, settings = s.settings } }, input)
      s.job = vim.system(
        { opts.python, vim.fs.dirname(opts.helper) .. '/render-plot.py', input, folder },
        { text = true, timeout = 30000 },
        vim.schedule_wrap(function(result)
          if active ~= s or serial ~= s.serial then return end
          s.job = nil
          local current = opts.connection()
          local ok, reply = pcall(vim.json.decode, result.stdout or '')
          s.message = nil
          if not current or current.generation ~= conn.generation then
            s.error = 'Kernel changed during rendering; draw a fresh snapshot'
          elseif result.code ~= 0 or not ok or not reply.ok then
            s.error = 'Renderer: ' .. (ok and reply.error or ('exit ' .. tostring(result.code) .. ': ' .. (result.stderr or ''):sub(1, 800)))
          else
            s.files, s.dirty, s.error = reply.files, false, nil
            vim.b[buf].plot_snapshot = { files = reply.files, caption = data.plot.caption, settings = vim.deepcopy(s.settings) }
          end
          render()
        end)
      )
    end)
  end
  local function map(key, fn, desc) vim.keymap.set('n', key, fn, { buffer = buf, silent = true, desc = desc }) end
  local function close()
    if s.help then
      s.help = false
      render()
      return
    end
    api.nvim_win_close(s.win, true)
    if api.nvim_win_is_valid(return_win) then api.nvim_set_current_win(return_win) end
  end
  map('q', close, 'Back / close plot setup')
  map('<Esc>', close, 'Back / close plot setup')
  map('?', function()
    s.help = not s.help
    render()
  end, 'Plot help')
  map('<CR>', draw, 'Draw configured plot')
  map('R', schema, 'Reload source schema')
  local function input(prompt, default, cb)
    vim.ui.input({ prompt = prompt, default = default }, function(value)
      if active == s and value ~= nil then cb(value) end
    end)
  end
  map('t', function()
    vim.ui.select({ 'line', 'scatter', 'histogram', 'heatmap' }, { prompt = 'Plot type' }, function(v)
      if active == s and v then
        s.settings.style = v
        change()
      end
    end)
  end, 'Choose plot type')
  map('x', function()
    if s.settings.style == 'histogram' or s.settings.style == 'heatmap' then return vim.notify 'This chart type does not use an X column' end
    if not s.schema then return end
    local choices = { -1 }
    for _, c in ipairs(s.schema.columns) do
      if c.numeric then choices[#choices + 1] = c.id end
    end
    vim.ui.select(choices, { prompt = 'X axis', format_item = column }, function(v)
      if active == s and v ~= nil then
        s.settings.x = v
        change()
      end
    end)
  end, 'Choose X column')
  local function select_y()
    if not s.schema then return end
    local choices = { -1 }
    for _, c in ipairs(s.schema.columns) do
      if c.numeric then choices[#choices + 1] = c.id end
    end
    vim.ui.select(choices, {
      prompt = 'Y columns · toggle selections, then Done',
      format_item = function(v) return v == -1 and 'Done' or ((vim.tbl_contains(s.settings.ys, v) and '[✓] ' or '[ ] ') .. column(v)) end,
    }, function(v)
      if active ~= s or v == nil or v == -1 then return end
      if vim.tbl_contains(s.settings.ys, v) then
        s.settings.ys = vim.tbl_filter(function(id) return id ~= v end, s.settings.ys)
      else
        s.settings.ys[#s.settings.ys + 1] = v
      end
      change()
      vim.schedule(select_y)
    end)
  end
  map('y', select_y, 'Choose Y columns')
  map('r', function()
    input('Row range: start, stop (zero-based, stop exclusive): ', s.settings.start .. ', ' .. tostring(s.settings.stop or ''), function(v)
      local a, b = v:match '^%s*(%d+)%s*,%s*(%d+)%s*$'
      if not a then return vim.notify('Enter start, stop; e.g. 0, 100', vim.log.levels.WARN) end
      s.settings.start, s.settings.stop = tonumber(a), tonumber(b)
      change()
    end)
  end, 'Select row range')
  for key, field in pairs { s = 'limit', n = 'bins' } do
    map(key, function()
      if field == 'limit' and s.settings.style == 'histogram' then return vim.notify 'Histograms use every selected value; r changes the row range' end
      if field == 'bins' and s.settings.style ~= 'histogram' then return vim.notify 'Bin count applies to histograms; t changes chart type' end
      input(field == 'limit' and 'Point/cell budget (10–20000): ' or 'Histogram bins (2–200): ', tostring(s.settings[field]), function(v)
        local number = tonumber(v)
        if not number or number % 1 ~= 0 then return vim.notify('Enter a whole number', vim.log.levels.WARN) end
        s.settings[field] = number
        change()
      end)
    end, 'Set ' .. field)
  end
  map('a', function()
    s.settings.legend = not s.settings.legend
    change()
  end, 'Toggle legend')
  map('l', function()
    input('Plot title: ', s.settings.title, function(v)
      s.settings.title = v
      change()
      input('X label (blank = automatic): ', s.settings.xlabel, function(x)
        s.settings.xlabel = x
        change()
        input('Y label (blank = automatic): ', s.settings.ylabel, function(y)
          s.settings.ylabel = y
          change()
        end)
      end)
    end)
  end, 'Set title and axis labels')
  local function ready()
    if s.dirty or not s.files then
      vim.notify 'Press Enter to draw the current settings first'
      return false
    end
    return true
  end
  map('v', function()
    if ready() then
      require('custom.python.image_viewer').open {
        file = s.files.png,
        svg = s.files.svg,
        name = s.settings.title,
        python = opts.python,
        helper = opts.helper,
        poll = opts.poll,
      }
    end
  end, 'Preview with zoom/pan/fit')
  map('b', function()
    if ready() then vim.ui.open(s.files.html) end
  end, 'Open interactive local chart')
  map('e', function()
    if not ready() then return end
    local files = vim.deepcopy(s.files)
    input('Export path (.png, .svg, .html, .json): ', '', function(value)
      local path = vim.fn.fnamemodify(vim.fn.expand(value), ':p')
      local ext = path:match '%.([a-z]+)$'
      if not files[ext] then return vim.notify('Choose .png, .svg, .html or .json', vim.log.levels.WARN) end
      local ok, err = vim.uv.fs_copyfile(files[ext], path, { excl = true })
      vim.notify(
        ok and ('Exported ' .. path) or ('Export failed (existing files are preserved): ' .. tostring(err)),
        ok and vim.log.levels.INFO or vim.log.levels.ERROR
      )
    end)
  end, 'Export chart snapshot')
  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if s.job then s.job:kill(15) end
      s.serial = s.serial + 1
      if active == s then active = nil end
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = api.nvim_create_augroup('python-plot-resize', { clear = true }),
    callback = function()
      if active == s and api.nvim_win_is_valid(s.win) then
        api.nvim_win_set_config(s.win, geometry())
        render()
      end
    end,
  })
  local function poll()
    if active ~= s then return end
    if opts.poll then opts.poll() end
    vim.defer_fn(poll, 200)
  end
  vim.defer_fn(poll, 200)
  schema()
end
return M
