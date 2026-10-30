---@module 'lazy'
---@type LazySpec
return {
  {
    -- Replaces `mini.statusline`
    --
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      ---@param kind 'mode'|'command'|'search'
      ---@param color string
      local function noice_status(kind, color)
        return {
          function()
            local ok, noice = pcall(require, 'noice')
            return ok and noice.api.status[kind].get() or ''
          end,
          cond = function()
            local ok, noice = pcall(require, 'noice')
            return ok and noice.api.status[kind].has()
          end,
          color = function() return { fg = require('custom.theme').palette()[color] } end,
        }
      end

      require('lualine').setup {
        options = {
          theme = 'auto',
          icons_enabled = vim.g.have_nerd_font,
          section_separators = '',
          component_separators = '|',
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = {
            'branch',
            'diff',
            'diagnostics',
          },
          lualine_c = { 'filename' },
          lualine_x = {
            {
              function() return '  ' .. (require('custom.markdown_reading').is_enabled() and 'on' or 'off') end,
              cond = function() return vim.bo.filetype == 'markdown' end,
            },
            -- `mode` is the noice-specific.
            noice_status('mode', 'peach'),
            noice_status('command', 'yellow'),
            noice_status('search', 'blue'),
            'filetype',
          },
          lualine_y = { 'progress' },
          lualine_z = { { 'location', fmt = function() return '%2l:%-2v' end } },
        },
      }
      vim.api.nvim_create_autocmd('User', {
        group = vim.api.nvim_create_augroup('lualine-markdown-reading', { clear = true }),
        pattern = 'MarkdownReadingChanged',
        callback = function() require('lualine').refresh { place = { 'statusline' } } end,
      })
    end,
  },
}
