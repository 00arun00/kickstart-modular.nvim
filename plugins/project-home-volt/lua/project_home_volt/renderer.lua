local M = {}
local ns = vim.api.nvim_create_namespace 'project_home_volt'
function M.paint(ctx, sections)
  local volt = require 'volt'
  local layout = {}
  for _, section in ipairs(sections) do
    layout[#layout + 1] = {
      name = section.name,
      lines = function()
        local lines = vim.deepcopy(section.lines)
        for _, row in ipairs(lines) do
          for _, chunk in ipairs(row) do
            chunk.heading = nil
            local item = chunk[3]
            if item then chunk[3] = { click = function() ctx.dispatch(item.action, item.value) end } end
          end
        end
        return lines
      end,
    }
  end
  volt.gen_data { { buf = ctx.buf, ns = ns, xpad = 0, layout = layout } }
  volt.redraw(ctx.buf, 'all')
  -- Combine Volt's text with the existing keyboard selection and number badges.
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(ctx.buf, ns, 0, -1, { details = true })) do
    vim.api.nvim_buf_set_extmark(ctx.buf, ns, mark[2], mark[3], {
      id = mark[1],
      virt_text = mark[4].virt_text,
      virt_text_win_col = 0,
      priority = 90,
      hl_mode = 'combine',
    })
  end
  return function()
    if vim.api.nvim_buf_is_valid(ctx.buf) then vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1) end
    require('volt.state')[ctx.buf] = nil
  end
end
-- Keep real buffer text for search/accessibility and byte-accurate keyboard targets.
-- Volt paints the visible chunks; no Workspace renderer is called here.
function M.page(sections, width)
  local page = { lines = {}, items = {}, highlights = {}, sections = {}, presentation = 'workspace', cursorline = false }
  for _, section in ipairs(sections) do
    for _, chunks in ipairs(section.lines) do
      local line, row = '', #page.lines + 1
      for _, chunk in ipairs(chunks) do
        local text, item, col = chunk[1], chunk[3], #line
        if chunk.heading then page.sections[chunk.heading] = { line = row, col = col, label = text } end
        if item then
          local previous = page.items[#page.items]
          if
            previous
            and previous.line == row
            and previous.end_col == col
            and previous.action == item.action
            and vim.deep_equal(previous.value, item.value)
          then
            previous.end_col = col + #text
            previous.label = previous.label .. text
          else
            page.items[#page.items + 1] = {
              line = row,
              col = col,
              end_col = col + #text,
              label = vim.trim(text),
              action = item.action,
              value = item.value,
              key = item.key,
              section = item.section,
            }
          end
        end
        line = line .. text
      end
      assert(vim.fn.strdisplaywidth(line) <= width, 'Volt row exceeds viewport')
      page.lines[#page.lines + 1] = line
    end
  end
  page.keyboard_footer = #page.lines
  for _, item in ipairs(page.items) do
    if item.action == 'file' or item.action == 'pr' then item.end_line = item.line + 1 end
  end
  page.paint = function(ctx) return M.paint(ctx, sections) end
  return page
end
return M
