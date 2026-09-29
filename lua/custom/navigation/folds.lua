local M = {}
local options

function M.setup(opts)
  options = vim.deepcopy(opts)
  require('origami').setup(options)
end

-- Origami anchors its suffix after the original header. Align summaries where
-- they fit, leaving the code intact in narrow windows or with long headers.
function M.padding(win, foldstart, suffix_width)
  local info = vim.fn.getwininfo(win)[1]
  if not info then return 2 end
  local line = vim.api.nvim_buf_get_lines(info.bufnr, foldstart - 1, foldstart, false)[1] or ''
  local header_width = math.max(0, vim.fn.virtcol { foldstart, #line } - info.leftcol)
  return math.max(2, info.width - info.textoff - header_width - suffix_width - 1)
end

local function normal_buffer()
  if vim.bo.buftype == '' then return true end
  vim.notify('Fold actions are available in editing buffers.', vim.log.levels.INFO)
  return false
end

function M.focus()
  if not normal_buffer() then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.cmd 'normal! zM'
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.cmd 'normal! zvzz'
end

function M.preview()
  if not normal_buffer() then return end
  local first = vim.fn.foldclosed '.'
  if first == -1 then
    vim.notify('Place the cursor on a closed fold to preview it.', vim.log.levels.INFO)
    return
  end
  local last = vim.fn.foldclosedend '.'
  local source = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(source, first - 1, last, false)
  local filetype = vim.bo[source].filetype
  local buf, win = vim.lsp.util.open_floating_preview(lines, filetype, {
    border = 'rounded',
    title = (' Fold: lines %d–%d '):format(first, last),
    title_pos = 'center',
    focus_id = 'custom_fold_preview',
    max_width = math.min(100, math.floor(vim.o.columns * 0.8)),
    max_height = math.min(24, math.floor(vim.o.lines * 0.6)),
    wrap = false,
  })
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].signcolumn = 'no'
  -- Reuse the language's highlights without firing its FileType/LSP hooks on
  -- this read-only copy. A second invocation focuses it for normal scrolling.
  local language = vim.treesitter.language.get_lang(filetype)
  if language then pcall(vim.treesitter.start, buf, language) end
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true, desc = 'Close fold preview' })
end

function M.toggle_git()
  options.foldtext.gitsignsCount = not options.foldtext.gitsignsCount
  require('origami').setup(options)
  vim.cmd 'redraw!'
  vim.notify('Fold Git counts: ' .. (options.foldtext.gitsignsCount and 'on' or 'off'), vim.log.levels.INFO)
end

return M
