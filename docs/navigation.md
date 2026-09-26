# Breadcrumbs and symbol navigation

Dropbar puts a navigable breadcrumb row above each normal editing window. Restart
Neovim after installing this config. It works alongside the existing bottom
statusline, Telescope symbol searches and notebook cell shortcuts.

For example, inside a Python method:

```text
project › model.py › Model › forward
```

A notebook adds its current cell:

```text
tutorial.ipynb › 02 Code › Model › forward
```

In a Markdown notebook cell, it shows the cell number, type and a short title from
the first nonempty source line. Code, Markdown and raw cells all appear in the
cell menu. Cell numbers are positions in the document, not execution counts.

## Start with these keys

The leader key is Space. These bindings are Normal-mode bindings.

| Key | Action |
| --- | --- |
| `Space ;` | Show letter labels over the breadcrumb components; press a letter to open that component's menu |
| `Space .` | Open the deepest/current context's menu directly |
| `[;` | Jump to the beginning of the current context; repeat at its start to move to its parent |
| `];` | Browse the current context (same action as `Space .`, **not** next cell/function) |
| `Space j C` | Open all notebook cells, including Markdown and raw cells; uppercase `C` |
| `gO` | Existing Telescope search for symbols in this file |
| `gW` | Existing Telescope search for workspace symbols |
| `[n` / `]n` | Existing notebook previous/next-cell navigation |

Inside a dropdown:

| Key | Action |
| --- | --- |
| `j` / `k` | Move through entries; symbol preview highlights the source |
| `Enter` | Jump to the selected name |
| `l` | Open the selected entry's children when its arrow is available |
| `h`, `q`, `Esc` | Close the current menu; return to its parent or source window |
| `/` or `i` | Start fuzzy search in the current menu |

During fuzzy search, type a name, use `Ctrl-n` / `Ctrl-p` or the arrow keys to
select a result, and press Enter to jump. Escape leaves search first; another
Escape closes the menu. Search filters this menu's entries, not the whole
workspace. Use `gW` for workspace-wide symbol search.

The breadcrumb components are also clickable. Click a directory to browse it,
or a scope to browse its siblings. Menu arrows open children. Directory/file
hover previews are disabled so browsing a directory doesn't load files merely
because the cursor passes over their names. Selecting a file still opens it.

## Walkthrough: Python

1. Open a Python file and move inside a method. Watch the class/method names in
   the top row follow the cursor.
2. Press `Space ;`, then the letter shown over the class name. The menu lists
   sibling classes/scopes available from the active symbol provider.
3. Move with `j`/`k`. Press `l` on a class to browse its methods, then Enter on a
   method to jump there.
4. Press `[;` to return to that method's start. Press it again from the exact
   start to move to its parent scope.
5. Use `gO` when you already know a symbol name and want to search the entire
   file instead of stepping through the hierarchy.

Symbol details come from LSP when available, with Tree-sitter as a fallback.
The exact kinds/names shown depend on that provider. No indentation engine is
changed; Python still uses the built-in indenter.

## Walkthrough: notebooks

1. Open a Python `.ipynb`. Move between cells: the top row retains the current
   cell's identity even after its separator scrolls off screen.
2. Press `Space j C` to list all cells. This also works while the cursor is in
   the notebook's metadata preamble.
3. Press `/`, type a Markdown title such as `Results`, then Enter. The cursor
   jumps to that cell's marker. This reveals editable marker/source text under
   the existing notebook rendering rules; it does not execute the cell.
4. Move into a code cell containing a function or class. Its Python scope appears
   after the cell breadcrumb. Use `Space .` for its current scope menu, or
   `Space j C` whenever you want cells instead of Python symbols.
5. Open two splits of the same notebook and move to different cells. Each
   breadcrumb row follows its own window's cursor and width.

The custom source reads the same cell scanner as the separator UI. It caches
cell metadata until the source changes and builds the cell list on demand.
Markdown cell titles are labels, **not** a nested Markdown heading outline;
ordinary `.md` files use Dropbar's heading hierarchy. The previously documented
shared-state limitations of notebook *body rendering* are unchanged by this
window-specific navigation feature.

## Scope, limitations, and verification

### Naming code cells

Move to a code cell's marker (for example with `[n` / `]n`) and add a title:

```python
# %% Load training dataset
dataset = load_dataset()
```

Keep any existing marker metadata, such as `id="..."` or `tags=[...]`, after the
title. On save, Jupytext stores the title in the notebook cell's metadata; the
Python source is unchanged. The breadcrumb and `Space j C` menu update as you edit.

Code-cell labels use the explicit marker title first, otherwise the first
nonempty source line (with a leading comment marker removed). For example,
`# Build the dataloader` becomes `Code · Build the dataloader`; a cell starting
with `model = Model()` uses that statement. Empty cells retain just their number
and type. Labels are limited to 60 characters. These titles appear in navigation;
the notebook body's separators retain their existing design.

Breadcrumbs occupy one extra row per editing window and shorten labels in narrow
splits. Output/scratch buffers, terminals, help and floating windows are excluded.
Unnamed buffers and editable text over 1 MiB are excluded. The size check uses
converted notebook text, so large saved image outputs alone do not exclude it.

Nothing changes notebook source or executes code when browsing. Completion,
formatting, indentation, plotting and the existing navigation mappings remain
separate. The normal config adds no global `vim.ui.select` replacement.

Implementation:

- `lua/custom/plugins/dropbar.lua`: attachment, appearance, sources and shortcuts.
- `lua/custom/navigation/notebook.lua`: notebook cell source and cell picker.
- `tests/dropbar.py`: real Neovim navigation/menu/search/split/source-save checks.
- `tests/notebook_titles.py`: title priority, live edits, and saved metadata checks.

Run the test with a Python environment containing `pynvim` and `nbformat`, with
this config and its plugins installed:

```sh
~/.local/share/nvim/python/bin/python tests/dropbar.py
~/.local/share/nvim/python/bin/python tests/notebook_titles.py
```

The integration test uses temporary files and does not execute notebook kernels.
