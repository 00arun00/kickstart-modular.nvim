local M = {}

-- Snacks already parses Obsidian image embeds. Resolve their paths inside the
-- nearest vault instead of depending on Neovim's working directory.
function M.resolve(file, src)
  if src:match '^%a[%w+.-]*://' or vim.startswith(src, '/') then return end
  local dir = vim.fs.dirname(file)
  local vault = dir and vim.fs.root(dir, '.obsidian')
  if not vault then return end

  -- Preserve explicit note-relative links before trying vault-relative paths.
  for _, base in ipairs { dir, vault } do
    local path = vim.fs.normalize(base .. '/' .. src)
    if vim.fn.filereadable(path) == 1 then return path end
  end

  -- Obsidian also permits just a filename (or partial folder path) for an
  -- attachment elsewhere in the vault. Never choose an arbitrary duplicate.
  local suffix = '/' .. src
  local found
  for name, kind in
    vim.fs.dir(vault, {
      depth = math.huge,
      skip = function(path) return vim.fs.basename(path) ~= '.obsidian' and vim.fs.basename(path) ~= '.git' end,
    })
  do
    if kind == 'file' and vim.endswith('/' .. name, suffix) then
      if found then return end
      found = vault .. '/' .. name
    end
  end
  return found
end

return M
