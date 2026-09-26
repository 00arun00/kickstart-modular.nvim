-- autopairs
-- https://github.com/windwp/nvim-autopairs

---@module 'lazy'
---@type LazySpec
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  -- Let the normal indenter handle Enter; keep bracket and quote pairing.
  opts = { map_cr = false },
}
