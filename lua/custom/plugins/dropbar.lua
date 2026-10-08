---@module 'lazy'
---@type LazySpec
return {
  {
    'Bekaboo/dropbar.nvim',
    lazy = false, -- Dropbar manages its own attachment lifecycle.
    dependencies = {
      'nvim-tree/nvim-web-devicons',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    opts = function()
      local sources = require 'dropbar.sources'
      local utils = require 'dropbar.utils'
      local notebook = require 'custom.navigation.notebook'
      local function activate(child)
        local menu = utils.menu.get_current()
        if not menu then return end
        local row = vim.api.nvim_win_get_cursor(menu.win)[1]
        local entry = menu.entries[row]
        if not entry then return end
        local component = entry.components[child and 1 or #entry.components]
        if component and component.on_click then menu:click_on(component) end
      end
      return {
        bar = {
          enable = function(buf, win)
            if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then return false end
            if vim.bo[buf].buftype ~= '' or vim.bo[buf].filetype == 'help' or vim.api.nvim_win_get_config(win).relative ~= '' then return false end
            local name = vim.api.nvim_buf_get_name(buf)
            if name == '' then return false end
            -- Saved notebook images can make JSON huge while editable text is small.
            return vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) <= 1024 * 1024
          end,
          sources = function(buf)
            if notebook.is_notebook(buf) then return { sources.path, notebook } end
            if vim.bo[buf].filetype == 'markdown' then return { sources.path, sources.markdown } end
            return { sources.path, utils.source.fallback { sources.lsp, sources.treesitter } }
          end,
        },
        menu = {
          preview = true,
          win_configs = { border = 'rounded' },
          keymaps = {
            ['<CR>'] = function() activate(false) end,
            ['l'] = function() activate(true) end,
            ['h'] = '<C-w>q',
            ['/'] = function() require('dropbar.api').fuzzy_find_toggle() end,
          },
        },
        fzf = {
          fuzzy_find_on_click = false, -- j/k/Enter first; i or / starts search.
          keymaps = { ['<CR>'] = function() require('dropbar.api').fuzzy_find_click(-1) end },
        },
        sources = {
          path = {
            max_depth = 3,
            preview = false, -- Hovering directory entries must not load arbitrary files.
          },
        },
      }
    end,
    config = function(_, opts)
      require('dropbar').setup(opts)
      require('custom.navigation.dropbar').setup()
      local function highlights()
        -- PmenuSel's bright background washes out the colored cell labels.
        vim.api.nvim_set_hl(0, 'DropBarMenuCurrentContext', { link = 'Visual' })
        vim.api.nvim_set_hl(0, 'DropBarMenuHoverEntry', { link = 'Visual' })
      end
      highlights()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('custom-dropbar-colors', { clear = true }),
        callback = highlights,
      })
    end,
    keys = {
      { '<leader>;', function() require('dropbar.api').pick() end, desc = 'Breadcrumb: pick component' },
      { '<leader>.', function() require('dropbar.api').select_next_context() end, desc = 'Breadcrumb: current context menu' },
      { '[;', function() require('dropbar.api').goto_context_start() end, desc = 'Breadcrumb: context start / parent' },
      { '];', function() require('dropbar.api').select_next_context() end, desc = 'Breadcrumb: browse current context' },
      { '<leader>jC', function() require('custom.navigation.notebook').pick_cells() end, desc = 'Notebook: browse all cells' },
    },
  },
}
