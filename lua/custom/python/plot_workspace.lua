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
function M.open(opts)
  if active and api.nvim_win_is_valid(active.win) then api.nvim_win_close(active.win, true) end
  local s = {
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
  local surface = require('custom.python.image_viewer').open {
    managed = true,
    name = opts.name,
    python = opts.python,
    helper = opts.helper,
    poll = opts.poll,
    footer = function()
      return vim.o.columns < 100 and ' +/- zoom · 0 fit · s settings · ? · q '
        or ' +/- zoom · hjkl pan · 0 fit · t type · x/y axes · s settings · ? help · q '
    end,
    chrome = function(view)
      local shown = s.snapshot and s.snapshot.settings or s.settings
      local state = s.error and ('Failed · ' .. (s.snapshot and 'previous chart shown · ' or '') .. s.error)
        or s.message and (s.message .. (s.snapshot and ' · previous chart shown' or ''))
        or s.dirty and 'Updating…'
        or 'Ready · r refresh · b browser · e export'
      local labels = s.snapshot and s.snapshot.labels or {}
      for _, id in ipairs(s.snapshot and {} or shown.ys) do
        for _, col in ipairs(s.schema and s.schema.columns or {}) do
          if col.id == id then labels[#labels + 1] = col.label end
        end
      end
      return {
        ' ' .. opts.name .. ' · ' .. shown.style .. ' · ' .. table.concat(labels, ', ') .. (view.renderer == 'cached' and ' · moving' or ''),
        ' ' .. (s.snapshot and s.snapshot.summary or 'Full variable / selected slice · loading chart'),
        ' ' .. state,
        '',
      }
    end,
  }
  local buf = surface.buf
  s.buf, s.win = buf, surface.win
  vim.bo[buf].filetype = 'molten-plot'
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
    surface.overlay(lines)
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
    vim.b[buf].plot_settings = s.settings
    if not s.help and not s.settings_open then
      surface.overlay(nil)
      surface.chrome()
      return
    end
    if s.help then
      return write {
        ' PLOT WORKSPACE',
        '',
        ' t type · x X column · y Y columns (toggle choices, then Done)',
        ' g row range [start, stop) · d point/cell budget · n histogram bins',
        ' L title/axis labels · a legend · r refresh source · s settings',
        ' Confirming a setting redraws automatically; Enter retries.',
        ' +/- zoom · hjkl/arrows pan · 0 fit · q closes overlay, then viewer.',
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
        ' ? / q returns to chart',
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
      '  g  Row range     [' .. c.start .. ', ' .. tostring(c.stop or 'end') .. ')  · stop exclusive',
      '  d  Budget        '
        .. (
          c.style == 'histogram' and 'Exact · all selected values (100,000 maximum)' or (c.limit .. (c.style == 'heatmap' and ' cells' or ' rows per series'))
        ),
      '  n  Histogram     ' .. (c.style == 'histogram' and (c.bins .. ' bins') or '(not used for this type)'),
      '  L  Title         ' .. c.title,
      '     Axis labels   ' .. (c.xlabel == '' and 'automatic' or c.xlabel) .. ' / ' .. (c.ylabel == '' and 'automatic' or c.ylabel),
      '  a  Legend        ' .. (c.legend and 'shown' or 'hidden'),
      '',
      ' '
        .. (
          s.message
          or (
            s.error and 'Correct settings or reload schema with R; Enter retries'
            or s.dirty and 'Updating chart…'
            or 'Chart ready · q returns to chart · b browser · e export'
          )
        ),
      ' ' .. (s.caption or ''),
      ' ' .. (s.error or ''),
      '',
      ' Changes redraw automatically · q returns to chart · ? help',
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
    local serial = s.serial
    vim.schedule(function()
      if active == s and serial == s.serial then draw() end
    end)
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
      draw()
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
      if #folders > 8 then
        for i, old in ipairs(folders) do
          if not s.files or old ~= vim.fs.dirname(s.files.png) then
            vim.fn.delete(table.remove(folders, i), 'rf')
            break
          end
        end
      end
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
            s.snapshot = {
              files = reply.files,
              caption = data.plot.caption,
              labels = data.plot.y_labels,
              settings = vim.deepcopy(s.settings),
              summary = string.format(
                '%s · %d/%d rows · [%d, %d)',
                data.plot.sampled and 'Sampled: may miss spikes' or 'Complete range',
                data.plot.emitted_rows,
                data.plot.range_rows,
                s.settings.start,
                s.settings.stop
              ),
            }
            vim.b[buf].plot_snapshot = s.snapshot
            surface.update(reply.files.png, reply.files.svg, s.settings.title)
          end
          render()
        end)
      )
    end)
  end
  local function map(key, fn, desc) vim.keymap.set('n', key, fn, { buffer = buf, silent = true, desc = desc }) end
  local function close()
    if s.help or s.settings_open then
      s.help, s.settings_open = false, false
      render()
      return
    end
    surface.close()
  end
  map('q', close, 'Back / close chart')
  map('<Esc>', close, 'Back / close chart')
  map('?', function()
    s.help = not s.help
    render()
  end, 'Plot help')
  map('<CR>', draw, 'Draw configured plot')
  map('R', schema, 'Reload source schema')
  map('r', schema, 'Refresh source and chart')
  map('s', function()
    s.settings_open = not s.settings_open
    s.help = false
    render()
  end, 'Plot settings')
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
  local draft_ys
  local function select_y()
    if not s.schema then return end
    local choices = { -1 }
    for _, c in ipairs(s.schema.columns) do
      if c.numeric then choices[#choices + 1] = c.id end
    end
    vim.ui.select(choices, {
      prompt = 'Y columns · toggle selections, then Done',
      format_item = function(v) return v == -1 and 'Done' or ((vim.tbl_contains(draft_ys, v) and '[✓] ' or '[ ] ') .. column(v)) end,
    }, function(v)
      if active ~= s then return end
      if v == nil then
        draft_ys = nil
        return
      end
      if v == -1 then
        s.settings.ys = draft_ys
        change()
        return
      end
      if vim.tbl_contains(draft_ys, v) then
        draft_ys = vim.tbl_filter(function(id) return id ~= v end, draft_ys)
      else
        draft_ys[#draft_ys + 1] = v
      end
      vim.schedule(select_y)
    end)
  end
  map('y', function()
    draft_ys = vim.deepcopy(s.settings.ys)
    select_y()
  end, 'Choose Y columns')
  map('g', function()
    input('Row range: start, stop (zero-based, stop exclusive): ', s.settings.start .. ', ' .. tostring(s.settings.stop or ''), function(v)
      local a, b = v:match '^%s*(%d+)%s*,%s*(%d+)%s*$'
      if not a then return vim.notify('Enter start, stop; e.g. 0, 100', vim.log.levels.WARN) end
      s.settings.start, s.settings.stop = tonumber(a), tonumber(b)
      change()
    end)
  end, 'Select row range')
  for key, field in pairs { d = 'limit', n = 'bins' } do
    map(key, function()
      if field == 'limit' and s.settings.style == 'histogram' then return vim.notify 'Histograms use every selected value; g changes the row range' end
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
  map('L', function()
    input('Plot title: ', s.settings.title, function(v)
      input('X label (blank = automatic): ', s.settings.xlabel, function(x)
        input('Y label (blank = automatic): ', s.settings.ylabel, function(y)
          s.settings.title, s.settings.xlabel, s.settings.ylabel = v, x, y
          change()
        end)
      end)
    end)
  end, 'Set title and axis labels')
  local function ready()
    if s.dirty or not s.files then
      vim.notify 'Chart is updating or failed; wait or press r to retry'
      return false
    end
    return true
  end
  map('v', function()
    s.help, s.settings_open = false, false
    render()
  end, 'Return to chart')
  map('o', function()
    if ready() then vim.ui.open(s.files.html) end
  end, 'Open interactive chart')
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
      if active == s and api.nvim_win_is_valid(s.win) then render() end
    end,
  })
  schema()
end
return M
