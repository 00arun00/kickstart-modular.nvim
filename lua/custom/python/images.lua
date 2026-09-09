local M = {}

function M.status()
  for _, arg in ipairs(vim.v.argv) do
    if arg == '--headless' then return false, 'Headless session: use external plots' end
  end
  if vim.fn.executable 'magick' ~= 1 then return false, 'ImageMagick missing: brew install imagemagick' end
  local terminal = (vim.env.TERM_PROGRAM or '') .. ' ' .. (vim.env.TERM or '')
  if vim.env.TMUX then terminal = terminal .. ' ' .. vim.fn.system { 'tmux', 'display-message', '-p', '#{client_termname}' } end
  if not (terminal:lower():find('ghostty', 1, true) or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.KITTY_WINDOW_ID) then
    return false, 'Inline images require Ghostty or Kitty; Space j p opens plots externally'
  end
  return true, 'Snacks plot renderer selected; :checkhealth snacks checks terminal support'
end

function M.enabled() return (M.status()) end

-- Molten's bundled adapter keys by file path, so inline/float placements collide,
-- and clear_all passes records instead of IDs. Keep the compatibility fix here.
function M.setup()
  package.preload['load_snacks_nvim'] = function() return { snacks_api = require 'custom.python.snacks_canvas' } end
  vim.g.molten_image_provider = M.enabled() and 'snacks.nvim' or 'none'
  vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('python-snacks-cleanup', { clear = true }),
    pattern = 'MoltenDeinitPost',
    callback = function()
      -- Molten removes the kernel from its registry after this event returns.
      vim.schedule(function()
        if package.loaded['custom.python.snacks_canvas'] and #vim.fn.MoltenRunningKernels() == 0 then require('custom.python.snacks_canvas').clear_all() end
      end)
    end,
  })
end

return M
