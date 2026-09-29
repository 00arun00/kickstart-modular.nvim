# Project explorer

Neo-tree is the project overview: browse nearby files, preview their contents,
and see open buffers or changed files. Its Files, Buffers, and Git tabs share a
36-column Catppuccin sidebar. Restart Neovim after changing the configuration.

Press a single `\` in Normal mode to open the Files sidebar and reveal the
current file. From the editor, it focuses an already-open sidebar without
changing its source or selection. From inside the sidebar, it closes it,
including when Buffers or Git is selected. Opening at a file outside the current
root can prompt to change the root. The tree does not automatically follow
subsequent buffer switches.

## Everyday keys

These keys apply while the tree has focus unless noted otherwise.

| Key | Action |
| --- | --- |
| `\` | Open/focus the sidebar from the editor; close it from any tree source |
| `<` / `>` | Previous / next source; the source tabs are also clickable |
| `j` / `k` | Move through files and folders |
| `Enter` | Open a file or expand/collapse a folder |
| `P` | Toggle floating preview; move through files to inspect them |
| `Esc` | Close the preview |
| `s` / `S` | Open a file in a vertical / horizontal split |
| `/` | Find a file within the Files source |
| `H` | Toggle filtered items in Files |
| `C` / `z` | Close the current folder / collapse all folders |
| `?` | Show source-specific help |
| `q` | Close the sidebar |

Dotfiles are visible. Git-ignored files and common clutter such as `.git`,
`.DS_Store`, and `__pycache__` are filtered; `H` can reveal them.

Git markers sit on the right: `M` modified, `A` added, `D` deleted, `R` renamed,
`?` untracked, `!` conflict, and `✓` staged. A solid dot (`●`) means the buffer
has unsaved edits. Collapsed folders can summarize changes inside them.

## Which tool to reach for

- **Explore an unfamiliar project:** `\`, expand folders, `P` to preview,
  then Enter to open. Use `s` when comparing neighboring files.
- **Jump to a known filename:** `Space s f` opens Telescope. For known open
  buffers, use `Space Space`; the Buffers tab gives a persistent list instead.
- **Review the affected files:** switch to Git. Use `Space g g` for LazyGit
  when reviewing diffs, staging, and committing. Neo-tree's own Git actions
  remain available in its help; the Git tab is not read-only.
- **Edit a directory:** `-` opens Oil. Neo-tree leaves directory opening to Oil,
  so the existing directory-editing workflow stays available.

The visual settings live in `lua/kickstart/plugins/neo-tree.lua`; palette
overrides live in `lua/custom/plugins/catppuccin.lua` and survive theme reloads.
