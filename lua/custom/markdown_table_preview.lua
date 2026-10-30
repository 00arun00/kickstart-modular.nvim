-- Experimental cell-by-cell renderer. Only the preview buffer is rewritten;
-- the source note and the existing Markdown renderer are never modified.
local M = {}
local ns = vim.api.nvim_create_namespace 'markdown-table-preview'

local function prose(cell, text)
  local pos = 1
  while pos <= #text do
    local br = text:sub(pos):match '^<[bB][rR]%s*/?%s*>'
    if br then
      cell[#cell + 1] = { newline = true }
      pos = pos + #br
    elseif text:sub(pos, pos + 1) == '**' then
      cell.bold = not cell.bold
      pos = pos + 2
    elseif text:sub(pos, pos):match '%s' then
      cell[#cell + 1] = { space = true }
      pos = pos + 1
    else
      local last = pos
      while last <= #text and not text:sub(last, last):match '[%s<*]' do
        last = last + 1
      end
      if last == pos then last = pos + 1 end
      cell[#cell + 1] = { text = text:sub(pos, last - 1):gsub('\\|', '|'), bold = cell.bold }
      pos = last
    end
  end
end

function M.table_at(buf, row)
  local parser = vim.treesitter.get_parser(buf, 'markdown')
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
  for _, node in query:iter_captures(tree:root(), buf) do
    local first, _, last = node:range()
    if row >= first and row < last then return node end
  end
end

function M.model(buf, node, equations)
  local model = { rows = {}, source_rows = {} }
  for row in node:iter_children() do
    if row:type() == 'pipe_table_delimiter_row' then model.separator = row:range() end
    if row:type() == 'pipe_table_header' or row:type() == 'pipe_table_row' then
      local cells = {}
      for cell in row:iter_children() do
        if cell:type() == 'pipe_table_cell' then
          local r, col, _, finish = cell:range()
          local line = vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1]
          local tokens, spans = {}, {}
          for _, image in ipairs(equations) do
            local range = image.range
            if image.type == 'math' and range[1] == r + 1 and range[3] == r + 1 and range[2] >= col and range[4] <= finish then spans[#spans + 1] = image end
          end
          table.sort(spans, function(a, b) return a.range[2] < b.range[2] end)
          for _, image in ipairs(spans) do
            prose(tokens, line:sub(col + 1, image.range[2]))
            local original = line:sub(image.range[2] + 1, image.range[4])
            tokens[#tokens + 1] = { src = image.src, display = original:sub(1, 2) == '$$', original = original }
            col = image.range[4]
          end
          prose(tokens, line:sub(col + 1, finish))
          cells[#cells + 1] = tokens
        end
      end
      model.rows[#model.rows + 1] = cells
      model.source_rows[#model.source_rows + 1] = row:range()
    end
  end
  return model
end

local function cell_layout(tokens, width, measure)
  local result = { lines = { {} }, images = {} }
  local x, pending = 0, false
  local function newline()
    result.lines[#result.lines + 1] = {}
    x, pending = 0, false
  end
  local function add(text, bold)
    local line = result.lines[#result.lines]
    line[#line + 1] = { text, bold and 'MarkdownTablePreviewBold' or 'Normal' }
    x = x + vim.fn.strdisplaywidth(text)
  end
  for _, token in ipairs(tokens) do
    if token.newline then
      newline()
    elseif token.space then
      pending = x > 0
    elseif token.src then
      local size = measure(token, width)
      if token.display then
        if x > 0 then newline() end
        -- One visual blank line separates a display equation from its label.
        if #result.lines > 1 then newline() end
        local offset = math.max(0, math.floor((width - size.width) / 2))
        result.images[#result.images + 1] = { token = token, row = #result.lines, col = offset, width = size.width, height = size.height }
        for i = 1, size.height do
          if i > 1 then newline() end
          add(string.rep(' ', offset + size.width))
        end
        newline()
      else
        if x + (pending and 1 or 0) + size.width > width then newline() end
        if pending then add ' ' end
        result.images[#result.images + 1] = { token = token, row = #result.lines, col = x, width = size.width, height = 1 }
        add(string.rep(' ', size.width))
        pending = false
      end
    elseif token.text then
      local text = token.text
      if x + (pending and 1 or 0) + vim.fn.strdisplaywidth(text) > width then newline() end
      if pending then add ' ' end
      pending = false
      -- Long words are split by characters, not bytes (vaults can use Unicode).
      for i = 0, vim.fn.strchars(text) - 1 do
        local char = vim.fn.strcharpart(text, i, 1)
        if x + vim.fn.strdisplaywidth(char) > width then newline() end
        add(char, token.bold)
      end
    end
  end
  return result
end

function M.layout(model, width, measure)
  local count = #model.rows[1]
  local available = math.max(count, width - count * 3 - 1)
  local demands, total = {}, 0
  for col = 1, count do
    local demand = 8
    for _, row in ipairs(model.rows) do
      local length = 0
      for _, token in ipairs(row[col] or {}) do
        if token.src then
          length = math.max(length, measure(token, 80).width)
        elseif token.text then
          length = length + vim.fn.strdisplaywidth(token.text) + 1
        end
      end
      demand = math.max(demand, math.min(70, length))
    end
    demands[col], total = demand, total + demand
  end
  local widths, remaining = {}, available
  for col = 1, count do
    widths[col] = col == count and remaining or math.max(1, math.floor(available * demands[col] / total))
    widths[col] = math.min(widths[col], remaining - (count - col))
    remaining = remaining - widths[col]
  end
  local result = { lines = {}, highlights = {}, images = {}, widths = widths, groups = {} }
  local function border(left, middle, right)
    local pieces = {}
    for _, size in ipairs(widths) do
      pieces[#pieces + 1] = string.rep('─', size + 2)
    end
    result.lines[#result.lines + 1] = left .. table.concat(pieces, middle) .. right
  end
  border('┌', '┬', '┐')
  for ri, row in ipairs(model.rows) do
    local first = ri == 1 and 1 or #result.lines + 1
    local cells, height = {}, 1
    for col = 1, count do
      cells[col] = cell_layout(row[col] or {}, widths[col], measure)
      height = math.max(height, #cells[col].lines)
    end
    local first_row = #result.lines + 2 -- top padding + first content row
    for y = 0, height + 1 do
      local line = '│'
      for col, cell in ipairs(cells) do
        line = line .. ' '
        local used = 0
        for _, chunk in ipairs(cell.lines[y] or {}) do
          local start = #line
          line = line .. chunk[1]
          used = used + vim.fn.strdisplaywidth(chunk[1])
          result.highlights[#result.highlights + 1] = { #result.lines, start, #line, ri == 1 and 'MarkdownTablePreviewHeader' or chunk[2] }
        end
        line = line .. string.rep(' ', widths[col] - used) .. ' │'
      end
      result.lines[#result.lines + 1] = line
    end
    local offset = 2
    for col, cell in ipairs(cells) do
      for _, img in ipairs(cell.images) do
        img.row, img.col = first_row + img.row - 1, offset + img.col
        result.images[#result.images + 1] = img
      end
      offset = offset + widths[col] + 3
    end
    if ri > 1 and ri == #model.rows then
      border('└', '┴', '┘')
    elseif ri > 1 then
      border('├', '┼', '┤')
    end
    result.groups[#result.groups + 1] = { source = model.source_rows[ri], first = first, last = #result.lines, anchor = first_row }
    if ri == 1 then
      if #model.rows == 1 then
        border('└', '┴', '┘')
      else
        border('├', '┼', '┤')
      end
      result.groups[#result.groups + 1] = { source = model.separator, first = #result.lines, last = #result.lines, anchor = #result.lines }
    end
  end
  return result
end

local function place(buf, image)
  local placement = Snacks.image.placement.new(buf, image.token.src, {
    inline = true,
    conceal = true,
    pos = { image.row, 0 },
    range = { image.row, 0, image.row + image.height - 1, 0 },
    on_update_pre = function(p)
      -- Use Snacks' real image grid, but paint only over preallocated blank
      -- cells. Source concealment and added virtual lines would break borders.
      if p._table_grid then return end
      p._table_grid = true
      p.is_concealed = function() return false end
      p.state = function(self)
        return { hidden = self.hidden or false, loc = { image.row, image.col, width = image.width, height = image.height }, wins = self:wins() }
      end
      local render = p._render
      p._render = function(self, marks)
        for _, mark in ipairs(marks) do
          mark.col, mark.end_col, mark.end_row, mark.conceal = 0, nil, nil, nil
          mark.virt_text_pos, mark.virt_text_win_col = 'overlay', image.col
        end
        return render(self, marks)
      end
    end,
  })
  return placement
end

function M.open()
  local source = vim.api.nvim_get_current_buf()
  local ok, node = pcall(M.table_at, source, vim.api.nvim_win_get_cursor(0)[1] - 1)
  if not ok or not node then return vim.notify('Place the cursor inside a Markdown table first.', vim.log.levels.INFO) end
  if not Snacks.image.supports_terminal() or not Snacks.image.terminal.env().placeholders then
    return vim.notify('Math table preview requires Ghostty or Kitty with inline image support.', vim.log.levels.WARN)
  end
  local tick = vim.api.nvim_buf_get_changedtick(source)
  Snacks.image.doc.find(source, function(equations)
    if not vim.api.nvim_buf_is_valid(source) or vim.api.nvim_buf_get_changedtick(source) ~= tick then
      return vim.notify('The table changed while parsing; run :MarkdownMathTable again.', vim.log.levels.INFO)
    end
    local model = M.model(source, node, equations)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'Math table preview · ' .. buf)
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
    -- A tab keeps the note's full width available to this layout experiment.
    vim.cmd.tabnew()
    local empty = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(0, buf)
    if empty ~= source and vim.bo[empty].buftype == '' and vim.api.nvim_buf_get_name(empty) == '' then vim.api.nvim_buf_delete(empty, {}) end
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].wrap, vim.wo[win].number, vim.wo[win].relativenumber = false, false, false
    vim.wo[win].signcolumn, vim.wo[win].foldcolumn = 'no', '0'
    vim.wo[win].statuscolumn, vim.wo[win].conceallevel = '', 0
    vim.api.nvim_set_hl(0, 'MarkdownTablePreviewBold', { bold = true, default = true })
    vim.api.nvim_set_hl(0, 'MarkdownTablePreviewHeader', { link = 'Title', default = true })
    local placements, listeners, images = {}, {}, {}
    local queued, closed = false, false
    local draw
    local function refresh()
      if queued or closed then return end
      queued = true
      vim.schedule(function()
        queued = false
        if not closed and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then draw() end
      end)
    end
    draw = function()
      for _, p in ipairs(placements) do
        p:close()
      end
      placements = {}
      local info = vim.fn.getwininfo(win)[1]
      local layout = M.layout(model, info.width - info.textoff, function(token, width)
        local img = images[token.src]
        if img:ready() then return Snacks.image.util.fit(img.file, { width = width, height = token.display and 8 or 1 }, { info = img.info }) end
        return { width = math.min(width, token.display and 16 or 3), height = token.display and 4 or 1 }
      end)
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, layout.lines)
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      for _, hl in ipairs(layout.highlights) do
        vim.api.nvim_buf_set_extmark(buf, ns, hl[1], hl[2], { end_col = hl[3], hl_group = hl[4] })
      end
      vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
      for _, image in ipairs(layout.images) do
        if images[image.token.src]:ready() then placements[#placements + 1] = place(buf, image) end
      end
    end
    for _, row in ipairs(model.rows) do
      for _, cell in ipairs(row) do
        for _, token in ipairs(cell) do
          if token.src and not images[token.src] then
            local img = Snacks.image.image.new(token.src)
            images[token.src] = img
            local listener =
              { update = refresh, error = function() vim.notify('A table equation could not be rendered; see :checkhealth snacks.', vim.log.levels.WARN) end }
            img:place(listener)
            listeners[#listeners + 1] = { img, listener }
          end
        end
      end
    end
    local group = vim.api.nvim_create_augroup('markdown-table-preview-' .. buf, { clear = true })
    vim.api.nvim_create_autocmd('WinResized', { group = group, callback = refresh })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        closed = true
        for _, p in ipairs(placements) do
          p:close()
        end
        for _, listener in ipairs(listeners) do
          listener[1]:del(listener[2].id)
        end
        vim.api.nvim_del_augroup_by_id(group)
      end,
    })
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, desc = 'Close math table preview' })
    draw()
  end)
end

return M
