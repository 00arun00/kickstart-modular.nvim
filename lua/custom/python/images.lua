local M = {}

function M.status()
  for _, arg in ipairs(vim.v.argv) do
    if arg == '--headless' then return false, 'Headless session: use external plots' end
  end
  if vim.fn.executable 'magick' ~= 1 then return false, 'ImageMagick missing: brew install imagemagick' end
  local terminal = (vim.env.TERM_PROGRAM or '') .. ' ' .. (vim.env.TERM or '')
  if vim.env.TMUX then
    terminal = terminal .. ' ' .. vim.fn.system { 'tmux', 'display-message', '-p', '#{client_termname}' }
    local passthrough = vim.trim(vim.fn.system { 'tmux', 'show', '-Apv', 'allow-passthrough' })
    if passthrough ~= 'on' and passthrough ~= 'all' then return false, 'tmux passthrough disabled: source scripts/tmux-images.conf in tmux' end
  end
  if not (terminal:lower():find('ghostty', 1, true) or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.KITTY_WINDOW_ID) then
    return false, 'Inline images require Ghostty or Kitty; Space j p opens plots externally'
  end
  return true, 'Inline plots enabled (image.nvim / Kitty graphics)'
end

function M.enabled() return (M.status()) end

function M.options()
  return {
    backend = 'kitty',
    processor = 'magick_cli',
    max_width = 100,
    max_height = 20,
    max_width_window_percentage = math.huge,
    max_height_window_percentage = math.huge,
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', '' },
    tmux_show_only_in_active_window = true,
    hijack_file_patterns = {},
    integrations = {
      markdown = { enabled = false },
      asciidoc = { enabled = false },
      typst = { enabled = false },
      neorg = { enabled = false },
      syslang = { enabled = false },
    },
  }
end

return M
