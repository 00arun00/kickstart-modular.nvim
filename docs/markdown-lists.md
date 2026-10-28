# Markdown lists and tasks

`bullets.nvim` continues Markdown lists with Enter in Insert mode or `o` in
Normal mode. It loads only for Markdown buffers. Tab/Shift-Tab retain their
existing completion, snippet, and Tabout behavior; `<Space>x…` remains Trouble.

| Key | Action |
| --- | --- |
| Enter at the end of an item | Create the next bullet, number, or unchecked task |
| Enter in the middle of an item's text | Split into an indented continuation, aligned with the item's text |
| Enter after an indented continuation line | Create the next list item |
| Enter on an empty item | Remove the empty marker |
| `o` in Normal mode | Open the next list item |
| Ctrl-Enter in Insert mode | Insert a plain newline, if the terminal sends a distinct keycode |
| `<Space>ct` | Toggle the current task and update its ancestors |
| `gN` in Normal/Visual mode | Renumber the current list/selection |
| Ctrl-T / Ctrl-D, `>>` / `<<` | Ordinary Neovim indentation; preserve marker styles |

Enter and `o` use normal editing behavior inside parsed code blocks. A colon
does not automatically create a child list. Prettier remains the formatter on
`<Space>f`; these mappings do not change formatting on save.

New tasks always start as `[ ]`, including after custom states from
`lua/custom/plugins/render-markdown.lua`: `[-]`, `[/]`, `[1]`, `[2]`, `[3]`,
`[>]`, `[!]`, `[?]`, and `[~]`. Existing states remain intact.

`<Space>ct` switches the current task between checked and unchecked. Only `[x]`
and `[X]` count as complete. When all checkbox children are checked, their
parent becomes `[x]`, continuing upward through nested tasks. Unchecking a
child reopens completed ancestors as `[ ]`. An unfinished parent's custom
state is preserved until all its children are complete. Toggling a parent
directly does not toggle its descendants. Ancestor updates undo with the task
toggle in a single step.

Parent updates run through `<Space>ct`, not arbitrary manual edits to checkbox
characters. They use the installed Markdown Tree-sitter parser to identify
nesting and exclude code examples. The plugin's native `:ToggleCheckbox` and
`:RecomputeCheckboxes` commands bypass this integration; use `<Space>ct` for
the state-preserving workflow.

Python notebook Markdown cells remain Python comments and do not receive these
Markdown-buffer mappings.
