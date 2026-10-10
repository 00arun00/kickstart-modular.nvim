# Diagnostics and batch-fix workflows

This guide describes this configuration as inspected on 2026-09-10, with Neovim
0.12.2 and Mason's Ruff 0.16.4. A project can resolve a different Ruff version.
`<leader>` means **Space**. Commands beginning with `:` run inside Neovim;
`sh` blocks run in a terminal. Lua blocks explain where to run them.

The useful loop is:

```text
Collect → choose scope → filter/group → inspect → fix → rerun → review diff/test
```

You already have enough tools to do this. Start with Telescope to discover work,
quickfix to hold a deliberate batch, Ruff to automate mechanical Python fixes,
and LSP actions or manual edits for changes requiring judgment.

## Contents

- [What is installed and configured](#what-is-installed-and-configured)
- [The four layers](#the-four-layers)
- [Everyday navigation](#everyday-navigation)
- [Build a worklist](#build-a-worklist)
- [Filter and sort](#filter-and-sort)
- [Ruff project checks and fixes](#ruff-project-checks-and-fixes)
- [Batch edits in Neovim](#batch-edits-in-neovim)
- [Tests, Markdown, and Git](#tests-markdown-and-git)
- [Where Trouble fits](#where-trouble-fits)
- [Practice session](#practice-session)
- [Troubleshooting and references](#troubleshooting-and-references)

## What is installed and configured

These entries were checked against enabled specs, local plugin directories, Mason
executables, and installed runtime/plugin source. Installed does not mean attached
to every buffer; servers still need the right filetype, project, and executable.

| Component                      | Current role                                                    | Entry points                                              |
| ------------------------------ | --------------------------------------------------------------- | --------------------------------------------------------- |
| Neovim diagnostics             | Shared store/display for LSP, lint, and test diagnostics        | `[d`, `]d`, diagnostic Lua API                            |
| Quickfix and location lists    | Built-in navigable worklists and batch execution                | `:copen`, `:lopen`, `:cfdo`, `:lfdo`                      |
| Telescope + native fzf         | Search, preview, select, export results                         | `<Space>sd`, `<Space>sg`, `<Space>sw`                     |
| Ruff native LSP                | Python lint diagnostics and code actions                        | `gra`; server runs `ruff server`                          |
| basedpyright                   | Python types, completion, navigation, rename                    | `grn`, `grr`, `grd`, `K`                                  |
| Conform                        | Explicit formatting; Python import organization then formatting | `<Space>f`, `:ConformInfo`                                |
| nvim-lint + markdownlint-cli2  | Markdown structural/style diagnostics                           | Runs on buffer enter, after save, and leaving insert mode |
| Harper LSP                     | Prose grammar/spelling/style in Markdown and gitcommit          | Diagnostics and `gra`                                     |
| Codebook LSP                   | Spelling in Python, Lua, C++, and Rust comments, strings, and definitions | Diagnostics and `gra`                              |
| markdown-oxide LSP             | Markdown links, navigation, backlinks, rename                   | LSP navigation/rename in matching roots                   |
| lua_ls and StyLua              | Lua analysis and formatting capability                          | LSP diagnostics; see formatting caveat below              |
| neotest + neotest-python       | pytest/unittest runner, diagnostics, quickfix, output, summary           | `<Space>tn`, `<Space>tf`, `<Space>ts`                     |
| nvim-dap + Python/DAP UI       | Debug a failing test or script                                  | `<Space>td`, `<F5>`, `<Space>db`                          |
| Gitsigns                       | Review changes and turn hunks into a worklist                   | `<Space>hp`, `<Space>hq`, `<Space>hQ`                     |
| todo-comments                  | Find TODO/FIXME-style comments                                  | `:TodoQuickFix`, `:TodoLocList`, `:TodoTelescope`         |
| Mason + tool installer         | Install language servers and executables                        | `:Mason`                                                  |
| which-key                      | Discover mappings                                               | Pause after Space; `<Space>sk` searches mappings          |
| Noice, Fidget, Snacks notifier | Messages/progress presentation                                  | Useful for feedback; not a project diagnostic scan        |

**Trouble is not installed or configured.** Snacks is installed, but its picker
is not enabled; Telescope is your picker. There is no configured Python nvim-lint
pipeline: Ruff already supplies Python diagnostics through LSP.

### Configuration details that affect workflow

- Codebook is installed automatically through Mason (`:MasonInstall codebook`
  to install manually). It checks while typing and reports informational
  diagnostics. `<Space>Ts` or `:CodebookToggle` toggles Codebook for the whole
  session, stopping its servers when off and reattaching when on. It defaults
  to on each time Neovim starts; other language servers and Harper are unaffected.
  Use `gra` on a spelling diagnostic for corrections or dictionary
  actions. Use `grn` through a language server that supports rename when changing
  an identifier and its references; a spelling replacement is not a refactor.
- Codebook downloads dictionaries on first use, then checks locally. Project
  vocabulary lives in `codebook.toml` or `.codebook.toml`; its dictionary actions
  can add accepted words. C++ is explicitly enabled because the pinned
  nvim-lspconfig defaults omit `cpp`; upstream labels its C++ support as needing
  more testing. Harper continues to handle Markdown and commit messages.

- `<Space>q` calls `vim.diagnostic.setloclist()`. Its description says “Quickfix,”
  but it creates a **location list for the current window's buffer**.
- `<Space>sd` searches diagnostics currently known to Neovim. It does not launch
  a full-project check.
- basedpyright inherits `diagnosticMode = 'openFilesOnly'` from installed
  nvim-lspconfig. The config sets `standard` type checking and suppresses unused
  import/variable reports in favor of Ruff. Project basedpyright configuration
  can override these analysis defaults.
- Python `<Space>f` runs `ruff_organize_imports` then `ruff_format`. The installed
  Conform import formatter selects `I001`; it is not a general `ruff check --fix`.
  An unused import can therefore remain after formatting.
- Format-on-save is effectively off: the enabled-filetypes table is empty.
  `<Space>f` is asynchronous; wait for completion before saving.
- Markdown formatting uses Prettier. `lua_ls` formatting is disabled; there is
  no explicit `lua = { 'stylua' }` Conform entry. StyLua is enabled as a server,
  so Lua formatting depends on Conform's LSP fallback and an attached provider.
  Check `:ConformInfo` rather than assuming an external formatter is configured.
- Python LSP and Conform use the same resolver: project/override virtualenv's
  Ruff first, then Neovim's PATH, where Mason exposes its tools. `:PyVenvInfo`
  reports the actual interpreter and Ruff. A terminal may have a different PATH;
  `ruff` was not available on the inspected shell PATH even though Mason had it.
- Diagnostic floats open when jumping; insert-mode updates are off; warnings
  and errors are underlined. `severity_sort = true` affects diagnostic display,
  not the ordering of an arbitrary quickfix worklist.

## The four layers

| Layer            | What it contains                                     | How it changes                                   |
| ---------------- | ---------------------------------------------------- | ------------------------------------------------ |
| Producer         | Ruff, basedpyright, markdownlint, tests, `rg`        | Run/recompute checks                             |
| Diagnostic store | Structured diagnostics published to `vim.diagnostic` | Producers update it                              |
| Picker/view      | Telescope; optionally Trouble                        | Displays/searches an upstream source             |
| Worklist         | Quickfix or location list                            | Populated explicitly by a command or integration |

A diagnostic contains a location, message, severity, source, and often a rule
code. A quickfix entry holds a location and text; it need not be an error at all.
Search matches, references, Git hunks, and test failures can all be work items.

Exporting diagnostics captures the currently available results. It neither scans
unopened files nor attaches executable fixes to each row. `gra` asks an attached
LSP for actions at the current buffer position. Running it from the quickfix
window itself is not the same as running it in the source buffer.

Quickfix is shared across the Neovim session, with a history of lists. Location
lists belong to windows and have their own histories. Use quickfix for a project
batch; use a location list to work on a file without replacing the project list.

Both can become stale after edits. Rerun the producer to confirm what remains.
The history is a history of lists, not an undo history of source changes.

## Everyday navigation

| Task                               | Current shortcut/command            |
| ---------------------------------- | ----------------------------------- |
| Next/previous diagnostic in buffer | `]d` / `[d`                         |
| Diagnostic details here            | `:lua vim.diagnostic.open_float()`  |
| Current-buffer diagnostic list     | `<Space>q`                          |
| Search known diagnostics           | `<Space>sd`                         |
| Code action in source buffer       | `gra`                               |
| Semantic rename                    | `grn`                               |
| References / definition            | `grr` / `grd`                       |
| Format current buffer              | `<Space>f`, then save when finished |
| Open/close quickfix                | `:copen` / `:cclose`                |
| Next/previous quickfix item        | `:cnext` / `:cprevious`             |
| First/last quickfix item           | `:cfirst` / `:clast`                |
| Next/previous quickfix file        | `:cnfile` / `:cpfile`               |
| Open/close location list           | `:lopen` / `:lclose`                |
| Next/previous location item        | `:lnext` / `:lprevious`             |
| Quickfix history                   | `:chistory`, `:colder`, `:cnewer`   |
| Location-list history              | `:lhistory`, `:lolder`, `:lnewer`   |

Press Enter on a list entry to jump to the source. `<C-o>` returns through the
jump list. Start with explicit Ex navigation commands so you can distinguish the
two list types regardless of keymap changes.

For one issue: `]d` → read the float → `gra` → inspect the change → save → rerun
the relevant test. Formatting is a separate step when needed.

## Build a worklist

### Known diagnostics → quickfix

```vim
:lua vim.diagnostic.setqflist()
```

Errors only:

```vim
:lua vim.diagnostic.setqflist({ severity = vim.diagnostic.severity.ERROR })
```

Errors and warnings:

```vim
:lua vim.diagnostic.setqflist({ severity = { min = vim.diagnostic.severity.WARN } })
```

“All diagnostics” means all diagnostics in the editor's store, potentially from
multiple projects. Narrow by source/root when necessary. On this installed 0.12
runtime, repeated `setqflist` calls with the same title update that diagnostic
list. Do not rely on each invocation creating a new historical snapshot.

### Telescope → selected work

1. Open `<Space>sd`, `<Space>sg` (live grep), `<Space>sw` (word search), or `grr`.
2. Search and preview until the results match the task.
3. Use **Ctrl-q** to export the current results to quickfix.
4. For a hand-picked subset, mark entries with **Tab**, then use **Alt-q**.

These are the installed Telescope defaults: Ctrl-q sends all current results;
Alt-q sends marked selections. Ctrl-q does not mean “only the rows I marked.”
Use Telescope's insert-mode Ctrl-/ help if your terminal intercepts Alt-q.

To further inspect an existing worklist:

```vim
:Telescope quickfix
:Telescope loclist
```

Telescope ranks matches for discovery. That rank is not necessarily a useful
execution order for a batch; sort the exported worklist by file before file loops.

### Built-in search → quickfix

From the intended project directory (`:pwd` shows Neovim's current directory):

```vim
:vimgrep /\<old_name\>/gj **/*.py
:copen
```

This built-in search does not adopt ripgrep's ignore policy. For large repos,
Telescope's ripgrep-backed search usually gives a more useful initial scope.

You can also connect `:grep` to ripgrep for the session:

```vim
:set grepprg=rg\ --vimgrep\ --smart-case
:set grepformat=%f:%l:%c:%m
:grep! old_name src tests
:copen
```

`!` here suppresses jumping to the first result; it does not negate the search.
`:make!` below follows the same convention. These option assignments are session
changes, not additions already present in this config.

## Filter and sort

### Filter by filename or message

Load Neovim's bundled optional filter package once per session:

```vim
:packadd cfilter
:Cfilter /F401/
:Cfilter! /tests\//
```

The first keeps entries whose filename or text matches `F401`; the second excludes
matching entries. Patterns are Vim regular expressions. Use `:Lfilter` for location
lists. Filters create another list, so `:colder` returns to the preceding one.

An ordinary diagnostic export may omit its rule code from the text. If filtering
by `F401` unexpectedly finds nothing, use Ruff's CLI list below or the explicit
diagnostic conversion in the next section.

### Sort an existing list by file, line, column

Do not run `:sort` on the quickfix window's displayed text. Transform its items.
Put this Lua block in a scratch `.lua` file and run `:luafile %`:

```lua
local q = vim.fn.getqflist({ title = 0, items = 0 })
local items = vim.tbl_filter(function(i) return i.valid == 1 end, q.items)
table.sort(items, function(a, b)
  local af, bf = vim.fn.bufname(a.bufnr), vim.fn.bufname(b.bufnr)
  if af ~= bf then return af < bf end
  if a.lnum ~= b.lnum then return a.lnum < b.lnum end
  return a.col < b.col
end)
vim.fn.setqflist({}, ' ', { title = q.title .. ' [file order]', items = items })
vim.cmd.copen()
```

This creates a new list and drops unparsed/non-location rows. It preserves entry
fields, including any `user_data`. File ordering keeps each file's entries
together, which is important for efficient `:cfdo` traversal.

### Preserve source/code and prioritize severity

For diagnosis, severity → source/rule → file is often more useful than file order.
This optional scratch Lua block creates an explicitly sorted snapshot of known
diagnostics. It can filter Ruff alone by uncommenting the indicated line:

```lua
local items = {}
for _, d in ipairs(vim.diagnostic.get()) do
  -- if d.source ~= 'ruff' then goto continue end
  local item = vim.diagnostic.toqflist({ d })[1]
  item.text = ('[%s %s] %s'):format(d.source or '?', d.code or '', d.message)
  item.user_data = { severity = d.severity, source = d.source or '', code = tostring(d.code or '') }
  items[#items + 1] = item
  ::continue::
end
table.sort(items, function(a, b)
  local x, y = a.user_data, b.user_data
  if x.severity ~= y.severity then return x.severity < y.severity end
  if x.source ~= y.source then return x.source < y.source end
  if x.code ~= y.code then return x.code < y.code end
  local af, bf = vim.fn.bufname(a.bufnr), vim.fn.bufname(b.bufnr)
  if af ~= bf then return af < bf end
  if a.lnum ~= b.lnum then return a.lnum < b.lnum end
  return a.col < b.col
end)
vim.fn.setqflist({}, ' ', { title = 'Diagnostic triage snapshot', items = items })
vim.cmd.copen()
```

Inspect actual source names with `:lua vim.print(vim.diagnostic.get(0))` before
filtering. This sorts the **converted items**: sorting diagnostics first and then
passing the whole array to `toqflist` would lose that order in this runtime.
Use the file-order block before a file batch; severity grouping can scatter the
same file across the list.

## Ruff project checks and fixes

### Choose the executable and scope first

Open a Python source file and run `:PyVenvInfo`. Check `:pwd`; use `:cd` to move
to the intended project root if necessary. CLI commands operate on disk, so save
the buffers whose contents you want checked before running them.

The shell examples below use `uv run ruff` for projects that have Ruff as a dev
dependency. `uv run` can synchronize the environment. If you need the exact
executable already used by Neovim, substitute the path reported by `:PyVenvInfo`.
See [Python PDE](python-pde.md) for environment setup.

### Zero-plugin project scan → quickfix

Neovim ships a Ruff compiler adapter. Its inspected default includes `--preview`,
so set its parameters explicitly to avoid accidentally expanding project policy:

```vim
:let b:ruff_makeprg_params = ''
:compiler ruff
:lua vim.bo.makeprg = vim.fn.shellescape(require('custom.python.venv').ruff(vim.fn.getcwd())) .. ' check --no-fix --no-fix-only --output-format=concise'
:make! .
:copen
```

The compiler sets `errorformat`, the parser that turns command output into
locations. The custom `makeprg` chooses your resolved Ruff and guarantees a
read-only scan even if the project enables fixes by default. `:make! src tests`
narrows the scan. These settings remain on the buffer; another `:compiler`
command can replace them. Run subsequent `:make!` from that source buffer.

This is synchronous and may block on a big project. For a responsive alternative,
run the same Ruff binary in a terminal and redirect concise output to a temporary
file, then use `:cgetfile /absolute/path/to/ruff-output.txt` after `:compiler ruff`.
Keep Neovim's working directory aligned with relative paths in that output.

Concise output is convenient for ordinary `.py`/`.pyi` files. Notebook cell
locations need special handling; do not assume a CLI `.ipynb` location maps to
this configuration's Jupytext editing buffer. Use the notebook's live diagnostics
or explicitly check its Python representation.

### Batch by rule, then recheck the whole scope

Start by measuring the work, using project-enabled rules:

```sh
uv run ruff check --no-fix --no-fix-only --statistics .
```

Example: inspect and remove unused imports in `src/`:

```sh
uv run ruff check --select F401 --no-unsafe-fixes --diff src/
uv run ruff check --select F401 --fix --no-unsafe-fixes src/
uv run ruff check --no-fix --no-fix-only src/
```

`--select F401` explicitly chooses a rule, replacing normal selection for this
invocation. Use it for an intentional focused cleanup. `--extend-select` adds
rules to project selection. A quickfix `:Cfilter` does **not** constrain this
shell command: the explicit paths and rule flags do.

For project-wide mechanical cleanup after reviewing a preview:

```sh
uv run ruff check --no-unsafe-fixes --diff .
uv run ruff check --fix --no-unsafe-fixes .
uv run ruff format .
uv run ruff check --no-fix --no-fix-only .
uv run ruff format --check .
```

Ruff distinguishes safe and unsafe fixes; the commands explicitly exclude unsafe
fixes even if project configuration enables them. Project settings can also
reclassify fix safety. Unfixed findings can remain, so treat the final check as
the result, not merely the fact that `--fix` ran. See the
[Ruff linter documentation](https://docs.astral.sh/ruff/linter/).

After external edits, run `:checktime`, rerun the quickfix scan, and inspect
`git diff`. Resolve any modified-buffer conflict before writing over an externally
changed file. Avoid parallel editor and CLI edits to the same files.

### File-local Ruff actions

In an attached Python buffer, `gra` offers available fixes. To request Ruff's
file-level fix-all action explicitly:

```vim
:lua vim.lsp.buf.code_action({ context = { only = { 'source.fixAll.ruff' } }, apply = true })
```

For imports only, use `source.organizeImports.ruff`, or your existing `<Space>f`
pipeline. These are file-level requests, not a whole-project traversal; `apply`
automatically applies a single matching action, and may still prompt if multiple
actions match. See [Ruff editor features](https://docs.astral.sh/ruff/editors/features/).

Prefer one CLI invocation over hundreds of LSP requests for repository cleanup.
Use file-level actions when working with unsaved editor contents or inspecting
an individual finding.

## Batch edits in Neovim

### Choose the correct iteration unit

| Command          | Unit                                 | Good use                                          |
| ---------------- | ------------------------------------ | ------------------------------------------------- |
| `:cdo`           | Each valid quickfix entry            | A deliberate location-specific edit               |
| `:cfdo`          | Files traversed by the quickfix list | Whole-file substitution or formatting             |
| `:ldo` / `:lfdo` | Location-list entries / files        | Same operations on a window-local list            |
| `:argdo`         | Argument-list files                  | A separately chosen explicit file set             |
| `:bufdo`         | Listed buffers                       | Only when all listed buffers are truly the target |

Use a file-sorted list for `:cfdo`: its traversal advances via `:cnfile`, so a
file scattered across different groups can be revisited. A `%s` substitution
processes a whole file; pairing it with `:cdo` repeats it for every hit in that file.

### Search → select → substitute

1. `<Space>sg` searches `old_name`.
2. Export the intended results to quickfix, then filter unwanted paths.
3. Sort by file with the earlier block.
4. Run a confirming, whole-word replacement:

```vim
:cfdo %s/\<old_name\>/new_name/gce | update
```

`g` means every match on a line, `c` asks per replacement, and `e` ignores
“pattern not found” for files that no longer match. `:update` saves only modified
buffers. This replaces occurrences throughout each selected file, not only the
lines in quickfix. Use `grn` when renaming a language symbol: text replacement
does not understand scope, shadowing, strings, or comments.

Before any batch, inspect the current list title/count with `:chistory`, save
intentional existing work, and preview a representative change. Undo is per
buffer; one `u` does not roll back an entire multi-file operation.

### Format only the files in a worklist

After sorting by file, use synchronous formatting so the next file is not visited
before formatting finishes. This loop stops on a formatter error before saving
that buffer:

```vim
:cfdo lua require('conform').format({ async = false, timeout_ms = 5000 }, function(err) if err then error(err) end end); vim.cmd.update()
```

This uses each filetype's configured pipeline. It does not add missing formatters
or turn formatting into general lint fixing. File-size-dependent timeouts and
missing executables should be resolved with `:ConformInfo` before a large batch.

Avoid `:cdo lua vim.lsp.buf.code_action(...)` as a general fix-all loop. Requests
are asynchronous, actions depend on attached clients and context, and earlier
fixes invalidate later locations. Use the producer's batch CLI for that task.

### Manual fixes in a stable queue

For type errors or API changes, work file by file: `:cfirst`, Enter into source,
fix the cause, then `:cnfile`. Several diagnostics may share one cause. Recheck
after each logical group rather than mechanically editing every row. In a long
session, test runs or Git/search exports may activate another list; use
`:chistory` to return to the intended worklist.

## Tests, Markdown, and Git

### Failing test → diagnosis → debug → rerun

1. `<Space>tn` runs the nearest test; `<Space>tf` runs the test file.
2. `<Space>ts` shows summary; `<Space>to` shows the selected test's output.
3. `:copen` opens the failure worklist. The installed neotest defaults enable
   diagnostics and quickfix, but do not automatically open quickfix.
4. `<Space>td` debugs the nearest test; `<Space>db` sets a breakpoint.
5. `<Space>tl` reruns the last test. `<Space>ta` runs the project suite.

The adapter must be able to collect tests using the selected project interpreter
and its test runner. A failed
collection or missing dependency is different from an assertion failure; inspect
output before treating a result as a source-level fix. A test run can populate
quickfix even when you were previously using it for Ruff.

### Markdown cleanup

Use `<Space>sd` or `<Space>q` to inspect Markdown diagnostics. Identify the source:
markdownlint covers structure/style, Harper covers prose, and markdown-oxide
handles Markdown knowledge/navigation features. `gra` can offer Harper fixes;
nvim-lint diagnostics do not automatically provide LSP code actions.

`<Space>f` runs Prettier; it does not invoke markdownlint's fix mode. For a batch,
run your project's `markdownlint-cli2 --fix` command against explicit files or
globs, review the diff, and rerun lint. This executable is installed by Mason,
but a plain terminal command may need its full path or the project's package
runner. Configuration/glob policy should come from the Markdown project.

### Review exactly what changed

- `<Space>hp` previews a hunk; `<Space>hd` opens a diff against the index.
- `<Space>hq` sends current-file hunks to quickfix.
- `<Space>hQ` sends repository hunks to quickfix.
- `<Space>gg` opens Lazygit, if the external executable is available.

That gives another useful chain: batch fix → Git hunks → review → targeted tests.
Git hunks may include pre-existing changes, so compare with your starting state.
Creating the hunk worklist activates another quickfix list; use history to return
to the diagnostic list. Hunk-reset mappings discard changes, so use preview/diff
for the review step.

## Where Trouble fits

Trouble is an optional persistent view over diagnostics, LSP results, quickfix,
and location lists. It adds grouping, filtering, sorting, previews, and multiple
views. It does not run Ruff or make a filtered view into a batch fix automatically.
Its diagnostics view has the same underlying coverage limits as Neovim's store.

If you later choose to install it, this minimal spec belongs in
`lua/custom/plugins/trouble.lua`; this guide has not installed it:

```lua
return {
  'folke/trouble.nvim',
  cmd = 'Trouble',
  opts = {},
}
```

Then the documented commands are:

```vim
:Trouble diagnostics toggle
:Trouble diagnostics toggle filter.buf=0
:Trouble qflist toggle
:Trouble loclist toggle
```

Use Telescope to select a task, quickfix to store its actual scope, and Trouble
to keep a readable view visible. A Trouble display filter does not automatically
filter the underlying quickfix list consumed by `:cfdo`. Consult the
[Trouble documentation](https://github.com/folke/trouble.nvim) when configuring
custom grouping or keybindings.

## Practice session

In a disposable Python project with Ruff installed, save this as `practice.py`:

```python
import os

def double(value):
    return value*2
```

1. Open it and run `:PyVenvInfo` and `:checkhealth vim.lsp`.
2. Wait for Ruff to report the unused import. Jump with `]d` and read the source.
3. `<Space>q` opens the location list; return to source and compare `<Space>sd`.
4. Export Telescope's results with Ctrl-q. Check `:chistory` and `:copen`.
5. Run `<Space>f`, wait, then save. Observe formatting; the unused import remains.
6. On the unused import, use `gra` and choose its removal. Save.
7. Run the compiler-based Ruff scan from the project root. Its list should now
   be empty unless your project enables other relevant rules.
8. Inspect `git diff` if the practice directory is a Git repo.

Next, deliberately create the same issue in two files. Scan, filter `F401`,
preview `ruff check --select F401 --diff`, apply that rule to the intended paths,
reload, and rescan. This teaches both list navigation and actual batch scope.

## Troubleshooting and references

| Symptom                                 | Check                                                                                             |
| --------------------------------------- | ------------------------------------------------------------------------------------------------- |
| No diagnostics for unopened files       | Known diagnostics are not a project scan; run Ruff CLI or basedpyright CLI for project coverage   |
| `:cnext` ignores what `<Space>q` showed | That mapping created a location list; use `:lnext`                                                |
| Formatting leaves lint errors           | Python formatting selects import organization and layout, not all Ruff fixes                      |
| `gra` has no action                     | Jump into source; check attached LSP, diagnostic ownership, rule fixability, and current position |
| Editor and CI disagree                  | `:PyVenvInfo`, exact binary versions, project settings, working directory, saved vs unsaved text  |
| F401 is absent from exported list text  | Use the source/code snapshot or Ruff concise CLI output                                           |
| Parser creates unusable rows            | Check `:setlocal errorformat? makeprg?`; use concise output and the matching compiler             |
| Quickfix suddenly shows tests/hunks     | Another producer activated a list; inspect `:chistory`                                            |
| Old failures remain after fixes         | Rerun their producer; changing source does not recompute a CLI snapshot                           |
| Formatter appears to do nothing         | `:ConformInfo`; errors are not automatically notified by this config                              |
| Notebook diagnostics look different     | Inline text is hidden for `.ipynb`; signs, underlines, and jump floats remain                     |

Primary local configuration:

- [Diagnostic display and location-list mapping](../lua/keymaps.lua)
- [LSP servers and actions](../lua/kickstart/plugins/lspconfig.lua)
- [Telescope mappings](../lua/kickstart/plugins/telescope.lua)
- [Formatting pipelines](../lua/kickstart/plugins/conform.lua)
- [Markdown linting](../lua/custom/plugins/lint.lua)
- [Python environment resolution](../lua/custom/python/venv.lua)
- [Tests and debugging](../lua/custom/plugins/python-tools.lua)
- [Git hunk workflows](../lua/kickstart/plugins/gitsigns.lua)

Use local help for the installed version: `:help quickfix`, `:help location-list`,
`:help :cdo`, `:help :cfdo`, `:help cfilter-plugin`,
`:help vim.diagnostic.setqflist()`, `:help vim.diagnostic.toqflist()`,
`:help telescope.defaults.mappings`, and `:help conform.format`.
The online [Neovim quickfix guide](https://neovim.io/doc/user/quickfix/) and
[diagnostic API reference](https://neovim.io/doc/user/diagnostic/) are useful
companions; local help remains the reference for your installed release.
