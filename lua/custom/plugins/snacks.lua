---@module 'lazy'
---@type LazySpec
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    config = function(_, opts)
      require('snacks').setup(opts)
      require('custom.markdown_reading').setup_snacks()
    end,
    ---@module 'snacks'
    ---@type snacks.Config
    opts = {
      gh = {},
      picker = {
        enabled = true,
        -- Telescope continues to own shared selection menus and search mappings.
        ui_select = false,
        sources = {
          -- Show cached matches immediately, then search GitHub after a pause.
          -- Ctrl+g in the input still switches to explicit GitHub search.
          gh_issue = {
            on_show = function(picker) require('custom.navigation.gh_search').setup(picker) end,
            on_close = function(picker) require('custom.navigation.gh_search').close(picker) end,
            finder = function(opts, ctx) return require('custom.navigation.gh_search').finder(opts, ctx) end,
            filter = { transform = function(picker, filter) require('custom.navigation.gh_search').transform(picker, filter) end },
            live = false,
            -- Limit each GitHub request, not the merged local/remote list.
            gh_search_limit = 100,
            limit = math.huge,
            limit_live = math.huge,
            matcher = { ignorecase = true, smartcase = false },
          },
          gh_pr = {
            on_show = function(picker) require('custom.navigation.gh_search').setup(picker) end,
            on_close = function(picker) require('custom.navigation.gh_search').close(picker) end,
            finder = function(opts, ctx) return require('custom.navigation.gh_search').finder(opts, ctx) end,
            filter = { transform = function(picker, filter) require('custom.navigation.gh_search').transform(picker, filter) end },
            live = false,
            gh_search_limit = 100,
            limit = math.huge,
            limit_live = math.huge,
            matcher = { ignorecase = true, smartcase = false },
          },
        },
        win = {
          input = {
            keys = {
              ['<c-t>'] = false,
              ['<a-t>'] = { 'tab', mode = { 'n', 'i' } },
            },
          },
          list = {
            keys = {
              ['<c-t>'] = false,
              ['<a-t>'] = 'tab',
            },
          },
        },
      },

      -- Renders images, mermaid diagrams and latex math inline using the kitty
      -- graphics protocol, which ghostty supports natively.
      -- Requires `imagemagick`. Latex math in markdown is compiled as a real
      -- latex document and rasterized through a pdf, so it needs both
      -- `tectonic` (or `pdflatex`) and `ghostscript`. `typst` is not involved:
      -- it only handles typst source files. Mermaid additionally needs `mmdc`.
      -- Run `:checkhealth snacks` to see which converters are missing.
      image = {
        enabled = true,
        resolve = function(file, src) return require('custom.markdown_images').resolve(file, src) end,
        doc = {
          auto_resize = true,
          on_update_pre = function(placement) require('custom.markdown_math').prepare(placement) end,
          -- Conceal charts as well as math, so a mermaid diagram is rendered
          -- in place of its source and the source returns when the cursor
          -- moves into it.
          --
          -- This truncated diagrams on the first attempt, but that was caused
          -- by render-markdown concealing the ``` fence lines: virtual lines
          -- anchored to a concealed line never render. It now skips mermaid
          -- blocks entirely (`code.disable`), so the fences stay real.
          --
          -- Image links are left unconcealed so `![alt](path)` stays readable.
          ---@param _ string tree-sitter language
          ---@param type snacks.image.Type
          conceal = function(_, type) return type == 'math' or type == 'chart' end,
        },
      },

      lazygit = {
        configure = true,
      },

      -- Other Snacks features are opt-in; GitHub uses its dedicated picker.
      notifier = { enabled = true },
    },
    keys = {
      { '<leader>Ss', function() require('custom.navigation.scratch').choose() end, desc = 'Scratch: choose scope' },
      { '<leader>Sb', function() require('custom.navigation.scratch').toggle 'branch' end, desc = 'Scratch: current branch' },
      { '<leader>Sp', function() require('custom.navigation.scratch').toggle 'project' end, desc = 'Scratch: current project' },
      { '<leader>Sg', function() require('custom.navigation.scratch').toggle 'global' end, desc = 'Scratch: global' },
      { '<leader>Sf', function() require('custom.navigation.scratch').find() end, desc = 'Scratch: find saved notes' },
      { '<leader>gi', function() Snacks.picker.gh_issue() end, desc = 'GitHub Issues (Open)' },
      { '<leader>gI', function() Snacks.picker.gh_issue { state = 'all' } end, desc = 'GitHub Issues (All)' },
      { '<leader>gp', function() Snacks.picker.gh_pr() end, desc = 'GitHub Pull Requests (Open)' },
      { '<leader>gP', function() Snacks.picker.gh_pr { state = 'all' } end, desc = 'GitHub Pull Requests (All)' },
      {
        '<leader>gb',
        function() require('custom.navigation.blame').snacks() end,
        desc = 'Git Blame Line History (Snacks)',
      },
      { '<leader>gB', function() require('custom.navigation.blame').gitsigns(false) end, desc = 'Git Blame File (Gitsigns)' },
      { '<leader>TB', function() require('custom.navigation.blame').gitsigns(true) end, desc = 'Toggle Git Blame File (Gitsigns)' },
      { '<leader>gg', function() require('custom.navigation.lazygit').open() end, desc = 'Toggle Lazygit' },
      { '<leader>gf', function() require('custom.navigation.lazygit').open(true) end, desc = 'LazyGit Current File History' },
    },
  },
}
