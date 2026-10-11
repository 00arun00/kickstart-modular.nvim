-- Run with: nvim --headless -n -u NONE -i NONE -l tests/gh_search.lua
-- Uses installed Snacks with mocked GitHub responses; no network requests.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.showmode = false
local root = vim.env.NVIM_TEST_PLUGIN_ROOT or (vim.fn.stdpath 'data' .. '/lazy')
assert(vim.fn.isdirectory(root .. '/snacks.nvim') == 1, 'Missing test dependency: snacks.nvim')
vim.opt.rtp:append(root .. '/snacks.nvim')
vim.o.columns = 140
vim.o.lines = 50
require('snacks').setup(dofile('lua/custom/plugins/snacks.lua')[1].opts)
local calls, release, initial, responses
local function item(id, text) return { file = 'gh://test/repo/issue/' .. id, text = text, number = id } end
require('snacks.gh.api').list = function(kind, cb, opts)
  calls[#calls + 1] = { kind = kind, search = opts.search, state = opts.state, limit = opts.limit }
  return {
    wait = function()
      if opts.search then
        while not release[opts.search] do
          require('snacks.picker.util.async').sleep(5)
        end
        cb(responses[opts.search])
      else
        cb(initial)
      end
    end,
  }
end
local function wait_for(fn, msg) assert(vim.wait(2500, fn, 5), msg) end
local function settle(p)
  wait_for(function() return not p.finder:running() and not p.matcher.task:running() end, 'finder stuck')
end
local function query(p, q)
  p.input.filter.pattern = q
  p:find { refresh = false }
end
local function visible(p, text)
  if not p.list.win:buf_valid() then return false end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(p.list.win.buf, 0, -1, false)) do
    if line:find(text, 1, true) then return true end
  end
end
for _, source in ipairs { 'gh_issue', 'gh_pr' } do
  calls = {}
  release = {}
  responses = {}
  initial = { item(1, 'Trouble first'), item(2, 'Trouble second'), item(3, 'Something unrelated') }
  local p = Snacks.picker(source, { preview = false, format = 'text', state = 'all' })
  settle(p)
  wait_for(function() return p.shown end, 'picker not shown')
  assert(#calls == 1 and calls[1].limit == 100 and calls[1].state == 'all')
  assert(calls[1].kind == (source == 'gh_issue' and 'issue' or 'pr'))
  responses.TROUBLE = { item(1, 'Trouble first'), item(4, 'Body-only GitHub hit') }
  query(p, 'TROUBLE')
  wait_for(function() return p.list:count() == 2 and visible(p, 'Trouble second') end, 'local matches not displayed during background search')
  assert(#calls == 1, 'request not debounced')
  p.list:move(2, true, true)
  p.list:select(p:current())
  local selected = p:current().file
  local win = vim.api.nvim_get_current_win()
  wait_for(function() return #calls == 2 end, 'GitHub not searched despite local matches')
  assert(p.finder:running() and p:current().file == selected)
  release.TROUBLE = true
  settle(p)
  assert(p.list:count() == 3, 'merge failed or duplicate retained')
  assert(p:current().file == selected and p.list:is_selected(p:current()), 'selection jumped')
  assert(vim.api.nvim_get_current_win() == win, 'focus changed')
  wait_for(function() return visible(p, 'Body-only GitHub hit') end, 'remote body match hidden')
  query(p, '')
  settle(p)
  assert(p.list:count() == 3 and p.list:get(3).file == initial[3].file and #calls == 2, 'initial list not restored')
  query(p, 'TROUBLE')
  settle(p)
  assert(#calls == 2 and p.list:count() == 3, 'repeat query not cached')
  -- Previously fetched remote items are available locally for subsequent queries.
  responses['Body-only'] = {}
  release['Body-only'] = true
  query(p, 'Body-only')
  wait_for(function() return p.list:count() == 1 and visible(p, 'Body-only') end, 'remote results not reused locally')
  assert(#calls == 2)
  settle(p)
  assert(#calls == 3)
  -- Abort both a pending debounce and an in-flight request.
  query(p, 'obsolete')
  query(p, 'inflight')
  wait_for(function() return #calls == 4 end, 'in-flight fixture not started')
  assert(calls[4].search == 'inflight')
  responses.inflight = { item(5, 'Stale response') }
  responses.latest = { item(6, 'Latest response') }
  release.latest = true
  query(p, 'latest')
  release.inflight = true
  settle(p)
  assert(#calls == 5 and p.list:count() == 1 and p:current().file == responses.latest[1].file, 'stale result leaked')
  -- Successful empty responses are cached; failures can be retried.
  responses.missing = {}
  release.missing = true
  query(p, 'missing')
  settle(p)
  assert(p.list:count() == 0 and #calls == 6)
  query(p, '')
  settle(p)
  query(p, 'missing')
  settle(p)
  assert(#calls == 6)
  release.failure = true
  query(p, 'failure')
  settle(p)
  assert(#calls == 7)
  query(p, '')
  settle(p)
  query(p, 'failure')
  settle(p)
  assert(#calls == 8, 'failure cached')
  -- The request limit must not cap the merged result list.
  initial = {}
  for i = 1, 100 do
    initial[i] = item(i, 'Bulk local ' .. i)
  end
  query(p, '')
  settle(p)
  p:refresh()
  settle(p)
  responses.Bulk = {}
  for i = 101, 200 do
    responses.Bulk[#responses.Bulk + 1] = item(i, 'Bulk remote ' .. i)
  end
  release.Bulk = true
  query(p, 'Bulk')
  settle(p)
  assert(p.list:count() == 200, 'merged results truncated to request limit')
  assert(calls[#calls].limit == 100)
  -- Explicit live mode excludes local-only hits.
  p.opts.live = true
  p.input.filter.search = 'Bulk'
  p:find { refresh = false }
  settle(p)
  assert(p.list:count() == 100, 'live mode did not use only GitHub results')
  p.opts.live = false
  query(p, 'cancel-on-close')
  if source == 'gh_issue' then wait_for(function() return p.finder.task._suspended end, 'debounce not started') end
  local count = #calls
  p:close()
  vim.wait(450, function() return false end, 10)
  assert(#calls == count, 'closed picker sent request')
end
assert(vim.v.errmsg == '', vim.v.errmsg)
print 'PASS: issue/PR immediate local display, background fetch, deduplication, cursor/multi-selection/focus, cache, clear, debounce/in-flight cancellation, errors, refresh, >100 merged results, live mode, close'
vim.cmd 'qa!'
