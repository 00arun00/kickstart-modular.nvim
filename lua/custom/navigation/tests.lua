-- File-local test navigation, with previews that never take source focus.
return function(client)
  local nio = require 'nio'
  local attached, preview, request = {}, nil, 0
  local keys = { '[t', ']t', '[f', ']f' }
  local group = vim.api.nvim_create_augroup('TestNavigation', { clear = true })

  local function close()
    if preview and vim.api.nvim_win_is_valid(preview.win) then vim.api.nvim_win_close(preview.win, true) end
    preview = nil
  end

  local function at(win, buf, cursor)
    return vim.api.nvim_get_current_win() == win and vim.api.nvim_get_current_buf() == buf and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
  end

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufLeave', 'WinLeave', 'InsertEnter' }, {
    group = group,
    callback = function(ev)
      if ev.event ~= 'CursorMoved' then request = request + 1 end
      if preview and (ev.event ~= 'CursorMoved' or not at(preview.source, preview.buf, preview.cursor)) then close() end
    end,
  })

  local function show(result, name, win, buf, cursor, token)
    if not result then return end
    -- A scheduled preview must not follow the user into another buffer or
    -- overtake a newer navigation request while discovery is still running.
    vim.schedule(function()
      if token ~= request or not at(win, buf, cursor) or vim.api.nvim_get_mode().mode ~= 'n' then return end
      local status = result.status or 'unknown'
      local title = status:sub(1, 1):upper() .. status:sub(2)
      local highlights = { passed = 'DiagnosticOk', failed = 'DiagnosticError', skipped = 'DiagnosticWarn' }
      local highlight = highlights[status] or 'DiagnosticInfo'
      local text = result.short
      if not text or text == '' then
        local messages = { name }
        for _, err in ipairs(result.errors or {}) do
          if err.message then messages[#messages + 1] = err.message end
        end
        text = table.concat(messages, '\n')
      end
      -- Short pytest reports can contain terminal color escapes.
      text = text:gsub('\27%[[0-?]*[ -/]*[@-~]', ''):gsub('\r', '')
      local border = {}
      for _, char in ipairs { '╭', '─', '╮', '│', '╯', '─', '╰', '│' } do
        border[#border + 1] = { char, highlight }
      end
      local _, float = vim.lsp.util.open_floating_preview(vim.split(text, '\n', { plain = true }), 'text', {
        focus = false,
        focusable = false,
        border = border,
        title = { { ' ' .. title .. ' ', highlight } },
        title_pos = 'left',
        max_width = math.max(1, math.floor(vim.o.columns * 0.6)),
        max_height = math.max(1, math.min(12, math.floor(vim.o.lines * 0.4))),
        close_events = {},
      })
      vim.w[float].test_navigation_preview = true
      preview = { win = float, source = win, buf = buf, cursor = cursor }
    end)
  end

  local function jump(direction, failed)
    request = request + 1
    local token = request
    close()
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local path = vim.api.nvim_buf_get_name(buf)
    nio.run(function()
      -- Resolve the registered project owner; a nested environment directory
      -- is not necessarily the root Neotest uses to identify its adapter.
      local owner, provider = client:get_adapter(path)
      local root = provider and provider.root(path)
      if root then owner = client:get_adapter(root) or owner end
      local tree, adapter = client:get_position(path, { adapter = owner or attached[buf] })
      if token ~= request or not at(win, buf, cursor) or not tree then return end
      local results = client:get_results(adapter)
      local target
      for _, node in tree:iter_nodes() do
        local pos = node:data()
        local result = results[pos.id]
        if pos.type == 'test' and pos.path == path and pos.range and (not failed or (result and result.status == 'failed')) then
          local row = pos.range[1] + 1
          if (direction > 0 and row > cursor[1]) or (direction < 0 and row < cursor[1]) then
            if not target or (row - target.range[1] - 1) * direction < 0 then target = pos end
          end
        end
      end
      if not target then
        vim.notify('No ' .. (failed and 'failed tests' or 'tests') .. (direction > 0 and ' below' or ' above') .. ' cursor', vim.log.levels.INFO)
        return
      end
      vim.cmd "normal! m'"
      vim.api.nvim_win_set_cursor(win, { target.range[1] + 1, target.range[2] })
      vim.cmd 'normal! zv'
      show(results[target.id], target.name, win, buf, vim.api.nvim_win_get_cursor(win), token)
    end)
  end

  local function attach(tree, adapter)
    if tree:data().type ~= 'file' then return end
    local buf = vim.fn.bufnr(tree:data().path)
    if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then return end
    local has_tests = false
    for _, node in tree:iter_nodes() do
      if node:data().type == 'test' then
        has_tests = true
        break
      end
    end
    if not has_tests then
      if attached[buf] then
        for _, key in ipairs(keys) do
          vim.keymap.del('n', key, { buffer = buf })
        end
        attached[buf] = nil
      end
      return
    end
    local mapped = attached[buf]
    attached[buf] = adapter
    if mapped then return end
    for _, key in ipairs(keys) do
      local direction, failed = key:sub(1, 1) == ']' and 1 or -1, key:sub(2) == 'f'
      vim.keymap.set('n', key, function() jump(direction, failed) end, {
        buffer = buf,
        desc = 'Tests: ' .. (direction > 0 and 'next' or 'previous') .. (failed and ' failure' or ' test') .. ' and preview',
      })
    end
  end

  client.listeners.discover_positions = function(adapter, tree) attach(tree, adapter) end
  client.listeners.test_file_focused = function(adapter, path)
    local tree = client:get_position(path, { adapter = adapter })
    if tree then attach(tree, adapter) end
  end
  vim.api.nvim_create_autocmd('BufWipeout', { group = group, callback = function(ev) attached[ev.buf] = nil end })
  -- Start discovery after all consumers are installed, including on a cold
  -- FileType load before the user has run a test or opened the summary.
  vim.schedule(function()
    nio.run(function() client:get_position(vim.api.nvim_buf_get_name(0)) end)
  end)
  return {}
end
