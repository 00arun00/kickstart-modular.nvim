# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repo identity

Personal Neovim config, forked from [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim) (which is itself a multi-file fork of `nvim-lua/kickstart.nvim`). It is a *starting-point* config the user owns and edits, **not** a distribution. Upstream merges are common — recent commits include several `Merge upstream:` entries — so changes should be made with merge friendliness in mind.

## Common commands

- `stylua .` — format all Lua (uses `.stylua.toml`: 2-space indent, single-quote preference, 160 col, no parens on bare calls).
- `stylua --check .` — lint check; same command CI runs (`.github/workflows/stylua.yml`, gated to upstream only).
- Inside Neovim:
  - `:Lazy` — plugin status; `:Lazy update` / `:Lazy sync` to update.
  - `:Mason` — language-server / tool installer UI. Servers listed in the `servers` table in `lua/kickstart/plugins/lspconfig.lua` are auto-installed via `mason-tool-installer`.
  - `:checkhealth` — runs the kickstart health check in `lua/kickstart/health.lua` (verifies Neovim ≥ 0.11 and presence of `git`, `make`, `unzip`, `rg`).
  - `<leader>f` — format buffer via `conform.nvim` (`<leader>` is space).

## Architecture

Entry point is `init.lua`, which sets the leader key + `vim.g.have_nerd_font` and then `require`s four modules in order:

1. `lua/options.lua` — `vim.o` / `vim.opt` settings.
2. `lua/keymaps.lua` — global keymaps and the `TextYankPost` highlight autocmd. **LSP keymaps live elsewhere** — they're set inside the `LspAttach` callback in `lua/kickstart/plugins/lspconfig.lua`.
3. `lua/lazy-bootstrap.lua` — clones `folke/lazy.nvim` into `stdpath('data')/lazy/lazy.nvim` if missing and prepends it to `rtp`.
4. `lua/lazy-plugins.lua` — calls `require('lazy').setup{...}` with the plugin spec.

### Plugin layout: `kickstart/` vs `custom/`

This is the most important convention to understand:

- `lua/kickstart/plugins/*.lua` — upstream-tracked plugin specs. Each returns a `LazySpec` table. They are **enabled one-by-one** by explicit `require 'kickstart.plugins.<name>'` lines in `lua/lazy-plugins.lua`. To toggle an upstream plugin, comment/uncomment its line there (e.g. `kickstart.plugins.debug`, `lint`, `autopairs`, `neo-tree`, `indent_line` are shipped but disabled by default).
- `lua/custom/plugins/*.lua` — user plugins. Auto-imported in bulk via `{ import = 'custom.plugins' }` at the bottom of `lazy-plugins.lua`. **Drop a new `*.lua` here that returns a `LazySpec` and it loads automatically — no edit to `lazy-plugins.lua` required.** This is the merge-conflict-free zone for personal additions.

When the user already has an upstream plugin enabled and wants to override it, the pattern is to **comment out the `kickstart.plugins.X` line in `lazy-plugins.lua`** and add a replacement in `custom/plugins/`. Live example: `tokyonight` is commented out and replaced by `custom/plugins/catppuccin.lua`.

### LSP / formatter / completion plumbing

- LSP servers are declared as a `servers` table inside `lua/kickstart/plugins/lspconfig.lua`. The keys of that table feed both `vim.lsp.config` + `vim.lsp.enable` **and** `mason-tool-installer`'s `ensure_installed`. Adding a server = adding a key to that table.
- `lua_ls` is configured to **disable its own formatting** because formatting is owned by `stylua` via `conform.nvim`. Preserve this split when touching either file.
- `conform.nvim` (`lua/kickstart/plugins/conform.lua`) handles formatting. **Format-on-save is opt-in per filetype** via the `enabled_filetypes` table inside `format_on_save` — currently everything is commented out, so format-on-save is effectively off and `<leader>f` is the trigger. External formatters go in `formatters_by_ft`.
- Completion is `blink-cmp` (kickstart-default), not `nvim-cmp`.

### Local files Lazy ignores

`.gitignore` excludes `lazy-lock.json` (upstream policy to avoid merge churn). The lockfile *is* checked in here; if the user wants to track it long-term they may eventually want that line removed from `.gitignore`.
