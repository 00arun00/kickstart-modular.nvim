-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

---@module 'lazy'
---@type LazySpec
return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    {
      '\\',
      function()
        local command = require 'neo-tree.command'
        -- Focus an existing sidebar without changing its source or selection.
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype == 'neo-tree' and vim.b[buf].neo_tree_position == 'left' then
            vim.api.nvim_set_current_win(win)
            return
          end
        end
        command.execute { source = 'filesystem', position = 'left', reveal = true }
      end,
      desc = 'Explorer: focus / reveal current file',
    },
  },
  ---@module 'neo-tree'
  ---@type neotree.Config
  opts = {
    popup_border_style = 'rounded',
    source_selector = {
      winbar = true,
      content_layout = 'center',
      sources = {
        { source = 'filesystem', display_name = 'Files' },
        { source = 'buffers', display_name = 'Buffers' },
        { source = 'git_status', display_name = 'Git' },
      },
      separator = ' ',
    },
    window = {
      width = 36,
      mappings = {
        ['\\'] = 'close_window',
      },
    },
    default_component_configs = {
      indent = {
        with_expanders = true,
        expander_collapsed = '',
        expander_expanded = '',
      },
      name = { use_git_status_colors = false },
      modified = { symbol = '●' }, -- Unsaved buffer, distinct from Git's M.
      git_status = {
        symbols = {
          added = 'A',
          modified = 'M',
          deleted = 'D',
          renamed = 'R',
          untracked = '?',
          ignored = '◌',
          unstaged = '', -- Change type already conveys the useful information.
          staged = '✓',
          conflict = '!',
        },
      },
      file_size = { enabled = false },
      type = { enabled = false },
      last_modified = { enabled = false },
      created = { enabled = false },
    },
    filesystem = {
      -- Reveal on demand; do not rearrange the tree as editor buffers change.
      follow_current_file = { enabled = false },
      hijack_netrw_behavior = 'disabled', -- Oil owns directory editing on `-`.
      filtered_items = {
        hide_dotfiles = false,
        hide_gitignored = true,
        hide_by_name = { '.git', '.DS_Store', 'thumbs.db', '__pycache__' },
        show_hidden_count = false,
      },
    },
    buffers = { follow_current_file = { enabled = false } },
  },
}
