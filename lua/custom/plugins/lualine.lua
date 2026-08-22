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
          color = { fg = color },
        }
      end

      require('lualine').setup {
        options = {
          theme = 'catppuccin-mocha',
          icons_enabled = vim.g.have_nerd_font,
          section_separators = '',
          component_separators = '|',
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'branch', 'diff', 'diagnostics' },
          lualine_c = { 'filename' },
          lualine_x = {
            -- `mode` is the noice-specific.
            noice_status('mode', '#fab387'),
            noice_status('command', '#f9e2af'),
            noice_status('search', '#89b4fa'),
            'filetype',
          },
          lualine_y = { 'progress' },
          lualine_z = { { 'location', fmt = function() return '%2l:%-2v' end } },
        },
      }
    end,
  },
}
