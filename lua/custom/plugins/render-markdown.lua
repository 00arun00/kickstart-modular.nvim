---@module 'lazy'
---@type LazySpec
return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    init = function()
      vim.api.nvim_create_user_command('MarkdownMathTable', function() require('custom.markdown_table_preview').open() end, {
        desc = 'Preview current table with native text and per-cell equation images',
      })
    end,
    config = function(_, opts)
      require('custom.markdown_tables').setup()
      require('render-markdown').setup(opts)
    end,
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      on = {
        attach = function(ctx) require('custom.markdown_reading').attach(ctx.buf) end,
        render = function(ctx) require('custom.markdown_reading').apply_window(ctx.win) end,
        clear = function(ctx) require('custom.markdown_reading').apply_window(ctx.win) end,
      },
      custom_handlers = {
        markdown = { parse = function(ctx) return require('custom.markdown_tables').parse('markdown', ctx) end },
        markdown_inline = { parse = function(ctx) return require('custom.markdown_tables').parse('markdown_inline', ctx) end },
        html = { parse = function(ctx) return require('custom.markdown_tables').parse('html', ctx) end },
      },
      -- Color only the icons: no scope_highlight on the task text.
      checkbox = {
        unchecked = { icon = '󰄱 ', highlight = 'MarkdownTaskPending' },
        checked = { icon = '󰄲 ', highlight = 'MarkdownTaskDone' },
        custom = {
          todo = { raw = '[-]', rendered = '󰦖 ', highlight = 'MarkdownTaskActive' },
          partial = { raw = '[/]', rendered = '󰪡 ', highlight = 'MarkdownTaskActive' },
          quarter = { raw = '[1]', rendered = '󰪟 ', highlight = 'MarkdownTaskQuarter' },
          half = { raw = '[2]', rendered = '󰪡 ', highlight = 'MarkdownTaskHalf' },
          three_quarters = { raw = '[3]', rendered = '󰪣 ', highlight = 'MarkdownTaskThreeQuarters' },
          deferred = { raw = '[>]', rendered = '󰃰 ', highlight = 'MarkdownTaskDeferred' },
          blocked = { raw = '[!]', rendered = '󰍁 ', highlight = 'MarkdownTaskBlocked' },
          question = { raw = '[?]', rendered = '󰆆 ', highlight = 'MarkdownTaskQuestion' },
          cancelled = { raw = '[~]', rendered = '󰅚 ', highlight = 'MarkdownTaskPending' },
        },
      },
      -- Rendering latex here would need `pylatexenc` and only produces unicode
      -- approximations. Math is left to `snacks.nvim`, which renders it as an
      -- actual image, so keeping this off avoids rendering formulas twice.
      latex = { enabled = false },
      code = {
        -- Leave mermaid blocks alone so `snacks.nvim` can render the diagram.
        --
        -- `conceal_delimiters` hides the ``` fence lines, and snacks anchors a
        -- diagram's virtual lines to the closing fence. Virtual lines on a
        -- concealed line never render, so the diagram stayed invisible until
        -- the cursor landed on that line and anti-conceal revealed it again.
        disable = { 'mermaid' },
      },
    },
  },
}
