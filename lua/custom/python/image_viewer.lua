local M = {}
local api = vim.api
local active
local files = {}
api.nvim_create_autocmd('VimLeavePre', {
  group = api.nvim_create_augroup('python-image-files', { clear = true }),
  callback = function()
    for _, file in ipairs(files) do
      vim.fn.delete(file)
    end
  end,
})
local function geometry()
  local width, height = math.max(20, math.min(110, vim.o.columns - 6)), math.max(5, math.min(38, vim.o.lines - 6))
  return {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    footer = width < 90 and ' ]/[ image · c · n · L · ? · o · q '
      or ' ]/[ image · c channel · n contrast · L layout · ? help · o external · q close ',
    footer_pos = 'center',
  }
end
local function write(s, lines)
  if not api.nvim_buf_is_valid(s.buf) then return end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
end
local function close(s, wiped)
  if s.closing then return end
  s.closing = true
  if s.job then s.job:kill(15) end
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
  local s = { buf = buf, win = win, serial = 0, options = { normalize = false }, opts = opts }
  active = s
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  vim.wo[win].wrap, vim.wo[win].list = false, false
  local request
  local function layout(choices)
    vim.ui.select(choices, { prompt = 'How are the image dimensions arranged?', format_item = function(item) return labels[item] end }, function(value)
      if value and active == s then
        s.options.layout, s.options.batch, s.options.channel = value, 0, -1
        request()
      end
    end)
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
    local channel = data.channel < 0 and (data.channels == 1 and 'grayscale' or 'color composite') or ('channel ' .. data.channel)
    write(s, {
      string.format(' %s · %d × %d pixels · %s', label, data.width, data.height, data.layout),
      string.format(' Image %d of %d (index %d) · %s', data.batch + 1, data.batch_count, data.batch, channel),
      ' ' .. data.scaling,
      string.format(' Range %s … %s · %d nonfinite color values shown black', tostring(data.min), tostring(data.max), data.nonfinite),
      '',
      '',
    })
    local enabled, reason = require('custom.python.images').status()
    if not enabled then
      vim.bo[buf].modifiable = true
      api.nvim_buf_set_lines(
        buf,
        -1,
        -1,
        false,
        { ' Inline display unavailable: ' .. reason, ' Press o to open the complete PNG externally.', '', ' ' .. file }
      )
      vim.bo[buf].modifiable = false
      return
    end
    local serial = s.serial
    require('snacks.image.terminal').detect(function()
      if active ~= s or serial ~= s.serial or not api.nvim_buf_is_valid(buf) then return end
      if not require('snacks').image.supports_terminal() then
        write(s, { 'Terminal image support unavailable. Press o to open the PNG externally.' })
        return
      end
      s.placement = require('snacks').image.placement.new(buf, file, {
        inline = true,
        pos = { 6, 0 },
        max_width = math.max(10, api.nvim_win_get_width(win) - 2),
        max_height = math.max(2, api.nvim_win_get_height(win) - 6),
      })
    end)
  end
  request = function()
    if active ~= s then return end
    if s.job then s.job:kill(15) end
    s.serial = s.serial + 1
    s.file = nil
    s.data = nil
    local serial = s.serial
    if s.placement then
      s.placement:close()
      s.placement = nil
    end
    vim.b[buf].image_snapshot = nil
    write(s, { ' Loading complete image…', ' GPU images copy only the selected image/channel to CPU.' })
    local conn, err = opts.connection()
    if not conn then return write(s, { ' ' .. err, ' r retry · q close' }) end
    local payload = { name = opts.name, path = opts.path, action = 'image', image_options = s.options }
    s.job = vim.system(
      { opts.python, opts.helper, conn.path, conn.generation, vim.json.encode(payload) },
      { text = true, timeout = 6500 },
      vim.schedule_wrap(function(result)
        if active ~= s or serial ~= s.serial then return end
        s.job = nil
        local current, reason = opts.connection()
        if not current or current.generation ~= conn.generation then
          return write(s, { ' ' .. (reason or 'Kernel restarted. Press r to reload.'), ' r retry · q close' })
        end
        local ok, reply = pcall(vim.json.decode, result.stdout or '')
        if result.code ~= 0 or not ok then return write(s, { ' Image request timed out. Wait for the kernel, then press r.', ' q close' }) end
        local data = reply.ok and reply.data or { error = reply.error }
        if data.error then return write(s, { ' ' .. data.error, ' L change layout · r retry · q close' }) end
        if not data.image.png then
          s.choices = data.image.choices
          write(s, {
            ' Shape: ' .. table.concat(data.image.shape, ' × '),
            ' Choose a layout to distinguish channels from batch dimensions.',
            ' L choose layout · q close',
          })
          return layout(s.choices)
        end
        s.choices = data.image.choices
        local displayed, failure = pcall(display, data.image, data.name)
        if not displayed then write(s, { 'Could not display image: ' .. tostring(failure), 'r retry · q close' }) end
      end)
    )
  end
  local function map(key, callback, desc) vim.keymap.set('n', key, callback, { buffer = buf, desc = desc, silent = true }) end
  map('q', function() close(s) end, 'Return to variables')
  map('<Esc>', function() close(s) end, 'Return to variables')
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
  map(
    '?',
    function()
      vim.notify(
        'Image viewer: ]/[ browse batch; c chooses channel/color; n toggles contrast; L changes layout; r reloads; o opens PNG; q returns. Original floats use 0–1, integers use 0–255; out-of-range values clip. Contrast maps finite color min/max to black/white, preserving alpha. The source is never changed.',
        vim.log.levels.INFO,
        { title = 'Image viewer controls' }
      )
    end,
    'Image controls and scaling'
  )
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function() close(s, true) end })
  api.nvim_create_autocmd('VimResized', {
    group = api.nvim_create_augroup('python-image-resize', { clear = true }),
    callback = function()
      if active == s and api.nvim_win_is_valid(win) then
        api.nvim_win_set_config(win, geometry())
        request()
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
