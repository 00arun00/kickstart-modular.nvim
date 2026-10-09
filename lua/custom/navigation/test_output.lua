-- Reuse native diagnostic popup placement and styling, while retaining
-- Neotest's terminal-rendered reports and its selection/output lifecycle.
return function(client)
  local output = require 'neotest.consumers.output'
  local open = output.open
  output.open = require('nio').create(function(opts)
    opts = vim.tbl_extend('force', {}, opts or {})
    if not opts.open_win then
      local tree, adapter
      if opts.position_id then
        tree, adapter = client:get_position(opts.position_id, opts)
      elseif not opts.last_run then
        tree, adapter = client:get_nearest(vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1] - 1, opts)
      end
      local result = tree and client:get_results(adapter)[tree:data().id]
      local status = result and result.status
      local highlights = { passed = 'DiagnosticOk', failed = 'DiagnosticError', skipped = 'DiagnosticWarn' }
      local highlight = highlights[status] or 'FloatBorder'
      local title = status and (status:sub(1, 1):upper() .. status:sub(2)) or 'Test output'
      opts.open_win = function(size)
        local border = {}
        for _, char in ipairs { '╭', '─', '╮', '│', '╯', '─', '╰', '│' } do
          border[#border + 1] = { char, highlight }
        end
        local width = math.min(size.width, math.floor(vim.o.columns * 0.6))
        local height = math.min(size.height, math.floor(vim.o.lines * 0.6))
        -- Keep Neotest's close-on-leave lifecycle, but use the same placement
        -- and window options builder as native diagnostic floats.
        local float = require('neotest.lib').ui.float.open {
          width = width,
          height = height,
          auto_close = opts.auto_close,
        }
        local win = float.win_id
        local placeholder = vim.api.nvim_win_get_buf(win)
        vim.bo[placeholder].bufhidden = 'wipe'
        vim.api.nvim_win_set_config(
          win,
          vim.lsp.util.make_floating_popup_options(width, height, {
            border = border,
            title = { { ' ' .. title .. ' ', highlight } },
            title_pos = 'left',
            focusable = true,
          })
        )
        vim.wo[win].winhighlight = 'Normal:NormalFloat'

        return win
      end
    end
    return open(opts)
  end, 1)
  return {}
end
