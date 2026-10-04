-- Each existing script is a named mini.test case in a fresh Neovim process.
local T = MiniTest.new_set()
local manifest = vim.json.decode(table.concat(vim.fn.readfile 'tests/cases.json', '\n'))
for _, case in ipairs(manifest.cases) do
  if case.language == 'lua' and (vim.env.NVIM_TEST_SUITE == 'all' or case.suite == vim.env.NVIM_TEST_SUITE) then
    T[case.file] = function()
      local result = vim.system({ '.test-venv/bin/python', 'scripts/run-test-case.py', case.file }, { text = true }):wait((case.timeout + 15) * 1000)
      assert(result.code == 0, (result.stdout or '') .. (result.stderr or ''))
    end
  end
end
return T
