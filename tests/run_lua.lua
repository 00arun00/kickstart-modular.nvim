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
MiniTest.execute(cases, { reporter = MiniTest.gen_reporter.stdout { quit_on_finish = true } })
-- -l exits when the chunk returns; mini.test schedules cases asynchronously.
vim.wait(2147483647, function() return not MiniTest.is_executing() end, 10)
