-- Keep the rich reader's dependency on Snacks image placement in one place.
-- The canvas uses real buffer rows so native scrolling works on the whole image.
local M = {}
local api = vim.api

function M.check()
  local ok, snacks = pcall(require, 'snacks')
  if not ok then return nil, 'Snacks image support is required.' end
  if not snacks.image.terminal.env().placeholders then return nil, 'Rich reading requires a terminal with image placeholders, such as Ghostty or Kitty.' end
  return snacks
end

function M.size() return Snacks.image.terminal.size() end

local function png_size(path)
  local file = assert(io.open(path, 'rb'))
  local header = file:read(24)
  file:close()
  assert(header and header:sub(1, 8) == '\137PNG\r\n\26\n' and header:sub(13, 16) == 'IHDR', 'Renderer returned an invalid PNG tile')
  local function integer(first)
    local a, b, c, d = header:byte(first, first + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return integer(17), integer(21)
end

function M.dispose(frame)
  if not frame or frame.closed then return end
  frame.closed = true
  for _, item in ipairs(frame.items) do
    item.img:del(item.listener.id)
    if item.listener.id then api.nvim_set_hl(0, 'SnacksImage' .. item.listener.id, {}) end
  end
  for _, info in ipairs(frame.metadata) do
    vim.fn.delete(info)
  end
end

function M.prepare(buf, result)
  local frame = { items = {}, metadata = {}, lines = {}, marks = {} }
  local ok, err = pcall(function()
    for _ = 1, result.rows do
      frame.lines[#frame.lines + 1] = ''
    end
    for _, tile in ipairs(result.tiles) do
      -- These are already-generated PNGs. Supplying their known metadata avoids
      -- an identify subprocess whose lifetime could outlast a discarded frame.
      local width, height = png_size(tile.file)
      local conversion = Snacks.image.convert.convert { src = tile.file }
      local info = conversion:tmpfile 'png.info'
      -- Snacks currently parses identify results as "PNG WxH Xdpi x Ydpi".
      -- Only seed its PNG-only identify path; fail safely if that changes.
      local steps = conversion.steps
      assert(
        #steps == 1 and steps[1].name == 'identify' and steps[1].file == info and conversion.file == conversion.src,
        'Snacks PNG conversion changed; rich image metadata needs an adapter update'
      )
      local cache = vim.fs.normalize(Snacks.image.config.cache) .. '/'
      assert(vim.fs.normalize(info):sub(1, #cache) == cache, 'Unexpected Snacks image metadata path')
      frame.metadata[#frame.metadata + 1] = info
      assert(vim.fn.writefile({ ('PNG %dx%d 72x72'):format(width, height) }, info) == 0, 'Could not write generated PNG metadata')
      local img = Snacks.image.image.new(tile.file)
      local listener = { update = function() end, error = function() end }
      frame.items[#frame.items + 1] = { img = img, listener = listener }
      img:place(listener)
      assert(img:ready() and not img:failed(), 'Could not load the rendered image')
      local hl = 'SnacksImage' .. listener.id
      Snacks.image.terminal.request { a = 'p', U = 1, i = img.id, p = listener.id, C = 1, c = tile.columns, r = tile.rows }
      local chunks = {}
      local placement = setmetatable({
        id = listener.id,
        img = img,
        buf = buf,
        opts = { range = { 1, 0, 1, 0 }, type = 'image' },
        _render = function(_, marks)
          for _, mark in ipairs(marks) do
            for _, chunk in ipairs(mark.virt_text or {}) do
              if chunk[2] == hl then chunks[#chunks + 1] = chunk[1] end
            end
            for _, line in ipairs(mark.virt_lines or {}) do
              for _, chunk in ipairs(line) do
                if chunk[2] == hl then chunks[#chunks + 1] = chunk[1] end
              end
            end
          end
        end,
      }, { __index = Snacks.image.placement })
      placement:render_grid { 1, 0, width = tile.columns, height = tile.rows }
      assert(#chunks == tile.rows, 'Incomplete native image placeholder grid')
      for offset, line in ipairs(chunks) do
        local row = tile.start + offset
        frame.lines[row] = ' ' .. line
        frame.marks[#frame.marks + 1] = { row = row - 1, first = 1, last = #frame.lines[row], hl = hl }
      end
    end
  end)
  if not ok then
    M.dispose(frame)
    error(err)
  end
  return frame
end

function M.publish(buf, ns, frame)
  vim.bo[buf].modifiable = true
  local ok, err = pcall(function()
    api.nvim_buf_set_lines(buf, 0, -1, false, frame.lines)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, mark in ipairs(frame.marks) do
      api.nvim_buf_set_extmark(buf, ns, mark.row, mark.first, { end_col = mark.last, hl_group = mark.hl })
    end
    vim.bo[buf].modified = false
  end)
  vim.bo[buf].modifiable = false
  if not ok then error(err) end
end

return M
