-- Opt-in installation of terminal theme consumers. No mutations during detection.
local M = {}
local uv = vim.uv
local begin_marker = '# BEGIN nvim-theme-sync'
local end_marker = '# END nvim-theme-sync'
local function read(path)
  local fd = io.open(path, 'rb')
  if not fd then return nil end
  local value = fd:read '*a'
  fd:close()
  return value
end
local function resolve(path)
  local real = uv.fs_realpath(path)
  if real then return real end
  local parent = vim.fs.dirname(path)
  if parent == path then return path end
  return resolve(parent) .. '/' .. vim.fs.basename(path)
end
local function dir() return vim.fn.stdpath 'state' .. '/terminal-theme' end
local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function tmux_quote(s) return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('%$', '\\$'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"' end
local function write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), 'p', 448)
  local temp = path .. '.' .. vim.fn.getpid() .. '.tmp'
  local fd = assert(io.open(temp, 'wb'))
  assert(fd:write(value))
  assert(fd:close())
  local stat = uv.fs_stat(path)
  assert(uv.fs_chmod(temp, stat and bit.band(stat.mode, 511) or 384))
  assert(uv.fs_rename(temp, path))
end
local function json(path)
  local value = read(path)
  return value and vim.json.decode(value) or nil
end
local function run(args)
  local ok, result = pcall(function() return vim.system(args, { text = true }):wait(2000) end)
  return ok and result or { code = -1, stdout = '', stderr = tostring(result) }
end
local function executable(name, extra)
  local path = vim.fn.exepath(name)
  if path ~= '' then return path end
  for _, candidate in ipairs(extra or {}) do
    if vim.fn.executable(candidate) == 1 then return candidate end
  end
end
local function choose(explicit, candidates)
  if explicit then return vim.fn.fnamemodify(vim.fn.expand(explicit), ':p'):gsub('/$', '') end
  local found = {}
  for _, candidate in ipairs(candidates) do
    if uv.fs_stat(candidate) then found[#found + 1] = candidate end
  end
  if #found > 1 then return nil, 'multiple config files found; set an explicit config path' end
  return found[1] or candidates[1]
end

-- Parse option strings without evaluating shell substitutions. This matches the
-- quoting accepted by fzf option variables and SessionX's additional options.
function M.words(value)
  local words, word, quote, escaped, started = {}, '', nil, false, false
  for i = 1, #value do
    local ch = value:sub(i, i)
    if escaped then
      local prefix = quote == '"' and not ch:match '[\\"$`\n]' and '\\' or ''
      word, escaped, started = word .. prefix .. ch, false, true
    elseif ch == '\\' and quote ~= "'" then
      escaped, started = true, true
    elseif quote then
      if ch == quote then
        quote = nil
      else
        word = word .. ch
      end
    elseif ch == "'" or ch == '"' then
      quote, started = ch, true
    elseif ch:match '%s' then
      if started then
        words[#words + 1], word, started = word, '', false
      end
    else
      word, started = word .. ch, true
    end
  end
  assert(not quote and not escaped, 'Unclosed quote or escape in fzf options')
  if started then words[#words + 1] = word end
  return words
end
local function without_colors(words)
  local result, skip = {}, false
  for _, word in ipairs(words) do
    if skip then
      skip = false
    elseif word == '--color' then
      skip = true
    elseif not word:match '^%-%-color=' then
      result[#result + 1] = word
    end
  end
  return result
end

local tmux_options = {
  'status-left',
  'status-right',
  'window-status-format',
  'window-status-current-format',
  'window-status-style',
  'window-status-current-style',
  'window-status-activity-style',
  'window-status-bell-style',
  'display-panes-colour',
  'display-panes-active-colour',
  'clock-mode-colour',
  'status-style',
  'pane-border-style',
  'pane-active-border-style',
  'popup-style',
  'popup-border-style',
  'message-style',
  'message-command-style',
  'mode-style',
  'focus-events',
}
local function snapshot_tmux(bin)
  local restore, formats = {}, {}
  for _, option in ipairs(tmux_options) do
    local result = run { bin, 'show-options', '-gqv', option }
    assert(result.code == 0, 'Cannot read tmux option ' .. option)
    local value = (result.stdout or ''):gsub('\n$', '')
    restore[#restore + 1] = 'set-option -g ' .. option .. ' ' .. tmux_quote(value)
    if option:match 'format$' or option == 'status-left' or option == 'status-right' then formats[option] = value end
  end
  local cached = run { bin, 'show-options', '-gqv', '@sessionx-_built-fzf-opts' }
  local sessionx = cached.code == 0 and (cached.stdout or ''):match '^declare %-a fzf_opts='
  if sessionx then restore[#restore + 1] = 'set-option -g @sessionx-_built-fzf-opts ' .. tmux_quote(cached.stdout:gsub('\n$', '')) end
  local env = run { bin, 'show-environment', '-g', 'FZF_DEFAULT_OPTS' }
  if env.code == 0 and (env.stdout or ''):match '^FZF_DEFAULT_OPTS=' then
    restore[#restore + 1] = 'set-environment -g FZF_DEFAULT_OPTS ' .. tmux_quote(env.stdout:sub(18):gsub('\n$', ''))
  else
    restore[#restore + 1] = 'set-environment -gu FZF_DEFAULT_OPTS'
  end
  local additional = sessionx and run { bin, 'show-options', '-gqv', '@sessionx-additional-options' } or nil
  local parsed, args = pcall(M.words, additional and additional.stdout or '')
  return formats, sessionx and parsed and without_colors(args) or false, table.concat(restore, '\n') .. '\n'
end

local function block(lines) return begin_marker .. '\n' .. table.concat(lines, '\n') .. '\n' .. end_marker .. '\n' end
local function clean_legacy(value, state)
  -- Adopt only the exact links written by the original manual installer.
  local lines = {}
  for line in (value .. '\n'):gmatch '(.-)\n' do
    if
      line ~= 'config-file = ' .. state .. '/ghostty.conf'
      and line ~= 'source-file -q "' .. state .. '/tmux.conf"'
      and line ~= 'export FZF_DEFAULT_OPTS_FILE="' .. state .. '/fzf.conf"'
    then
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, '\n')
end

function M.plan(settings)
  settings = settings or vim.g.theme_sync or {}
  local state, home = dir(), vim.env.HOME or vim.fn.expand '~'
  local plan = {
    version = 1,
    state = state,
    targets = {},
    files = {},
    skipped = {},
    templates = { options = {}, sessionx = false, format_mode = 'semantic' },
  }
  if json(state .. '/installation.json') then
    plan.installed = true
    return plan
  end
  if uv.os_uname().sysname ~= 'Darwin' and uv.os_uname().sysname ~= 'Linux' then
    plan.skipped[#plan.skipped + 1] = 'External sync supports macOS and Linux; Neovim themes still work.'
    return plan
  end
  assert(not state:find '[\r\n]', 'State path must not contain newlines')
  local config = vim.env.XDG_CONFIG_HOME
  if not config or config == '' then config = home .. '/.config' end
  local legacy = read(state .. '/enabled') ~= nil
  plan.legacy = legacy
  local function add(name, path, lines, metadata)
    if not path then return end
    assert(not path:find '[\r\n]', 'Config paths must not contain newlines')
    local target = resolve(path)
    assert(not uv.fs_lstat(path) or uv.fs_realpath(path), 'Cannot manage a dangling symlink: ' .. path)
    assert(not uv.fs_stat(target) or uv.fs_stat(target).type == 'file', 'Not a regular config file: ' .. path)
    local before = read(target)
    assert(not uv.fs_stat(target) or before ~= nil, 'Cannot read existing config: ' .. path)
    local base = legacy and before and clean_legacy(before, state) or before or ''
    assert(not base:find(begin_marker, 1, true), 'Untracked managed block in ' .. path .. '; inspect before setup')
    local addition = (base == '' and '' or base:sub(-1) == '\n' and '\n' or '\n\n') .. block(lines)
    plan.files[#plan.files + 1] = {
      path = path,
      target = target,
      before = before,
      base = base,
      addition = addition,
      after = base .. addition,
    }
    metadata.path = path
    plan.targets[name] = metadata
  end
  if settings.ghostty ~= false then
    local bin = executable('ghostty', {
      '/Applications/Ghostty.app/Contents/MacOS/ghostty',
      home .. '/Applications/Ghostty.app/Contents/MacOS/ghostty',
    })
    local candidates = { config .. '/ghostty/config' }
    if uv.os_uname().sysname == 'Darwin' then candidates[#candidates + 1] = home .. '/Library/Application Support/com.mitchellh.ghostty/config' end
    local path, reason = choose(settings.ghostty_config, candidates)
    local version = bin and run { bin, '+version' }
    local major, minor = (version and version.stdout or ''):match 'Ghostty (%d+)%.(%d+)'
    if bin and path and major and (tonumber(major) > 1 or tonumber(minor) >= 2) then
      add('ghostty', path, { 'config-file = ' .. state .. '/ghostty.conf' }, { executable = bin, reload = executable 'pkill' ~= nil })
    else
      plan.skipped[#plan.skipped + 1] = 'Ghostty: ' .. (reason or 'requires an installed Ghostty >= 1.2 with a readable version')
    end
  end
  if settings.tmux ~= false then
    local bin = executable 'tmux'
    local path, reason = choose(settings.tmux_config, { home .. '/.tmux.conf', config .. '/tmux/tmux.conf' })
    local version = bin and run { bin, '-V' }
    local major, minor = (version and version.stdout or ''):match 'tmux (%d+)%.(%d+)'
    if bin and path and major and (tonumber(major) > 3 or tonumber(major) == 3 and tonumber(minor) >= 2) and run({ bin, 'list-sessions' }).code == 0 then
      plan.templates.options, plan.templates.sessionx, plan.tmux_restore = snapshot_tmux(bin)
      if plan.templates.sessionx == false then
        plan.skipped[#plan.skipped + 1] = 'SessionX: compatible cached options not detected; tmux styling remains supported'
      end
      local socket_result = run { bin, 'display-message', '-p', '#{socket_path}' }
      local socket = (socket_result.stdout or ''):gsub('\n$', '')
      add('tmux', path, { 'source-file -q ' .. tmux_quote(state .. '/tmux.conf') }, { executable = bin, socket = socket ~= '' and socket or nil })
    else
      plan.skipped[#plan.skipped + 1] = 'tmux: ' .. (reason or 'requires tmux >= 3.2 and a running server to preserve its layout')
    end
  end
  if settings.fzf ~= false then
    local shell = vim.fs.basename(settings.shell or vim.env.SHELL or '')
    if executable 'fzf' and (shell == 'zsh' or shell == 'bash') then
      local zdotdir = vim.env.ZDOTDIR
      if not zdotdir or zdotdir == '' then zdotdir = home end
      local default = shell == 'zsh' and (zdotdir .. '/.zshrc') or home .. '/.bashrc'
      local path = choose(settings.shell_config, { default })
      -- A function appends colours at invocation, after stale FZF_DEFAULT_OPTS.
      -- Existing FZF_DEFAULT_OPTS_FILE and explicit CLI options keep their semantics.
      add('fzf', path, {
        'function fzf() {',
        '  local _nvim_theme_colors',
        '  if [ -r ' .. shell_quote(state .. '/fzf.conf') .. ' ]; then',
        '    _nvim_theme_colors=$(command cat ' .. shell_quote(state .. '/fzf.conf') .. ')',
        '    FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS-} ${_nvim_theme_colors}" command fzf "$@"',
        '  else',
        '    command fzf "$@"',
        '  fi',
        '}',
      }, { shell = shell })
    else
      plan.skipped[#plan.skipped + 1] = 'fzf: requires fzf and a bash or zsh shell (set shell/shell_config to override)'
    end
  end
  local base = without_colors(M.words(vim.env.FZF_DEFAULT_OPTS or ''))
  plan.templates.fzf_enabled = plan.targets.fzf ~= nil
  plan.templates.fzf_base = table.concat(vim.tbl_map(shell_quote, base), ' ')
  return plan
end

local function current_target(file) return resolve(file.path) end
function M.install(plan)
  assert(not plan.installed, 'Already installed; uninstall before changing integrations')
  assert(#plan.files > 0, 'No supported integrations detected')
  for _, file in ipairs(plan.files) do
    assert(current_target(file) == file.target and read(file.target) == file.before, 'Config changed since detection: ' .. file.path)
  end
  local backup = plan.state .. '/backup-' .. os.date '%Y%m%d-%H%M%S' .. '-' .. string.format('%d', uv.hrtime())
  vim.fn.mkdir(backup, 'p', 448)
  for i, file in ipairs(plan.files) do
    file.backup = backup .. '/' .. i .. '.original'
    if file.before then write(file.backup, file.before) end
    file.installed_hash = vim.fn.sha256(file.after)
  end
  local previous = {}
  for _, name in ipairs { 'templates.json', 'enabled', 'ghostty.conf', 'tmux.conf', 'fzf.conf' } do
    previous[name] = read(plan.state .. '/' .. name) or false
  end
  local changed = {}
  local ok, err = pcall(function()
    write(plan.state .. '/templates.json', vim.json.encode(plan.templates))
    -- Generate the includes before attaching them to application configs.
    require('custom.theme_sync').export(plan.targets)
    for _, file in ipairs(plan.files) do
      write(file.target, file.after)
      changed[#changed + 1] = file
    end
    plan.backup = backup
    write(plan.state .. '/installation.json', vim.json.encode(plan))
    write(plan.state .. '/enabled', 'Managed by :ThemeSyncSetup\n')
  end)
  if not ok then
    for _, file in ipairs(changed) do
      if file.before then
        write(file.target, file.before)
      else
        uv.fs_unlink(file.target)
      end
    end
    for name, value in pairs(previous) do
      if value then
        write(plan.state .. '/' .. name, value)
      else
        uv.fs_unlink(plan.state .. '/' .. name)
      end
    end
    uv.fs_unlink(plan.state .. '/installation.json')
    error(err)
  end
  require('custom.theme_sync').publish(true)
  return backup
end

function M.uninstall_plan()
  local installed = json(dir() .. '/installation.json')
  assert(installed, 'No managed installation found. Legacy setup can be adopted with :ThemeSyncSetup!')
  local plan = { installed = installed, files = {} }
  for _, file in ipairs(installed.files) do
    assert(current_target(file) == file.target, 'Config symlink changed: ' .. file.path .. '; backup: ' .. file.backup)
    local current = read(file.target)
    assert(current, 'Config disappeared: ' .. file.path)
    local after
    if vim.fn.sha256(current) == file.installed_hash then
      after = file.base
    else
      local start, finish = current:find(file.addition, 1, true)
      assert(start and not current:find(file.addition, finish + 1, true), 'Managed block edited or missing: ' .. file.path .. '; backup: ' .. file.backup)
      after = current:sub(1, start - 1) .. current:sub(finish + 1)
    end
    plan.files[#plan.files + 1] = { path = file.target, before = current, after = after, remove = not file.before and after == '' }
  end
  return plan
end

function M.uninstall(plan)
  for _, file in ipairs(plan.files) do
    assert(read(file.path) == file.before, 'Config changed since uninstall preview: ' .. file.path)
  end
  write(plan.installed.backup .. '/installation.json', vim.json.encode(plan.installed))
  local changed = {}
  local ok, err = pcall(function()
    for _, file in ipairs(plan.files) do
      if file.remove then
        assert(uv.fs_unlink(file.path))
      else
        write(file.path, file.after)
      end
      changed[#changed + 1] = file
    end
  end)
  if not ok then
    for _, file in ipairs(changed) do
      write(file.path, file.before)
    end
    error(err)
  end
  uv.fs_unlink(dir() .. '/enabled')
  local installed = plan.installed
  if installed.targets.tmux and installed.tmux_restore then
    local path = dir() .. '/restore-tmux.conf'
    write(path, installed.tmux_restore)
    local command = { installed.targets.tmux.executable }
    if installed.targets.tmux.socket then vim.list_extend(command, { '-S', installed.targets.tmux.socket }) end
    vim.list_extend(command, { 'source-file', path })
    local result = run(command)
    if result.code ~= 0 then vim.notify('Configs removed; restart tmux to restore its original colours: ' .. (result.stderr or ''), vim.log.levels.WARN) end
  end
  if installed.targets.ghostty and installed.targets.ghostty.reload then run { 'pkill', '-USR2', '-x', 'ghostty' } end
  -- Retain the manifest and backups for recovery; do not delete unrelated state.
  assert(uv.fs_unlink(dir() .. '/installation.json'))
  vim.notify(
    'Theme sync uninstalled. Backups retained: '
      .. installed.backup
      .. '\nRestart shells (or run unset -f fzf) to remove the loaded wrapper; Neovim themes remain available.'
  )
end

local function report(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden = 'nofile', 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(table.concat(lines, '\n'), '\n', { plain = true }))
  vim.bo[buf].modifiable = false
  vim.cmd 'botright split'
  vim.api.nvim_win_set_buf(0, buf)
end
function M.commands()
  local function guarded(fn)
    return function(opts)
      local ok, err = pcall(fn, opts)
      if not ok then vim.notify('Theme sync: ' .. tostring(err), vim.log.levels.ERROR) end
    end
  end
  vim.api.nvim_create_user_command(
    'ThemeSyncSetup',
    guarded(function(opts)
      local plan = M.plan()
      if plan.installed then return vim.notify 'Theme sync is already installed. Use :ThemeSyncStatus or :ThemeSyncUninstall first.' end
      if opts.bang then
        local backup = M.install(plan)
        return vim.notify(
          'Theme sync installed. Backups: '
            .. backup
            .. '\nOpen a new shell or source its config once. Existing fzf functions are replaced by the managed wrapper.'
        )
      end
      local lines = { 'Theme sync setup (read-only preview)', '', 'State: ' .. plan.state, '' }
      for name, target in pairs(plan.targets) do
        lines[#lines + 1] = name .. ': ' .. target.path
      end
      for _, file in ipairs(plan.files) do
        lines[#lines + 1] = '\nAppend to ' .. file.path .. (file.path ~= file.target and (' -> ' .. file.target) or '') .. ':'
        vim.list_extend(lines, vim.split(file.addition, '\n', { plain = true }))
      end
      vim.list_extend(lines, plan.skipped)
      lines[#lines + 1] = '\nRun :ThemeSyncSetup! to install with backups. No files have changed.'
      if plan.legacy then lines[#lines + 1] = 'Existing manual theme links will be adopted; old backups are retained.' end
      report(lines)
    end),
    { bang = true, desc = 'Detect/preview theme sync; ! installs with backups' }
  )
  vim.api.nvim_create_user_command(
    'ThemeSyncUninstall',
    guarded(function(opts)
      local plan = M.uninstall_plan()
      if opts.bang then return M.uninstall(plan) end
      local lines = { 'Theme sync uninstall (read-only preview)', '' }
      for _, file in ipairs(plan.files) do
        lines[#lines + 1] = 'Remove managed wiring from ' .. file.path
      end
      lines[#lines + 1] = 'Later edits outside the blocks are preserved. Backups: ' .. plan.installed.backup
      lines[#lines + 1] = 'Run :ThemeSyncUninstall! to apply.'
      report(lines)
    end),
    { bang = true, desc = 'Preview uninstall; ! removes managed theme sync' }
  )
  vim.api.nvim_create_user_command(
    'ThemeSyncStatus',
    guarded(function()
      local installed = json(dir() .. '/installation.json')
      local lines = { 'Theme sync: ' .. (read(dir() .. '/enabled') and 'enabled' or 'disabled'), 'State: ' .. dir() }
      if installed then
        for name, target in pairs(installed.targets) do
          lines[#lines + 1] = name .. ': ' .. target.path
        end
        lines[#lines + 1] = 'Backups: ' .. installed.backup
      else
        lines[#lines + 1] = 'No managed installation. Run :ThemeSyncSetup to detect apps (or adopt manual links).'
      end
      report(lines)
    end),
    { desc = 'Show managed theme integrations and backups' }
  )
end
return M
