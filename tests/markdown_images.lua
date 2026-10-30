-- Run with: nvim --headless -n -u NONE -i NONE -l tests/markdown_images.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local resolve = require('custom.markdown_images').resolve
local root = vim.fn.tempname()
local vault = root .. '/Second Brain Vault'
local note = vault .. '/Learning/RL/cs285/FlowMatching.md'
local function write(path)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile({ 'fixture' }, path)
  return path
end

local ok, err = pcall(function()
  vim.fn.mkdir(vault .. '/.obsidian', 'p')
  write(note)
  local pasted = write(vault .. '/Pasted image 20261030095354.png')
  assert(resolve(note, 'Pasted image 20261030095354.png') == pasted, 'vault-root embed was not resolved')
  local attachment = write(vault .. '/Attachments/diagrams/nested.png')
  write(vault .. '/.obsidian/plugins/nested.png')
  write(vault .. '/.git/objects/nested.png')
  assert(resolve(note, 'nested.png') == attachment, 'filename-only attachment was not resolved')
  assert(resolve(note, 'diagrams/nested.png') == attachment, 'partial attachment path was not resolved')
  assert(resolve(note, 'Attachments/diagrams/nested.png') == attachment)
  local local_image = write(vim.fs.dirname(note) .. '/nested.png')
  assert(resolve(note, 'nested.png') == local_image, 'note-relative image should take precedence')
  vim.fn.delete(local_image)
  write(vault .. '/Other/nested.png')
  assert(resolve(note, 'nested.png') == nil, 'ambiguous attachment should not select a random file')
  assert(resolve(note, 'diagrams/nested.png') == attachment, 'folder-qualified link should disambiguate')
  assert(resolve(note, 'missing.png') == nil)
  assert(resolve(note, 'https://example.com/nested.png') == nil)
  assert(resolve(note, attachment) == nil, 'absolute paths should use Snacks defaults')
  assert(resolve(write(root .. '/outside/note.md'), 'nested.png') == nil, 'non-vault Markdown should use Snacks defaults')
  local other = root .. '/Other Vault'
  vim.fn.mkdir(other .. '/.obsidian', 'p')
  local other_note = write(other .. '/note.md')
  assert(resolve(other_note, 'Pasted image 20261030095354.png') == nil, 'lookup escaped its vault')
end)
vim.fn.delete(root, 'rf')
assert(ok, err)
print 'Markdown vault image resolution checks passed'
