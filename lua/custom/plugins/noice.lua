---@module 'lazy'
---@type LazySpec
return {
  {
    -- Replaces the UI for `messages`, `cmdline` and the `popupmenu`.
    --
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
      -- Rendering primitives.
      'MunifTanjim/nui.nvim',
      -- Backend for the `notify` view. `noice` checks
      'folke/snacks.nvim',
    },
    ---@module 'noice'
    ---@type NoiceConfig
    opts = {
      cmdline = {
        enabled = true,
        -- [alt] `cmdline` classic bottom position.
        view = 'cmdline_popup',
      },

      messages = {
        enabled = true,
      },

      popupmenu = {
        enabled = true,
        backend = 'nui',
      },

      lsp = {
        -- `fidget.nvim` (a dependency of `nvim-lspconfig`) already owns LSP
        -- progress. Leaving both on renders every progress message twice.
        progress = { enabled = false },

        -- `blink.cmp` has `signature = { enabled = true }` and positions its
        -- window relative to the completion menu, which noice cannot see.
        signature = { enabled = false },

        hover = { enabled = true },
        message = { enabled = true },

        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
        },
      },

      presets = {
        -- Keep `/` at the bottom of the screen.
        bottom_search = true,
        -- Position the cmdline and popupmenu together as one palette.
        command_palette = true,
        -- Send long messages to a split instead of an oversized notification.
        long_message_to_split = true,
        -- Requires `inc-rename.nvim`, which is not installed.
        inc_rename = false,
        -- Borders on hover and signature help, to match the catppuccin theme.
        lsp_doc_border = true,
      },
    },
    keys = {
      { '<leader>nh', '<cmd>Noice history<cr>', desc = '[N]oice [H]istory' },
      { '<leader>nl', '<cmd>Noice last<cr>', desc = '[N]oice [L]ast message' },
      { '<leader>nd', '<cmd>Noice dismiss<cr>', desc = '[N]oice [D]ismiss all' },
      {
        -- Scroll long hover docs and signature help. Returns `false` when no
        -- noice window is open, so the normal page-scroll behaviour of these
        -- keys still works everywhere else.
        '<c-f>',
        function()
          if not require('noice.lsp').scroll(4) then return '<c-f>' end
        end,
        silent = true,
        expr = true,
        desc = 'Scroll forward',
        mode = { 'i', 'n', 's' },
      },
      {
        '<c-b>',
        function()
          if not require('noice.lsp').scroll(-4) then return '<c-b>' end
        end,
        silent = true,
        expr = true,
        desc = 'Scroll backward',
        mode = { 'i', 'n', 's' },
      },
    },
  },
}
-- vim: ts=2 sts=2 sw=2 et
