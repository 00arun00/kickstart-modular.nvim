local L = require 'project_home_navigator.layout'
local M = {}
function M.rail(home)
  local rail = {}
  L.heading(rail, 'WORKSPACE')
  L.add(rail, '⌂ Home', home and 'ProjectHomeAccent' or 'ProjectHomeNormal', 'layout', 'navigator')
  L.blank(rail)
  L.add(rail, 'e Files', nil, 'browse', nil, 'e')
  L.add(rail, '/ Search', nil, 'search', nil, '/')
  L.blank(rail)
  L.heading(rail, 'COLLABORATE')
  L.blank(rail)
  L.add(rail, 'g Changes', nil, 'git', nil, 'g')
  L.add(rail, 'p Pull requests', nil, 'prs', nil, 'p')
  L.add(rail, 'w Worktrees', nil, 'worktrees', nil, 'w')
  return rail
end
function M.content_width(width) return width >= 90 and width - 24 or width - 4 end
function M.render(model, width)
  width = math.max(8, (width or 80) - 4)
  local rail_width = width >= 86 and 17 or 0
  local cw = width - (rail_width > 0 and rail_width + 3 or 0)
  local content = L.header(model, cw, 'Navigator')
  L.append(content, L.actions(cw))
  content[#content + 1] = L.resume(model)
  L.blank(content)
  if cw >= 59 then
    local lw = math.floor((cw - 3) * 0.53)
    L.append(content, L.columns(L.recents(model), L.explore(model), lw, cw - lw - 3))
  else
    L.append(content, L.recents(model))
    L.blank(content)
    L.append(content, L.explore(model))
  end
  L.blank(content)
  L.rule(content, cw)
  L.blank(content)
  L.append(content, L.git_columns(model, cw))
  if model.show_activity ~= false then
    L.blank(content)
    L.rule(content, cw)
    L.blank(content)
    L.append(content, L.activity(model, cw))
  end
  L.blank(content)
  L.add(content, 'R Refresh · j/k move · Enter open', 'ProjectHomeMuted', 'refresh', nil, 'R')
  if rail_width > 0 then
    local rail = M.rail(true)
    return L.pad(L.finish(L.columns(rail, content, rail_width, cw), width), 2)
  end
  return L.pad(L.finish(content, width), 2)
end
-- Child views reserve the same rail width before rendering their own content.
function M.decorate(model, width, page)
  if width < 90 then return page end
  local rw, gap, cw = 17, 3, M.content_width(width)
  local rail = L.finish(M.rail(false), rw)
  local out = vim.deepcopy(page)
  out.lines, out.highlights, out.items = {}, {}, {}
  local offsets = {}
  for line = 1, math.max(#rail.lines, #page.lines) do
    local left = rail.lines[line] or ''
    local prefix = '  ' .. left .. string.rep(' ', rw - L.width(left) + gap)
    offsets[line] = #prefix
    out.lines[line] = prefix .. (page.lines[line] or '')
  end
  for _, h in ipairs(rail.highlights) do
    h.start_col = h.start_col + 2
    h.end_col = h.end_col + 2
    out.highlights[#out.highlights + 1] = h
  end
  for _, item in ipairs(rail.items) do
    item.col = (item.col or 0) + 2
    out.items[#out.items + 1] = item
  end
  for _, h in ipairs(page.highlights or {}) do
    local copy = vim.deepcopy(h)
    local offset = offsets[h.line] or 20
    copy.start_col = (h.start_col or 0) + offset
    copy.end_col = (h.end_col == nil or h.end_col == -1) and #out.lines[h.line] or math.min((h.end_col or 0) + offset, #out.lines[h.line])
    if copy.start_col < copy.end_col then out.highlights[#out.highlights + 1] = copy end
  end
  for index, item in ipairs(page.items or {}) do
    local copy = vim.deepcopy(item)
    copy.col = (item.col or 0) + (offsets[item.line] or 20)
    if copy.col < #out.lines[item.line] then
      out.items[#out.items + 1] = copy
      if index == 1 then out.initial_focus = vim.deepcopy(copy) end
    end
  end
  return out
end
function M.setup() require('project_home').register('navigator', M.render, { decorate = M.decorate, content_width = M.content_width }) end
function M.open(opts)
  M.setup()
  require('project_home').open('navigator', opts)
end
return M
