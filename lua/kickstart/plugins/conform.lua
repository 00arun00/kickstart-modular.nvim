---@module 'lazy'
---@type LazySpec
return {
  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function() require('conform').format { async = true } end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    ---@module 'conform'
    ---@type conform.setupOpts
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- You can specify filetypes to autoformat on save here:
        local enabled_filetypes = {
          -- lua = true,
          -- python = true,
        }
        if enabled_filetypes[vim.bo[bufnr].filetype] then
          return { timeout_ms = 500 }
        else
          return nil
        end
      end,
      default_format_opts = {
        lsp_format = 'fallback', -- Use external formatters if configured below, otherwise use LSP formatting. Set to `false` to disable LSP formatting entirely.
      },
      -- You can also specify external formatters in here.
      formatters_by_ft = {
        -- Prettier handles the GFM this config actually uses - tables, task
        -- lists, footnotes and yaml frontmatter - none of which is CommonMark.
        -- `proseWrap` defaults to `preserve`, so paragraphs are not rewrapped.
        markdown = { 'prettier' },
        -- ruff replaces both black (formatting) and isort (import sorting),
        -- and is fast enough that two passes are imperceptible. The ruff *LSP*
        -- owns diagnostics and code actions, see `lspconfig.lua`; formatting
        -- stays here so `<leader>f` remains the single formatting entry point
        -- across every filetype.
        python = { 'ruff_organize_imports', 'ruff_format' },
        -- rust = { 'rustfmt' },
        --
        -- You can use 'stop_after_first' to run the first available formatter from the list
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
      },
      -- Same project-first resolution as the LSP, so a formatted file matches
      -- what CI's ruff would produce rather than whatever mason last installed.
      formatters = {
        ruff_format = { command = function(_, ctx) return require('custom.python.venv').ruff(ctx.dirname) end },
        ruff_organize_imports = { command = function(_, ctx) return require('custom.python.venv').ruff(ctx.dirname) end },
      },
    },
  },
}
-- vim: ts=2 sts=2 sw=2 et
