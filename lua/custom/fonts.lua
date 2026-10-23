-- Typography belongs to the terminal; confirmed choices apply across Ghostty.
local M = {}
local uv = vim.uv
M.presets = {
  { id = 'original', label = 'JetBrains Mono (baseline)', detail = 'Your existing Ghostty typography, without overrides' },
  {
    id = 'writer',
    label = 'iA Writer Mono',
    family = 'iA Writer Mono V',
    cask = 'font-ia-writer-mono',
    detail = '15pt · line height +12% · padding 20 × 14pt',
  },
  { id = 'lilex', label = 'Lilex', family = 'Lilex', cask = 'font-lilex', detail = '15pt · line height +12% · padding 20 × 14pt' },
  { id = 'maple', label = 'Maple Mono', family = 'Maple Mono', cask = 'font-maple-mono', detail = '15pt · line height +12% · padding 20 × 14pt' },
  {
    id = 'recursive',
    label = 'Recursive Mono Casual',
    family = 'Rec Mono Casual',
    cask = 'font-recursive-code',
    detail = '15pt · line height +12% · padding 20 × 14pt · installs the Recursive Code family',
  },
  { id = 'plex', label = 'IBM Plex Mono', family = 'IBM Plex Mono', cask = 'font-ibm-plex-mono', detail = '15pt · line height +12% · padding 20 × 14pt' },
  { id = 'commit', label = 'Commit Mono', family = 'CommitMono', cask = 'font-commit-mono', detail = '15pt · line height +12% · padding 20 × 14pt' },
}
local function dir() return vim.fn.stdpath 'state' .. '/terminal-font' end
local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read '*a'
  f:close()
  return s
end
local function write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), 'p', 448)
  local tmp = path .. '.' .. vim.fn.getpid() .. '.tmp'
  local f = assert(io.open(tmp, 'wb'))
  assert(f:write(value))
  assert(f:close())
  local stat = uv.fs_stat(path)
  assert(uv.fs_chmod(tmp, stat and bit.band(stat.mode, 511) or 384))
  assert(uv.fs_rename(tmp, path))
end
local function run(args)
  local result = vim.system(args, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr or 'Command failed')
  return result.stdout or ''
end
local function manifest()
  local raw = read(dir() .. '/installation.json')
  return raw and vim.json.decode(raw)
end
local function reload()
  local result = vim.system({ 'pkill', '-USR2', '-x', 'ghostty' }, { text = true }):wait(1000)
  if result.code ~= 0 and result.code ~= 1 then vim.notify('Font saved; reload Ghostty configuration manually.', vim.log.levels.WARN) end
end
function M.render(id)
  local preset
  for _, item in ipairs(M.presets) do
    if item.id == id then preset = item end
  end
  assert(preset, 'Unknown font preset: ' .. tostring(id))
  local lines = { '# font-choice: ' .. id }
  if preset.family then
    -- Reset lists so a user's existing family does not remain the primary font.
    vim.list_extend(lines, {
      'font-family = ""',
      'font-family = ' .. preset.family,
      'font-family-bold = ""',
      'font-family-italic = ""',
      'font-family-bold-italic = ""',
      'font-style = default',
      'font-style-bold = default',
      'font-style-italic = default',
      'font-style-bold-italic = default',
      'font-size = 15',
      'adjust-cell-height = 12%',
      'adjust-cell-width = 0',
      'window-padding-x = 20',
      'window-padding-y = 14',
    })
  end
  return table.concat(lines, '\n') .. '\n'
end
function M.current() return (read(dir() .. '/ghostty.conf') or ''):match '^# font%-choice: ([%w-]+)' or 'original' end
local function installed_fonts(bin)
  local result = {}
  for line in run({ bin, '+list-fonts' }):gmatch '[^\r\n]+' do
    result[line] = true
  end
  return result
end
-- Keep the saved id stable while naming a custom baseline accurately too.
function M.baseline_label()
  local data = manifest()
  local family
  for line in ((data and read(data.backup)) or ''):gmatch '[^\r\n]+' do
    local value = line:match '^%s*font%-family%s*=%s*(.-)%s*$'
    if value then
      value = value:gsub('^"(.*)"$', '%1')
      if value == '' then
        family = nil
      elseif not family then
        family = value
      end
    end
  end
  return (family or 'JetBrains Mono') .. ' (baseline)'
end
local installing = {}
local function install_changed() vim.api.nvim_exec_autocmds('User', { pattern = 'FontInstallChanged', modeline = false }) end
function M.install_font(id, done)
  local preset
  for _, item in ipairs(M.presets) do
    if item.id == id then preset = item end
  end
  assert(preset and preset.cask, 'No installer for this font')
  assert(uv.os_uname().sysname == 'Darwin', 'Install this font with your system font manager, then reopen FontPicker')
  local brew = vim.fn.exepath 'brew'
  assert(brew ~= '', 'Homebrew is required for in-picker installation; install the font manually and reopen FontPicker')
  if installing[id] then return vim.notify(preset.label .. ' is already installing') end
  local choice = vim.fn.confirm('Install ' .. preset.label .. ' with Homebrew?\n\nbrew install --cask ' .. preset.cask, '&No\n&Install', 1)
  if choice ~= 2 then return end
  local log = dir() .. '/install-' .. id .. '.log'
  local output = ''
  write(log, '')
  installing[id] = true
  local function stream(err, chunk)
    vim.schedule(function()
      output = output .. (chunk or err or '')
      pcall(write, log, output)
      install_changed()
    end)
  end
  vim.notify('Installing ' .. preset.label .. ' with Homebrew…')
  local ok, err = pcall(vim.system, { brew, 'install', '--cask', preset.cask }, {
    text = true,
    stdin = false,
    timeout = 300000,
    stdout = stream,
    stderr = stream,
    env = { HOMEBREW_NO_AUTO_UPDATE = '1' },
  }, function(result)
    vim.schedule(function()
      installing[id] = nil
      output = output .. (result.stdout or '') .. (result.stderr or '')
      local saved = pcall(write, log, output)
      if result.code == 0 then
        vim.notify(preset.label .. ' installed. Select it and press Enter to apply.')
      else
        local reason = result.code == 124 and 'timed out after 5 minutes' or ('failed (exit ' .. result.code .. ')')
        vim.notify('Font installation ' .. reason .. '. ' .. (saved and ('See ' .. log) or (result.stderr or '')), vim.log.levels.ERROR)
      end
      install_changed()
      if done then done(result.code == 0) end
    end)
  end)
  if not ok then
    installing[id] = nil
    install_changed()
    error(err)
  end
end
function M.select(id)
  local data = assert(manifest(), 'Run :FontSetup! first to enable Ghostty font switching')
  assert(uv.fs_realpath(data.path) == data.target, 'Ghostty config target changed; inspect font setup')
  assert((read(data.target) or ''):find(data.block, 1, true), 'Font setup block was changed or removed')
  local output = M.render(id)
  for _, item in ipairs(M.presets) do
    if item.id == id and item.family then assert(installed_fonts(data.executable)[item.family], 'Font not installed: ' .. item.family) end
  end
  write(dir() .. '/ghostty.conf', output)
  reload()
end
function M.install()
  if manifest() then return vim.notify 'Font switching is already set up' end
  local home = vim.env.HOME
  local bin = vim.fn.exepath 'ghostty'
  if bin == '' then
    for _, path in ipairs { '/Applications/Ghostty.app/Contents/MacOS/ghostty', home .. '/Applications/Ghostty.app/Contents/MacOS/ghostty' } do
      if vim.fn.executable(path) == 1 then
        bin = path
        break
      end
    end
  end
  assert(bin ~= '', 'Ghostty not found')
  local major, minor = run({ bin, '+version' }):match 'Ghostty (%d+)%.(%d+)'
  assert(major and (tonumber(major) > 1 or tonumber(minor) >= 2), 'Requires Ghostty >= 1.2')
  local path = (vim.g.font_sync or {}).ghostty_config
  if not path then
    local found = {}
    local xdg = vim.env.XDG_CONFIG_HOME
    if not xdg or xdg == '' then xdg = home .. '/.config' end
    local candidates = { xdg .. '/ghostty/config' }
    if uv.os_uname().sysname == 'Darwin' then candidates[#candidates + 1] = home .. '/Library/Application Support/com.mitchellh.ghostty/config' end
    for _, candidate in ipairs(candidates) do
      if uv.fs_stat(candidate) then found[#found + 1] = candidate end
    end
    assert(#found == 1, 'Set vim.g.font_sync = { ghostty_config = "/path/to/config" } to choose an existing Ghostty config')
    path = found[1]
  end
  path = vim.fn.fnamemodify(vim.fn.expand(path), ':p')
  local target = assert(uv.fs_realpath(path), 'Ghostty config must exist')
  local before = assert(read(target), 'Cannot read Ghostty config')
  assert(not before:find('# BEGIN nvim-font-sync', 1, true), 'Untracked font setup block; inspect config before setup')
  assert(not dir():find '[\r\n]', 'State path contains newlines')
  local block = '\n# BEGIN nvim-font-sync\nconfig-file = ' .. dir() .. '/ghostty.conf\n# END nvim-font-sync\n'
  local backup = dir() .. '/backup-' .. os.date '%Y%m%d-%H%M%S' .. '-' .. vim.fn.getpid()
  write(backup, before)
  write(dir() .. '/ghostty.conf', M.render 'original')
  local data = { path = path, target = target, executable = bin, block = block, backup = backup }
  local ok, err = pcall(function()
    write(target, before .. block)
    write(dir() .. '/installation.json', vim.json.encode(data))
  end)
  if not ok then
    write(target, before)
    error(err)
  end
  vim.notify('Font switching enabled. Baseline preserved; backup: ' .. backup)
end
function M.uninstall()
  local data = assert(manifest(), 'Font switching is not installed')
  assert(uv.fs_realpath(data.path) == data.target, 'Config symlink changed; restore manually from ' .. data.backup)
  local value = assert(read(data.target))
  local first, last = value:find(data.block, 1, true)
  assert(first, 'Managed block was edited; restore manually from ' .. data.backup)
  write(data.target, value:sub(1, first - 1) .. value:sub(last + 1))
  assert(uv.fs_unlink(dir() .. '/installation.json'))
  reload()
  vim.notify 'Font switching removed; backups and installed fonts retained'
end
local function guarded(fn)
  local ok, err = pcall(fn)
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end
function M.pick()
  local data = manifest()
  if not data then return vim.notify('Run :FontSetup! once to enable font switching', vim.log.levels.WARN) end
  local available = installed_fonts(data.executable)
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'
  local current = M.current()
  local presets = vim.deepcopy(M.presets)
  presets[1].label = M.baseline_label()
  local function finder()
    return require('telescope.finders').new_table {
      results = presets,
      entry_maker = function(item)
        local missing = item.family and not available[item.family]
        return {
          value = item,
          ordinal = item.label,
          display = (current == item.id and '● ' or '  ')
            .. item.label
            .. (installing[item.id] and ' [installing…]' or missing and ' [not installed]' or ''),
        }
      end,
    }
  end
  local picker
  picker = require('telescope.pickers').new({}, {
    prompt_title = 'Fonts — Enter applies / offers installation',
    finder = finder(),
    sorter = require('telescope.config').values.generic_sorter {},
    previewer = require('telescope.previewers').new_buffer_previewer {
      define_preview = function(self, entry)
        local lines = require('custom.font_profiles').lines(entry.value, available[entry.value.family])
        if installing[entry.value.id] then
          local log = dir() .. '/install-' .. entry.value.id .. '.log'
          local output = vim.split((read(log) or ''):gsub('\r', '\n'), '\n', { trimempty = true })
          local progress = { 'INSTALLING — Homebrew is running (5 minute limit)', 'Log: ' .. log }
          for i = math.max(1, #output - 5), #output do
            progress[#progress + 1] = output[i]
          end
          progress[#progress + 1] = ''
          vim.list_extend(progress, lines)
          lines = progress
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = 'markdown'
        if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
        end
      end,
    },
    attach_mappings = function(buf)
      local watcher = vim.api.nvim_create_autocmd('User', {
        pattern = 'FontInstallChanged',
        callback = function()
          if not vim.api.nvim_buf_is_valid(buf) then return true end
          guarded(function()
            available = installed_fonts(data.executable)
            picker:refresh(finder(), { reset_prompt = false })
          end)
        end,
      })
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        once = true,
        callback = function() pcall(vim.api.nvim_del_autocmd, watcher) end,
      })
      actions.select_default:replace(function()
        local entry = state.get_selected_entry()
        if not entry then return end
        if entry.value.family and not available[entry.value.family] then
          guarded(function()
            M.install_font(entry.value.id)
            picker:refresh(finder(), { reset_prompt = false })
          end)
          return
        end
        actions.close(buf)
        guarded(function() M.select(entry.value.id) end)
      end)
      return true
    end,
  })
  picker:find()
end
function M.setup()
  vim.api.nvim_create_user_command('FontPicker', function() guarded(M.pick) end, { desc = 'Choose terminal typography' })
  vim.keymap.set('n', '<leader>Tf', '<cmd>FontPicker<CR>', { desc = '[T]ypography: choose [f]ont' })
  vim.api.nvim_create_user_command('FontSetup', function(opts)
    if opts.bang then
      guarded(M.install)
    else
      vim.notify 'FontSetup! backs up Ghostty config and adds a managed font include. Baseline remains active until you choose a font.'
    end
  end, { bang = true, desc = 'Opt in to Ghostty font switching' })
  vim.api.nvim_create_user_command('FontUninstall', function(opts)
    if opts.bang then
      guarded(M.uninstall)
    else
      vim.notify 'FontUninstall! removes the managed include, preserves other config edits, and reloads Ghostty. Backups and fonts are retained.'
    end
  end, { bang = true, desc = 'Remove Ghostty font switching' })
end
return M
