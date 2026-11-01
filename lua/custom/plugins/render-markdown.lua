---@module 'lazy'
---@type LazySpec
return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    init = function()
      vim.api.nvim_create_user_command('MarkdownRender', function()
        if vim.bo.filetype ~= 'markdown' then return vim.notify('Open a Markdown note first.', vim.log.levels.INFO) end
        require('custom.markdown.document').new(vim.api.nvim_get_current_buf()):update(true)
      end, { desc = 'Refresh the retained mathematical presentation for this note' })
      vim.api.nvim_create_user_command('MarkdownRenderStatus', function()
        local status = require('custom.markdown.document').status(vim.api.nvim_get_current_buf())
        vim.notify(status and vim.inspect(status) or 'No retained Markdown presentation is attached.', vim.log.levels.INFO)
      end, { desc = 'Show retained Markdown rendering readiness' })
      vim.api.nvim_create_user_command('MarkdownMathTable', function() require('custom.markdown.table_preview').open() end, {
        desc = 'Preview current table with native text and per-cell equation images',
      })
    end,
    config = function(_, opts)
      require('custom.markdown.tables').setup()
      require('render-markdown').setup(opts)
    end,
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      -- Each retained-table ownership change needs a completed host render.
      -- The host's leading-edge throttle can otherwise drop the final request.
      debounce = 0,
      on = {
        attach = function(ctx) require('custom.markdown.reading').attach(ctx.buf) end,
        render = function(ctx)
          require('custom.markdown.reading').apply_window(ctx.win)
          require('custom.markdown.tables').on_render(ctx)
        end,
        clear = function(ctx)
          require('custom.markdown.reading').apply_window(ctx.win)
          require('custom.markdown.tables').on_clear(ctx)
        end,
      },
      custom_handlers = {
        markdown = { parse = function(ctx) return require('custom.markdown.tables').parse('markdown', ctx) end },
        markdown_inline = { parse = function(ctx) return require('custom.markdown.tables').parse('markdown_inline', ctx) end },
        html = { parse = function(ctx) return require('custom.markdown.tables').parse('html', ctx) end },
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
