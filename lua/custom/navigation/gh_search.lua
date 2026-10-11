local M = {}

-- Each picker keeps its initial batch and completed remote searches until closed.
local sessions = setmetatable({}, { __mode = 'k' })

function M.setup(picker)
  -- GitHub actions refresh the picker after edits; discard stale search data.
  local refresh = picker.refresh
  picker.refresh = function(self, ...)
    sessions[self] = nil
    return refresh(self, ...)
  end
end

function M.close(picker)
  -- Finish cancellation before Snacks tears down the matcher. Otherwise a
  -- sleeping finder can deliver its completion callback after that teardown.
  local task = picker.finder.task
  if task:running() then
    task:abort()
    task:step()
  end
end

local function session(picker)
  sessions[picker] = sessions[picker] or { searches = {}, items = {}, seen = {} }
  return sessions[picker]
end

local function key(item) return item.file or table.concat({ item.repo or '', item.type or '', item.number or item.text }, ':') end

local function remember(state, items)
  for _, item in ipairs(items or {}) do
    local id = key(item)
    if not state.seen[id] then
      state.seen[id] = true
      state.items[#state.items + 1] = item
    end
  end
end

local function matches(items, query, opts)
  if query == '' then return items end
  local matcher = require('snacks.picker.core.matcher').new(opts.matcher)
  matcher:init(query)
  local result = {}
  for index, item in ipairs(items or {}) do
    local score = matcher:match { text = item.text }
    if score > 0 then result[#result + 1] = { item = item, score = score, index = index } end
  end
  table.sort(result, function(a, b) return a.score == b.score and a.index < b.index or a.score > b.score end)
  return vim.tbl_map(function(entry) return entry.item end, result)
end

function M.transform(picker, filter)
  local query = picker.opts.live and filter.search or filter.pattern
  -- Changing search reruns the finder, even in local mode. Keep the actual
  -- input untouched; GitHub results can match body text absent from the title.
  filter.search = (picker.opts.live and 'remote:' or 'local:') .. query
  -- The finder matches and ranks cached items itself. Applying the query again
  -- here would discard GitHub's body matches and search qualifiers.
  filter.pattern = ''
end

function M.finder(opts, ctx)
  local state = session(ctx.picker)
  local query = ctx.filter.search:gsub('^[^:]+:', '')
  local live = opts.live
  local kind = opts.source == 'gh_issue' and 'issue' or 'pr'
  return function(cb)
    if ctx.async:aborted() then return end
    local function fetch(search)
      local result
      local request = vim.tbl_extend('force', {}, opts)
      request.limit = opts.gh_search_limit or 100
      request.search = search ~= '' and search or nil
      require('snacks.gh.api').list(kind, function(items) result = items end, request):wait()
      return result
    end

    local emitted = {}
    local function emit(items)
      for _, item in ipairs(items or {}) do
        local id = key(item)
        if not emitted[id] then
          emitted[id] = true
          -- Matcher bookkeeping belongs to this run, not to the cached item.
          local copy = setmetatable(vim.tbl_extend('force', {}, item), getmetatable(item))
          copy.match_tick, copy.match_topk = nil, nil
          cb(copy)
        end
      end
    end

    if not state.initial and not live then
      state.initial = fetch ''
      remember(state, state.initial)
    end
    if query == '' then
      emit(live and fetch '' or state.initial)
      return
    end

    if not live then emit(matches(state.items, query, opts)) end
    local items = state.searches[query]
    if not items then
      -- Render local matches during the debounce/network wait. Snacks normally
      -- holds a short result list until its asynchronous finder has finished.
      ctx.async:schedule(function()
        if not ctx.picker.closed then ctx.picker.list:unpause() end
      end)
      -- Snacks aborts this task when the query changes or the picker closes.
      ctx.async:sleep(350)
      items = fetch(query)
      state.searches[query] = items
      remember(state, items)
    end
    -- Append new results so arrival never reorders items under the cursor.
    emit(items)
  end
end

return M
