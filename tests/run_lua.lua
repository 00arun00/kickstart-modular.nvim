vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.fn.getcwd() .. '/.test-deps/mini.nvim')
require('mini.test').setup()
local cases = MiniTest.collect {
  find_files = function() return vim.fn.glob('tests/lua/test_*.lua', false, true) end,
  filter_cases = function(case)
    if not case.desc[1]:match 'test_scripts%.lua$' and vim.env.NVIM_TEST_SUITE ~= 'fast' and vim.env.NVIM_TEST_SUITE ~= 'all' then return false end
    return table.concat(case.desc, ' '):find(vim.env.NVIM_TEST_MATCH or '', 1, true) ~= nil
  end,
}
assert(#cases > 0, 'No Lua tests matched')
local reporter = MiniTest.gen_reporter.stdout { quit_on_finish = true }
local update, finish = reporter.update, reporter.finish
local started, durations, skipped = {}, {}, {}
local skip = MiniTest.skip
MiniTest.skip = function(message)
  skipped[MiniTest.current.case] = true
  return skip(message)
end
reporter.update = function(index)
  local now = vim.uv.hrtime()
  started[index] = started[index] or now
  durations[index] = (now - started[index]) / 1e9
  update(index)
end
reporter.finish = function()
  local results = {}
  for index, case in ipairs(cases) do
    local exec = case.exec or { fails = {}, notes = {} }
    results[#results + 1] = {
      name = table.concat(case.desc, ' / '),
      status = #exec.fails > 0 and 'failed' or skipped[case] and 'skipped' or not case.exec and 'skipped' or 'passed',
      seconds = durations[index] or 0,
      detail = table.concat(exec.fails, '\n'),
    }
  end
  vim.fn.writefile({ vim.json.encode(results) }, vim.env.NVIM_TEST_RUN_DIR .. '/lua.json')
  finish()
end
MiniTest.execute(cases, { reporter = reporter })
-- -l exits when the chunk returns; mini.test schedules cases asynchronously.
vim.wait(2147483647, function() return not MiniTest.is_executing() end, 10)
