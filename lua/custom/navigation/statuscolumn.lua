local M = {}

function M.setup()
  local builtin = require 'statuscol.builtin'
  require('statuscol').setup {
    relculright = true,
    segments = {
      { sign = { namespace = { '^gutter_marks$' }, maxwidth = 1, colwidth = 1, auto = true } },
      {
        sign = { namespace = { '^gitsigns' }, maxwidth = 1, colwidth = 1, auto = true },
        click = 'v:lua.ScSa',
      },
      { text = { builtin.foldfunc }, condition = { function(args) return vim.wo[args.win].foldenable end }, click = 'v:lua.ScFa' },
      {
        -- The wildcard excludes signs claimed by the dedicated segments above.
        -- DAP uses priority 21; diagnostics use 10-13. Future test signs should
        -- use a lower priority to keep breakpoints and diagnostics visible.
        sign = { name = { '.*' }, namespace = { '.*' }, maxwidth = 1, colwidth = 1, auto = true },
        click = 'v:lua.ScSa',
      },
      { text = { builtin.lnumfunc, ' ' }, click = 'v:lua.ScLa' },
    },
  }

  local expression = "%{%v:lua.require('statuscol').get_statuscol_string()%}"
  local excluded = { oil = true, ['neo-tree'] = true, help = true, lazy = true, mason = true, projecthome = true }
  local function update()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local editor = vim.bo[buf].buftype == '' and not excluded[vim.bo[buf].filetype] and vim.api.nvim_win_get_config(win).relative == ''
      local value = editor and expression or ''
      if vim.wo[win].statuscolumn ~= value then vim.wo[win].statuscolumn = value end
      -- Native auto fold columns still reserve space with 'nofoldenable'.
      if editor then
        if not vim.wo[win].foldenable and vim.wo[win].foldcolumn ~= '0' then
          vim.w[win].statuscolumn_foldcolumn = vim.wo[win].foldcolumn
          vim.wo[win].foldcolumn = '0'
        elseif vim.wo[win].foldenable and vim.w[win].statuscolumn_foldcolumn then
          vim.wo[win].foldcolumn = vim.w[win].statuscolumn_foldcolumn
          vim.w[win].statuscolumn_foldcolumn = nil
        end
      end
    end
  end
  local group = vim.api.nvim_create_augroup('CustomStatusColumn', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'WinNew', 'FileType' }, { group = group, callback = update })
  vim.api.nvim_create_autocmd('OptionSet', { group = group, pattern = { 'buftype', 'foldenable' }, callback = update })
  update()
end

return M
