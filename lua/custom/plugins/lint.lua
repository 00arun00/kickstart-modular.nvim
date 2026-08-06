---@module 'lazy'
---@type LazySpec
return {
  {
    -- Replaces `kickstart.plugins.lint`, which stays commented out in
    -- `lazy-plugins.lua`. Same structure as upstream, with `markdownlint-cli2`
    -- instead of `markdownlint`: it is the maintained CLI, picks up
    -- `.markdownlint-cli2.*` config files and supports `--fix`.
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'

      lint.linters_by_ft = {
        markdown = { 'markdownlint-cli2' },
      }

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only lint modifiable buffers, so the markdown used to render LSP
          -- hover popups does not get linted.
          if vim.bo.modifiable then lint.try_lint() end
        end,
      })
    end,
  },
}
