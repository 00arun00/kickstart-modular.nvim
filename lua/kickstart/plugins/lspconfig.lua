-- LSP Plugins
---@module 'lazy'
---@type LazySpec
return {
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      -- Mason must be loaded before its dependents so we need to set it up here.
      -- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
      {
        'mason-org/mason.nvim',
        ---@module 'mason.settings'
        ---@type MasonSettings
        ---@diagnostic disable-next-line: missing-fields
        opts = {},
      },
      -- Maps LSP server names between nvim-lspconfig and Mason package names.
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      { 'j-hui/fidget.nvim', opts = {} },
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('grn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method('textDocument/documentHighlight', event.buf) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client:supports_method('textDocument/inlayHint', event.buf) then
            map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --  See `:help lsp-config` for information about keys and how to configure
      ---@type table<string, vim.lsp.Config>
      local servers = {
        -- clangd = {},
        -- gopls = {},
        -- rust_analyzer = {},
        --
        -- Some languages (like typescript) have entire language plugins that can be useful:
        --    https://github.com/pmizio/typescript-tools.nvim
        --
        -- But for many setups, the LSP (`ts_ls`) will work just fine
        -- ts_ls = {},

        stylua = {}, -- Used to format Lua code

        -- Python type checking, completion and navigation. A `pyright` fork
        -- with inlay hints and stricter inference enabled, which upstream
        -- reserves for Pylance. Linting and formatting belong to `ruff` below.
        basedpyright = {
          -- The interpreter has to be resolved per project root, so it is set
          -- here rather than statically. See `custom/python/venv.lua`.
          --
          -- `python.pythonPath` is deliberately not one of basedpyright's
          -- "discouraged" settings, so unlike the `analysis.*` options below it
          -- still applies in projects that ship their own config file.
          --
          -- NOTE: this has to mutate `client.settings`, not `config.settings`
          -- via `before_init`. The client captures a reference to the settings
          -- table when it is created, so reassigning `config.settings` later
          -- leaves the client pointing at the original table and the value is
          -- silently dropped. Same `on_init` shape `lua_ls` uses below.
          on_init = function(client)
            client.settings = vim.tbl_deep_extend('force', client.settings or {}, {
              python = { pythonPath = require('custom.python.venv').python(client.root_dir or assert(vim.uv.cwd())) },
            })
          end,
          settings = {
            basedpyright = {
              -- Everything under `analysis` is a "discouraged" language server
              -- setting: basedpyright ignores it outright when the project has
              -- a `[tool.basedpyright]` section or a `pyrightconfig.json`.
              -- These are therefore defaults for projects that have not
              -- decided, not policy imposed on ones that have.
              analysis = {
                -- `recommended` enables every rule at error severity, which is
                -- unusable on an existing untyped codebase. `standard` matches
                -- pyright's baseline; raise it per project in `pyproject.toml`.
                typeCheckingMode = 'standard',
                diagnosticSeverityOverrides = {
                  -- ruff reports these (F401/F841) *with* autofixes attached,
                  -- so let it own them rather than showing each twice.
                  reportUnusedImport = 'none',
                  reportUnusedVariable = 'none',
                },
              },
            },
          },
        },

        -- Lint diagnostics and code actions - `gra` to autofix a violation or
        -- organise imports. Formatting goes through conform, see `conform.lua`.
        ruff = {
          -- `cmd` as a function runs a different ruff per project: a repo that
          -- pins ruff in its dev-dependencies is linted by that exact version,
          -- so the editor and CI agree. Falls back to the mason-installed one.
          cmd = function(dispatchers, config)
            local ruff = require('custom.python.venv').ruff(config.root_dir or assert(vim.uv.cwd()))
            return vim.lsp.rpc.start({ ruff, 'server' }, dispatchers)
          end,
          -- basedpyright owns hover. Without this both servers answer and the
          -- popup renders the same symbol twice.
          on_attach = function(client) client.server_capabilities.hoverProvider = false end,
        },

        -- PKM language server for markdown: wiki/markdown link completion,
        -- go to definition, backlinks, and rename that updates every link to a
        -- file or heading. Attaches on `.git`, `.obsidian` or `.moxide.toml`,
        -- so it works in plain repos as well as vaults.
        markdown_oxide = {},

        -- Grammar, spelling and style diagnostics for prose, with per-issue
        -- code actions (`gra`) to correct a word or add it to the dictionary.
        -- Runs locally, no network. It lints code comments in many languages
        -- by default, which is noisy in source files, so it is scoped to prose
        -- here - widen `filetypes` if it turns out to be useful elsewhere.
        harper_ls = {
          filetypes = { 'markdown', 'gitcommit' },
        },

        -- Special Lua Config, as recommended by neovim help docs
        lua_ls = {
          on_init = function(client)
            client.server_capabilities.documentFormattingProvider = false -- Disable formatting (formatting is done by stylua)

            if client.workspace_folders then
              local path = client.workspace_folders[1].name
              if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
            end

            client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
              runtime = {
                version = 'LuaJIT',
                path = { 'lua/?.lua', 'lua/?/init.lua' },
              },
              workspace = {
                checkThirdParty = false,
                -- NOTE: this is a lot slower and will cause issues when working on your own configuration.
                --  See https://github.com/neovim/nvim-lspconfig/issues/3189
                library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
                  '${3rd}/luv/library',
                  '${3rd}/busted/library',
                }),
              },
            })
          end,
          ---@type lspconfig.settings.lua_ls
          settings = {
            Lua = {
              format = { enable = false }, -- Disable formatting (formatting is done by stylua)
            },
          },
        },
      }

      -- Ensure the servers and tools above are installed
      --
      -- To check the current status of installed tools and/or manually install
      -- other tools, you can run
      --    :Mason
      --
      -- You can press `g?` for help in this menu.
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        -- You can add other tools here that you want Mason to install
        'prettier', -- Used to format markdown, see `conform.lua`
        'markdownlint-cli2', -- Used to lint markdown, see `custom/plugins/lint.lua`
      })

      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      for name, server in pairs(servers) do
        vim.lsp.config(name, server)
        vim.lsp.enable(name)
      end
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
