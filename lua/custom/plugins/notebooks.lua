return {
  {
    'goerz/jupytext.nvim',
    lazy = false, -- Must intercept the first .ipynb read, including CLI arguments.
    opts = function()
      return {
        jupytext = require('custom.python.host').executable 'jupytext',
        format = function(_, metadata)
          local language = (metadata.kernelspec or {}).language or (metadata.language_info or {}).name or 'python'
          -- Other kernels remain editable as JSON; never relabel them as Python.
          vim.b.jupytext_format = language == 'python' and 'py:percent' or 'ipynb'
          vim.b.jupytext_filetype = language == 'python' and 'python' or 'json'
          return vim.b.jupytext_format
        end,
        update = true,
        async_write = false, -- :write must complete before output export or :wq.
        handle_url_schemes = false,
      }
    end,
    config = function(_, opts)
      if vim.fn.executable(opts.jupytext) ~= 1 then
        vim.notify('Notebook conversion unavailable: run bash scripts/setup-python.sh and restart Neovim', vim.log.levels.WARN)
        return
      end
      require('jupytext').setup(opts)
    end,
  },
  {
    'benlubas/molten-nvim',
    build = ':UpdateRemotePlugins',
    lazy = false,
    init = function()
      require 'custom.python.notebook'
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_enter_output_behavior = 'open_then_enter' -- The output helper validates before focusing.
      vim.g.molten_virt_text_max_lines = 16
      vim.g.molten_output_win_max_height = 24
      vim.g.molten_output_win_max_width = 120
      vim.g.molten_output_win_style = 'minimal'
      vim.g.molten_output_win_border = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' }
      vim.g.molten_output_win_cover_gutter = false
      vim.g.molten_output_show_more = true
      vim.g.molten_use_border_highlights = true
      vim.g.molten_wrap_output = false -- Keep tables aligned; gw toggles wrapping inside output.
      vim.g.molten_tick_rate = 200
      local function highlights()
        vim.api.nvim_set_hl(0, 'MoltenOutputBorderSuccess', { link = 'DiagnosticOk' })
        vim.api.nvim_set_hl(0, 'MoltenOutputBorderFail', { link = 'DiagnosticError' })
      end
      highlights()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('python-output-colors', { clear = true }),
        callback = highlights,
      })
      -- Text works in any terminal. Rich HTML/images can be opened externally.
      vim.g.molten_image_provider = 'none'
    end,
    keys = {
      { '<leader>ji', function() require('custom.python.notebook').init() end, desc = 'Notebook: initialize project kernel' },
      { '<leader>jl', '<cmd>MoltenEvaluateLine<cr>', desc = 'Notebook: run line' },
      { '<leader>jv', ':<C-u>MoltenEvaluateVisual<cr>gv', mode = 'x', desc = 'Notebook: run selection' },
      { '<leader>jo', function() require('custom.python.output').preview() end, desc = 'Notebook: show output' },
      { '<leader>je', function() require('custom.python.output').enter() end, desc = 'Notebook: enter output' },
      { '<leader>jO', function() require('custom.python.output').inspect() end, desc = 'Notebook: inspect full output in split' },
      { '<leader>jy', '<cmd>MoltenYankOutput!<cr>', desc = 'Notebook: copy output to clipboard' },
      { '<leader>jh', function() require('custom.python.output').hide() end, desc = 'Notebook: hide output' },
      { '<leader>jx', '<cmd>MoltenInterrupt<cr>', desc = 'Notebook: interrupt' },
      { '<leader>jr', function() require('custom.python.notebook').restart() end, desc = 'Notebook: restart kernel' },
      { '<leader>jq', '<cmd>MoltenDeinit<cr>', desc = 'Notebook: stop kernel' },
      { '<leader>js', function() require('custom.python.notebook').export() end, desc = 'Notebook: save with outputs' },
      { '<leader>jI', function() require('custom.python.notebook').import() end, desc = 'Notebook: import saved outputs' },
      { '<leader>jb', '<cmd>MoltenOpenInBrowser<cr>', desc = 'Notebook: open HTML output' },
      { '<leader>jp', '<cmd>MoltenImagePopup<cr>', desc = 'Notebook: open plot' },
    },
  },
  {
    'GCBallesteros/NotebookNavigator.nvim',
    ft = 'python',
    dependencies = { 'benlubas/molten-nvim' },
    opts = { repl_provider = 'molten', syntax_highlight = true },
    keys = {
      { ']n', function() require('notebook-navigator').move_cell 'd' end, desc = 'Next notebook cell', ft = 'python' },
      { '[n', function() require('notebook-navigator').move_cell 'u' end, desc = 'Previous notebook cell', ft = 'python' },
      { '<leader>jc', function() require('custom.python.notebook').run() end, desc = 'Notebook: run cell', ft = 'python' },
      { '<leader>jn', function() require('custom.python.notebook').run(false, true) end, desc = 'Notebook: run cell and advance', ft = 'python' },
      { '<leader>ja', function() require('custom.python.notebook').run(true) end, desc = 'Notebook: run all cells', ft = 'python' },
      { '<leader>jN', function() require('notebook-navigator').add_cell_below() end, desc = 'Notebook: add cell below', ft = 'python' },
    },
  },
  {
    'lewis6991/gitsigns.nvim',
    opts = function(_, opts)
      local attach = opts.on_attach
      opts.on_attach = function(buf)
        if vim.api.nvim_buf_get_name(buf):match '%.ipynb$' then return false end
        if attach then return attach(buf) end
      end
    end,
  },
  {
    'stevearc/conform.nvim',
    opts = function(_, opts)
      -- The buffer is Python, but its filename still ends in .ipynb. Otherwise
      -- Ruff tries to parse this percent script as JSON, including range format.
      for _, name in ipairs { 'ruff_format', 'ruff_organize_imports' } do
        opts.formatters[name].append_args = { '--extension', 'ipynb:python' }
      end
    end,
  },
  {
    'folke/which-key.nvim',
    opts = function(_, opts) vim.list_extend(opts.spec, { { '<leader>j', group = 'notebook' }, { '<leader>p', group = 'python' } }) end,
  },
}
