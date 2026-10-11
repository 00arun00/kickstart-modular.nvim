-- LazyGit supplies the selected SHA; its process cwd identifies the repository.
local server, sha, action = arg[1], arg[2], arg[3]
assert(server and server ~= '', 'Missing Neovim server')
assert(sha and sha:match '^%x+$' and (#sha == 40 or #sha == 64), 'Select a commit first')
assert(action == 'commit' or action == 'pr', 'Invalid browser action')
local channel = vim.fn.sockconnect('pipe', server, { rpc = true })
assert(channel > 0, 'Could not connect to Neovim')
vim.rpcrequest(
  channel,
  'nvim_exec_lua',
  [[
  local sha, root, pr = ...
  vim.schedule(function()
    require('custom.navigation.blame').from_lazygit(sha, root, pr)
  end)
]],
  { sha, vim.fn.getcwd(), action == 'pr' }
)
vim.fn.chanclose(channel)
