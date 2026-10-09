---@module 'lazy'
---@type LazySpec
return {
  {
    'dimtion/guttermarks.nvim',
    event = { 'BufReadPost', 'BufNewFile', 'BufWritePre', 'FileType' },
    cmd = 'GutterMarks',
    opts = {
      local_mark = { enabled = true },
      global_mark = { enabled = true },
      special_mark = { enabled = false },
    },
    keys = {
      { '<leader>mn', function() require('guttermarks.actions').next_buf_mark() end, desc = 'Next mark in buffer' },
      { '<leader>mp', function() require('guttermarks.actions').prev_buf_mark() end, desc = 'Previous mark in buffer' },
      { '<leader>md', function() require('guttermarks.actions').delete_mark() end, desc = 'Delete letter marks on current line' },
      {
        '<leader>mq',
        function()
          require('guttermarks.actions').marks_to_quickfix()
          vim.cmd.copen()
        end,
        desc = 'Send marks to quickfix',
      },
      { '<leader>mt', '<cmd>GutterMarks toggle<CR>', desc = 'Toggle mark signs' },
      { '<leader>Tm', '<cmd>GutterMarks toggle<CR>', desc = '[T]oggle [M]ark signs' },
    },
  },
}
