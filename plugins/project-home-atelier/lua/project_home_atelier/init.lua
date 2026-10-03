local L = require 'project_home_atelier.layout'
local M = {}
function M.render(model, width)
  width = math.max(8, (width or 80) - 4)
  local rows = L.header(model, width, 'Atelier')
  L.append(rows, L.actions(width))
  local gutter = width >= 75 and 16 or 0
  local cw = width - (gutter > 0 and gutter + 3 or 0)
  local function band(number, title, content)
    L.rule(rows, width)
    L.blank(rows)
    if gutter > 0 then
      L.append(rows, L.columns({ L.row(number, 'ProjectHomeAccent'), L.row(title, 'ProjectHomeMuted') }, content, gutter, cw))
    else
      L.add(rows, number .. '  ' .. title, 'ProjectHomeAccent')
      L.blank(rows)
      L.append(rows, content)
    end
    L.blank(rows)
  end
  local recent = { L.resume(model) }
  L.blank(recent)
  local list = L.recents(model)
  table.remove(list, 1)
  L.append(recent, list)
  band('01', 'RECENT FILES', recent)
  local explore = L.explore(model)
  table.remove(explore, 1)
  band('02', 'START EXPLORING', explore)
  local git = L.git_columns(model, cw, true)
  if git[1] and git[1].text == 'GIT WORKSPACE' then table.remove(git, 1) end
  band('03', 'GIT WORKSPACE', git)
  if model.show_activity ~= false then
    local activity = L.activity(model, cw)
    table.remove(activity, 1)
    band('04', 'ACTIVITY', activity)
  end
  L.add(rows, 'R Refresh · j/k move · Enter open', 'ProjectHomeMuted', 'refresh', nil, 'R')
  return L.pad(L.finish(rows, width), 2)
end
function M.setup() require('project_home').register('atelier', M.render) end
function M.open(opts)
  M.setup()
  require('project_home').open('atelier', opts)
end
return M
