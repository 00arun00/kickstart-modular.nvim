local M = {}
local api = vim.api
local active
local files = {}
local highlights = api.nvim_create_namespace 'image-viewer-ui'
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('python-image-files', { clear = true }),
  callback = function()
    for _, file in ipairs(files) do
      vim.fn.delete(file)
    end
  end,
})
local function geometry()
  local width, height = math.max(1, math.min(140, vim.o.columns - 6)), math.max(1, math.min(48, vim.o.lines - 6))
  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    footer = width < 85 and ' +/- zoom · 0 fit · hjkl pan · ? · q ' or ' +/- zoom · 0 fit · hjkl pan · ]/[ image · ? help · q close ',
    footer_pos = 'center',
  }
end
local function write(s, lines)
  if not api.nvim_buf_is_valid(s.buf) then return end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(s.buf, highlights, 0, -1)
  for i, line in ipairs(lines) do
    if i <= 3 then
      api.nvim_buf_set_extmark(s.buf, highlights, i - 1, 0, { end_col = #line, hl_group = i == 1 and 'Title' or i == 2 and 'Comment' or 'Special' })
    end
  end
  vim.bo[s.buf].modifiable = false
end
local function close(s, wiped)
  if s.closing then return end
  s.closing = true
  if s.job then s.job:kill(15) end
  if s.view_job then s.view_job:kill(15) end
  s.view_serial = (s.view_serial or 0) + 1
  for _, file in ipairs(s.view_files or {}) do
    vim.fn.delete(file)
  end
  s.serial = s.serial + 1
  if s.placement then s.placement:close() end
  if active == s then active = nil end
  if not wiped and api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
end
local labels = {
  HW = 'HW — grayscale image',
  CHW = 'CHW — channels, height, width',
  HWC = 'HWC — height, width, channels',
  BHW = 'BHW — batch of grayscale images',
  NCHW = 'NCHW — batch, channels, height, width',
  NHWC = 'NHWC — batch, height, width, channels',
}
function M.open(opts)
  if active then close(active) end
  local buf = api.nvim_create_buf(false, true)
  local cfg = geometry()
  cfg.border, cfg.style, cfg.title, cfg.title_pos = 'rounded', 'minimal', ' Image · ' .. opts.name .. ' ', 'center'
  local win = api.nvim_open_win(buf, true, cfg)
  local s = { buf = buf, win = win, serial = 0, options = { normalize = false }, opts = opts, zoom = 1, cx = 0.5, cy = 0.5, view_files = {}, view_serial = 0 }
  active = s
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'molten-image'
  vim.bo[buf].swapfile = false
  vim.wo[win].wrap, vim.wo[win].list = false, false
  vim.wo[win].scrolloff, vim.wo[win].sidescrolloff = 0, 0
  vim.wo[win].fillchars = 'eob: '
  vim.wo[win].cursorline = false
  local request
  local function status(lines)
    s.help_return = lines
    if not s.help then write(s, lines) end
  end
  local function layout(choices)
    vim.ui.select(choices, { prompt = 'How are the image dimensions arranged?', format_item = function(item) return labels[item] end }, function(value)
      if value and active == s then
        s.options.layout, s.options.batch, s.options.channel = value, 0, -1
        s.zoom, s.cx, s.cy = 1, 0.5, 0.5
        request()
      end
    end)
  end
  local function hide_image()
    if s.placement then
      s.placement:close()
      s.placement = nil
    end
  end
  local function header(view)
    local data = s.data
    if not data then return end
    local channel = data.channel < 0 and (data.channels == 1 and 'Grayscale' or 'Color composite') or ('Channel ' .. data.channel)
    local crop = view.crop
    local mode = math.abs(view.zoom - 1) < 0.001 and 'Fit' or string.format('%.2g× fit', view.zoom)
    local narrow = api.nvim_win_get_width(win) < 85
    local range = string.format('x %d–%d · y %d–%d', math.floor(crop[1]), math.ceil(crop[3]) - 1, math.floor(crop[2]), math.ceil(crop[4]) - 1)
    local lines = {
      string.format(
        ' %d × %d · %s%d/%d · %s · %s',
        data.width,
        data.height,
        narrow and '' or 'Image ',
        data.batch + 1,
        data.batch_count,
        channel,
        data.layout
      ),
      ' ' .. (narrow and (data.normalize and 'Contrast · min/max → black/white' or 'Original · values outside display range clip') or data.scaling),
      ' ' .. mode .. ((view.pan_x or view.pan_y) and (' · ' .. range .. ' · hjkl pan') or ' · whole image'),
      '',
    }
    for _ = 5, api.nvim_win_get_height(win) do
      lines[#lines + 1] = ''
    end
    write(s, lines)
    api.nvim_win_set_cursor(win, { 1, 0 })
    api.nvim_win_call(win, function() vim.fn.winrestview { topline = 1, leftcol = 0 } end)
  end
  local function help()
    hide_image()
    write(s, {
      ' IMAGE VIEWER',
      '',
      ' + / =     Zoom in around the viewport center',
      ' -         Zoom out (0.25× to 32× fit)',
      ' 0         Fit and center the complete image',
      ' h j k l   Pan left / down / up / right; arrows also work',
      '           Prefix a count for a larger step, e.g. 3l',
      '',
      ' ] / [     Next / previous image; keep zoom and position',
      ' g         Jump to a batch index (zero-based)',
      ' c         Choose a channel or color composite',
      ' n         Original / contrast scaling; keeps viewport',
      ' L         Choose dimension layout; resets to fit',
      ' r         Reload snapshot from the kernel',
      ' o         Open the ORIGINAL complete PNG externally',
      ' ? / q     Return to the image; q again closes the viewer',
      '',
      ' Zoom is relative to fit, not an absolute screen percentage.',
      ' Visible pixel coordinates are zero-based, including both endpoints.',
      ' Nearest-neighbor scaling keeps pixels crisp. Panning stops at image edges.',
      ' Zoom, pan and resize use the cached PNG: no kernel or GPU reads.',
      ' Source pixels are display pixels here, not the original tensor values.',
      ' Original floats use 0–1; integers use 0–255. Outside values clip.',
      ' Contrast maps finite color min/max to black/white; alpha is unchanged.',
    })
    vim.wo[win].wrap = true
    api.nvim_buf_clear_namespace(buf, highlights, 0, -1)
    api.nvim_buf_set_extmark(buf, highlights, 0, 0, { end_col = 13, hl_group = 'Title' })
    for row = 2, 15 do
      local length = #(api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or '')
      if length > 1 then api.nvim_buf_set_extmark(buf, highlights, row, 1, { end_col = math.min(10, length), hl_group = 'Special' }) end
    end
    api.nvim_win_set_cursor(win, { 1, 0 })
  end
  local repaint
  repaint = function()
    if active ~= s then return end
    s.view_serial = s.view_serial + 1
    local serial = s.view_serial
    if s.view_job then
      s.view_job:kill(15)
      s.view_job = nil
    end
    api.nvim_win_set_config(win, { footer = s.help and ' ? / q back · j/k scroll ' or geometry().footer })
    if s.help then return help() end
    if not s.file or not s.data then return write(s, s.help_return or { 'Loading image…' }) end
    if api.nvim_win_get_width(win) < 35 or api.nvim_win_get_height(win) < 10 then
      hide_image()
      return write(s, { ' Enlarge window to view image', ' ? help · o external · q close' })
    end
    vim.wo[win].wrap = false
    -- Debounce held navigation keys and only show the newest crop.
    vim.defer_fn(function()
      if active ~= s or serial ~= s.view_serial then return end
      local terminal = require('snacks.image.terminal').size()
      local columns, rows = math.max(1, api.nvim_win_get_width(win) - 2), math.max(1, api.nvim_win_get_height(win) - 5)
      local scale = terminal.scale > 0 and terminal.scale or 1
      local cw = terminal.cell_width > 0 and terminal.cell_width or 8
      local ch = terminal.cell_height > 0 and terminal.cell_height or 16
      local bg = api.nvim_get_hl(0, { name = 'NormalFloat', link = false }).bg or api.nvim_get_hl(0, { name = 'Normal', link = false }).bg or 0x1e1e2e
      local options = {
        width = math.max(1, math.floor(columns * cw / scale)),
        height = math.max(1, math.floor(rows * ch / scale)),
        zoom = s.zoom,
        cx = s.cx,
        cy = s.cy,
        background = string.format('#%06x', bg),
      }
      local file = vim.fn.tempname() .. '.png'
      s.view_files[#s.view_files + 1] = file
      local helper = vim.fs.dirname(opts.helper) .. '/image-viewport.py'
      s.view_job = vim.system(
        { opts.python, helper, s.file, file, vim.json.encode(options) },
        { text = true, timeout = 5000 },
        vim.schedule_wrap(function(result)
          if active ~= s or serial ~= s.view_serial then
            vim.fn.delete(file)
            return
          end
          s.view_job = nil
          local ok, view = pcall(vim.json.decode, result.stdout or '')
          if not ok or result.code ~= 0 or view.error then
            hide_image()
            return write(s, { ' Could not render viewport: ' .. (ok and view.error or 'local renderer failed'), ' o opens the complete PNG · q closes' })
          end
          hide_image()
          s.cx, s.cy, s.viewport = view.cx, view.cy, view
          view.file = file
          view.source_file = s.file
          vim.b[buf].image_viewport = view
          header(view)
          while #s.view_files > 4 do
            vim.fn.delete(table.remove(s.view_files, 1))
          end
          local enabled, reason = require('custom.python.images').status()
          if not enabled then
            vim.bo[buf].modifiable = true
            api.nvim_buf_set_lines(buf, 5, 7, false, { ' Inline display unavailable · o opens externally.', ' ' .. (reason:match '^[^:]+' or reason) })
            vim.bo[buf].modifiable = false
            return
          end
          require('snacks.image.terminal').detect(function()
            if active ~= s or serial ~= s.view_serial or s.help then return end
            if not require('snacks').image.supports_terminal() then
              vim.bo[buf].modifiable = true
              api.nvim_buf_set_lines(buf, 5, 7, false, { ' Terminal image support unavailable.', ' o opens the complete image externally.' })
              vim.bo[buf].modifiable = false
              return
            end
            s.placement = require('snacks').image.placement.new(
              buf,
              file,
              { inline = true, pos = { 5, 1 }, width = columns, height = rows, max_width = columns, max_height = rows }
            )
          end)
        end)
      )
    end, 30)
  end
  local function display(data, label)
    s.data = data
    api.nvim_win_set_config(win, { title = ' Image · ' .. label .. ' ' })
    s.options.layout, s.options.batch, s.options.channel = data.layout, data.batch, data.channel
    local file = vim.fn.tempname() .. '.png'
    local raw = vim.base64.decode(data.png)
    local fd = assert(vim.uv.fs_open(file, 'w', 384))
    local written, err = vim.uv.fs_write(fd, raw, 0)
    vim.uv.fs_close(fd)
    assert(written == #raw, err or 'Incomplete PNG write')
    files[#files + 1] = file
    if #files > 16 then vim.fn.delete(table.remove(files, 1)) end
    s.file = file
    vim.b[buf].image_snapshot = vim.tbl_extend('force', data, { png = '', file = file })
    s.label = label
    repaint()
  end

  request = function()
    if active ~= s then return end
    if s.job then s.job:kill(15) end
    s.serial = s.serial + 1
    s.view_serial = s.view_serial + 1
    if s.view_job then
      s.view_job:kill(15)
      s.view_job = nil
    end
    s.help = false
    api.nvim_win_set_config(win, { footer = geometry().footer })
    s.file = nil
    s.data = nil
    local serial = s.serial
    if s.placement then
      s.placement:close()
      s.placement = nil
    end
    vim.b[buf].image_snapshot = nil
    vim.b[buf].image_viewport = nil
    status { ' Loading complete image…', ' GPU images copy only the selected image/channel to CPU.' }
    local conn, err = opts.connection()
    if not conn then return status { ' ' .. err, ' r retry · q close' } end
    local payload = { name = opts.name, path = opts.path, action = 'image', image_options = s.options }
    s.job = vim.system(
      { opts.python, opts.helper, conn.path, conn.generation, vim.json.encode(payload) },
      { text = true, timeout = 6500 },
      vim.schedule_wrap(function(result)
        if active ~= s or serial ~= s.serial then return end
        s.job = nil
        local current, reason = opts.connection()
        if not current or current.generation ~= conn.generation then
          return status { ' ' .. (reason or 'Kernel restarted. Press r to reload.'), ' r retry · q close' }
        end
        local ok, reply = pcall(vim.json.decode, result.stdout or '')
        if result.code ~= 0 or not ok then return status { ' Image request timed out. Wait for the kernel, then press r.', ' q close' } end
        local data = reply.ok and reply.data or { error = reply.error }
        if data.error then return status { ' ' .. data.error, ' L change layout · r retry · q close' } end
        if not data.image.png then
          s.choices = data.image.choices
          status {
            ' Shape: ' .. table.concat(data.image.shape, ' × '),
            ' Choose a layout to distinguish channels from batch dimensions.',
            ' L choose layout · q close',
          }
          return layout(s.choices)
        end
        s.choices = data.image.choices
        local displayed, failure = pcall(display, data.image, data.name)
        if not displayed then status { 'Could not display image: ' .. tostring(failure), 'r retry · q close' } end
      end)
    )
  end
  local function map(key, callback, desc) vim.keymap.set('n', key, callback, { buffer = buf, desc = desc, silent = true }) end
  map('q', function()
    if s.help then
      s.help = false
      repaint()
    else
      close(s)
    end
  end, 'Back / close image viewer')
  map('<Esc>', function()
    if s.help then
      s.help = false
      repaint()
    else
      close(s)
    end
  end, 'Back / close image viewer')
  map('r', request, 'Reload image')
  for key, delta in pairs { [']'] = 1, ['['] = -1 } do
    map(key, function()
      if not s.data then return end
      local batch = math.max(0, math.min((s.options.batch or 0) + delta, s.data.batch_count - 1))
      if batch == s.options.batch then return vim.notify('Already at the ' .. (delta > 0 and 'last' or 'first') .. ' image') end
      s.options.batch = batch
      request()
    end, delta > 0 and 'Next image' or 'Previous image')
  end
  map('c', function()
    if not s.data then return end
    local choices = {}
    if s.data.channels == 1 or s.data.channels == 3 or s.data.channels == 4 then choices[#choices + 1] = -1 end
    for i = 0, s.data.channels - 1 do
      choices[#choices + 1] = i
    end
    vim.ui.select(choices, {
      prompt = 'Display channel',
      format_item = function(v) return v == -1 and (s.data.channels == 1 and 'Grayscale image' or 'Color composite') or ('Channel ' .. v) end,
    }, function(v)
      if v ~= nil and active == s then
        s.options.channel = v
        request()
      end
    end)
  end, 'Choose channel or color composite')
  map('n', function()
    s.options.normalize = not s.options.normalize
    request()
  end, 'Toggle original/contrast display')
  map('L', function()
    if s.choices then layout(s.choices) end
  end, 'Choose dimension layout')
  map('o', function()
    if s.file then vim.ui.open(s.file) end
  end, 'Open complete PNG externally')
  map('?', function()
    s.help = not s.help
    repaint()
  end, 'Toggle image controls')
  local function zoom(factor)
    if not s.viewport or s.help then return end
    s.zoom = math.max(0.25, math.min(32, s.zoom * factor))
    repaint()
  end
  map('+', function() zoom(math.sqrt(2)) end, 'Zoom in')
  map('=', function() zoom(math.sqrt(2)) end, 'Zoom in')
  map('-', function() zoom(1 / math.sqrt(2)) end, 'Zoom out')
  map('0', function()
    s.zoom, s.cx, s.cy = 1, 0.5, 0.5
    repaint()
  end, 'Fit whole image and center')
  for key, delta in pairs {
    h = { -1, 0 },
    j = { 0, 1 },
    k = { 0, -1 },
    l = { 1, 0 },
    ['<Left>'] = { -1, 0 },
    ['<Down>'] = { 0, 1 },
    ['<Up>'] = { 0, -1 },
    ['<Right>'] = { 1, 0 },
  } do
    map(key, function()
      if s.help then
        local direction = delta[2] > 0 and 'j' or delta[2] < 0 and 'k' or nil
        if direction then vim.cmd('normal! ' .. vim.v.count1 .. direction) end
        return
      end
      local view = s.viewport
      if not view then return end
      if not view.pan_x and not view.pan_y then return end
      local crop = view.crop
      local old_cx, old_cy = s.cx, s.cy
      local count = vim.v.count1
      local hx, hy = (crop[3] - crop[1]) / view.source_width / 2, (crop[4] - crop[2]) / view.source_height / 2
      if view.pan_x then s.cx = math.max(hx, math.min(1 - hx, s.cx + delta[1] * hx * 0.24 * count)) end
      if view.pan_y then s.cy = math.max(hy, math.min(1 - hy, s.cy + delta[2] * hy * 0.24 * count)) end
      if old_cx ~= s.cx or old_cy ~= s.cy then repaint() end
    end, 'Pan image')
  end
  map('g', function()
    if not s.data then return end
    vim.ui.input({ prompt = 'Image index (0–' .. (s.data.batch_count - 1) .. '): ', default = tostring(s.options.batch) }, function(value)
      if active ~= s or not value then return end
      local index = tonumber(value)
      if not index or index % 1 ~= 0 or index < 0 or index >= s.data.batch_count then
        return vim.notify('Enter a valid zero-based batch index', vim.log.levels.WARN)
      end
      s.options.batch = index
      request()
    end)
  end, 'Jump to batch index')
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function() close(s, true) end })
  api.nvim_create_autocmd('VimResized', {
    group = api.nvim_create_augroup('python-image-resize', { clear = true }),
    callback = function()
      if active == s and api.nvim_win_is_valid(win) then
        api.nvim_win_set_config(win, geometry())
        repaint()
      end
    end,
  })
  local function poll()
    if active ~= s then return end
    if opts.poll then opts.poll() end
    vim.defer_fn(poll, 200)
  end
  vim.defer_fn(poll, 200)
  request()
end
return M
