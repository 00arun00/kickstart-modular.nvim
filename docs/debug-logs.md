# Debug logs

Chainsaw inserts temporary diagnostics for Python, Rust, C++, and Lua. The marker
is `⟦nvim:dbg⟧`; icons are the chosen Nerd Font glyphs plus 📍 and 🧪. Use a Nerd
Font in the terminal that displays program output as well as in Neovim.

The leader in this config is Space. Expression actions accept a word under the
cursor or a single-line characterwise/linewise selection. Select comparisons or
indexed expressions explicitly. Expressions are kept intact; their printed labels
are escaped independently. Multiline/blockwise selections are rejected.

Python placement uses a fresh Tree-sitter tree: logs go after complete calls and
assignments, or before `return`/`raise`. Function-parameter logs remain after the
docstring. Expressions inside lambdas/comprehensions, compound headers, and
shared-line statements are refused when placement could change scope or syntax.
Rendered source is inserted verbatim, including literal `{{lnum}}`/`{{insert}}`
strings. Selecting a function call still evaluates that expression for logging;
the original call is not rewritten or captured.

| Shortcut | Action | Output |
| --- | --- | --- |
| `<leader>lv` | String / display | ` ⟦nvim:dbg⟧ str │ name → Ada` |
| `<leader>lr` | Representation | ` ⟦nvim:dbg⟧ repr │ name → 'Ada\t'` |
| `<leader>lo` | Pretty object | ` ⟦nvim:dbg⟧ object │ payload` followed by indented contents |
| `<leader>ly` | Type | ` ⟦nvim:dbg⟧ type │ payload → …` |
| `<leader>le` | Sequential checkpoint | `📍 ⟦nvim:dbg⟧ checkpoint │ A` (edit in a description if useful) |
| `<leader>lm` | Prompt for a note | ` ⟦nvim:dbg⟧ note │ cache hit` |
| `<leader>lt` | Insert timer start / stop | ` ⟦nvim:dbg⟧ time │ #1 → 12.345 ms` |
| `<leader>ls` | Stack capture | ` ⟦nvim:dbg⟧ stack` followed by frames |
| `<leader>la` | Assertion panel | Prompts for an optional observed-value expression; displays details and fails only when the condition is false |
| `<leader>lb` | Toggle DAP breakpoint | Displays a source panel when a running debugger actually stops |
| `<leader>lx` | Remove marked statements | Whole buffer, or whole statements within the selected lines |
| `<leader>lf` | Find in project | Literal, case-sensitive marker search |
| `<leader>lj` / `<leader>lk` | Next / previous marked line | Wraps and opens folds; preserves the search register |

`<leader>lb` is an editor breakpoint, not an inserted `breakpoint()` or Rust
`dbg!()`. Python source breakpoints remain available with `:Chainsaw debugLog`.
Continue/step using the existing F5/F10/F11/F12 or `<leader>dc` mappings.

On an existing single-line Python `assert`, `<leader>la` in normal mode (any
cursor position) or with the entire statement selected using `v`/`V` replaces
it with a rich assertion. The condition is evaluated once and still respects
Python's `-O` flag. Leaving the observed-value prompt empty preserves the original
failure message in a separate `message` row. Entering a diagnostic expression adds
an `observed` row with its expression and value; it does not replace the message.
Leaving the input empty omits the `observed` row. A trailing metadata comment
stores the original line so `<leader>lx` restores it, including its comments.
Partial visual selections continue to use the selected expression.

Checkpoint labels advance per buffer: A, B, … Z, AA, AB, … . Each insertion uses
the label after the highest existing checkpoint, including after reopening a file
or undoing an edit. Existing checkpoints are never renumbered when you insert
between them. Gaps below the highest label are not filled; removing all checkpoints
restarts at A. The shortcut, `:Chainsaw emojiLog`, and dot-repeat use the same rule.

## Phases and coverage

1. **Native formats:** shared marker and labels, separate string/representation
   actions, notes, checkpoints, timers, types, and conservative cleanup.
2. **Rich diagnostics:** local helpers in `lua/custom/chainsaw/helpers/` provide object formatting,
   assertion panels, Lua/C++ representations, and stack output.
3. **Debugger panel:** a language-independent nvim-dap listener shows the actual
   stopped frame, source context and reason; dismisses on continue/exit; discards
   late responses from previous stops. It does not claim a pause merely because
   a logging statement ran.

| Feature | Python | Rust | C++ | Lua |
| --- | --- | --- | --- | --- |
| String | `str` | Requires `Display` | Requires `operator<<` | `tostring` |
| Representation | `repr` | Requires `Debug` | Helper handles strings/ranges/pairs/streamable values | Helper handles values/tables; Neovim Lua uses `vim.inspect` |
| Object | `pprint` | Pretty `Debug` | Range entries or streamable values; no automatic struct reflection | Nested tables, cycle detection, depth/item bounds |
| Type | Native `type` | Inferred type name | RTTI name, possibly mangled | Native category such as `table` |
| Timer | Elapsed time | Elapsed time | Elapsed time | CPU time, explicitly labelled `ms CPU` |
| Stack | Indented frame hierarchy | Native backtrace | Native backtrace where supported | Indented frame hierarchy |
| Assertion panel | Yes | Yes | Yes | Yes |
| Pause panel | DAP adapter | DAP adapter | DAP adapter | DAP adapter |

Rust/C++ native stack output preserves available symbols and locations. Rust's
stable backtrace interface does not expose structured frames. The C++ helper uses
standard stacktrace when available, otherwise `execinfo` on supported platforms;
on other toolchains it prints an explicit unavailable message. Debug symbols and
compiler optimizations affect frame detail. C++ helpers require C++17 or newer.

Python's DAP launch configurations already exist in this config. Rust, C++, and
Lua need their own adapter and launch/attach configuration. No adapters or project
build settings are installed or changed by these logging additions. Setting a
breakpoint without a launch configuration displays a reminder; it does not start
a session. The pause panel has a `q` mapping and does not steal editor focus.

## Helpers, assertions, and temporary source

Rich diagnostics reference the absolute path of this config's `lua/custom/chainsaw/helpers/` helpers.
There is no package installation in a project. Python loads the helper with
`runpy`, Lua uses `dofile`, and Rust includes a scoped helper module. C++ adds one
marked header include at the top of the buffer. These temporary statements are
local-machine diagnostics: remove them before sharing code or running it on a
machine without those helpers. Helper-loading/formatting overhead is real; avoid
placing diagnostics inside the section whose uninstrumented timing you need.

The plugin specification lives in `lua/custom/plugins/chainsaw.lua`; its Lua
implementation lives in `lua/custom/chainsaw/`.

An assertion evaluates the condition once. The optional observed expression is
evaluated only on failure, also once. Supply a dict/table/tuple or any supported
value to explain the failure, for example Python `{"shape": batch.shape}`.
Leaving the prompt empty reports that the condition evaluated to false. Escape
cancels insertion. Rich checks remain active regardless of Python `-O` or C++
`NDEBUG`; they raise/panic/abort/error according to the language.

Basic C++ statements use standard facilities; ensure the appropriate headers are
present (`<iostream>`, `<chrono>`, `<typeinfo>`). A rich helper include supplies its
own dependencies. Lua table inspection is bounded to 8 levels and 100 entries per
table; C++ range representation has similar bounds. User formatters and Python
`repr` methods still determine how custom values render.

## Cleanup and migration

The old `[debug]` marker is **not** automatically searched or removed. It is too
broad to safely treat arbitrary repository prints as ours. Use the old config to
clean existing generated statements before switching, or review them manually.

Cleanup recognizes complete generated statements. Python/Lua use Tree-sitter;
Rust/C++ use a conservative delimiter scanner. Shared lines, raw strings, block
comments, unsupported statements, and partially selected statements may be skipped
with a count. C++ helper includes are removed only within the selection and only
when no helper calls remain. Cleanup refuses a deletion that would introduce a
Python/Lua parse error (for example, leaving an empty Python suite). Add `pass` or
adjust the selection first. Deletions undo together, and timer indices avoid
surviving/reloaded timer names.

The marker is currently session-global, as in upstream Chainsaw. Per-repository
marker overrides are a separate enhancement; this implementation does not switch
markers automatically between repositories.

## Validation

Run from the Neovim config root, with the installed Chainsaw plugin and
Python/Lua Tree-sitter parsers:

```sh
nvim --headless -n -u NONE -i NONE -l tests/chainsaw.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_cleanup.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_checkpoints.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_insertion.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_languages.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_rich.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_dap.lua
nvim --headless -n -u NONE -i NONE -l tests/chainsaw_dap_live.lua
```

Runtime tests need Python 3, Rust/rustfmt, a C++17 compiler (`clang++`), LuaJIT and
Ruff (PATH or Mason). The final test uses the existing Neovim Python host's
`debugpy` and a real local debugger session. The DAP fixture test covers all four
language source types, stale callbacks, virtual source retrieval, and exit cleanup;
it does not claim to launch Rust/C++/Lua adapters.
