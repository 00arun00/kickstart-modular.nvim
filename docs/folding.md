# Reading long files with folds

Origami prefers LSP folding, falling back to Tree-sitter and then indentation.
It decorates collapsed lines without removing their original indentation or
syntax colors. Files open fully expanded.

Closed folds have a subtle background, a gutter arrow, and a right-aligned
summary such as ` 165`. This counts hidden lines, excluding the visible
header. The gutter appears when the window has folds and uses a single column.

## Start with these keys

All bindings below are in Normal mode. The leader is Space. Press `Space z` to
see the extra fold actions in which-key.

| Key | Action |
| --- | --- |
| `h` | Move left; in indentation or on the first non-whitespace character, close the enclosing fold |
| `l` | Move right; on a collapsed fold, open one level |
| `za` | Toggle the fold at the cursor |
| `zc` / `zo` | Close / open one level |
| `zC` / `zO` | Close / open the current fold recursively |
| `zM` / `zR` | Close / open every fold in this window |
| `zm` / `zr` | Show fewer / more nesting levels |
| `[z` / `]z` | Move to the start / end of the current open fold |
| `Space z f` | Fold unrelated code and reveal the nested code at the cursor |
| `Space z p` | Preview a closed fold; repeat to enter the preview |
| `Space z g` | Toggle hidden Git-change counts for this session |
| `zi` | Temporarily disable / re-enable folding in this window |

`h` closes folds within indentation or on the first non-whitespace character
of a line. If there is no fold to close, it moves left
normally. `l` opens a collapsed fold instead of moving across its header.
The standard `^`, `$`, and uppercase `H` / `L` motions are unchanged.

## A practical workflow

1. Use `zM` to see a file's outline, then `zo` on the function you want to read.
   Inner blocks remain folded; use `zo` again as you explore.
2. For a multiline function signature, use `Space z p` on its closed fold.
   The highlighted, read-only popup includes the whole folded region.
   Repeat `Space z p` to enter it, scroll with `Ctrl-d` / `Ctrl-u`, and press
   `q` or `Esc` to close it. Moving the cursor in the source also dismisses it.
3. While reading deep inside a long function, use `Space z f`. The cursor stays
   on the same code; containing folds open and unrelated folds close.
4. Use `zR` to return to a fully expanded view. Focus mode is not a saved view;
   it does not restore a previous arrangement of manually opened folds.

## Information inside a fold

Diagnostics inside hidden lines appear automatically, using the configured
diagnostic signs: for example, `1 2` means one error and two warnings.
Errors are red and warnings orange, matching the gutter signs. A
diagnostic on the visible header is not counted again in the summary.

Git counts are enabled by default. `Space z g` toggles summaries such as
`+3 ~2 -1` for added, changed, and deleted lines reported by Gitsigns.
These are line counts, not a staging interface or a list of changed files.

Summaries align to the right when they fit. A long header or narrow split can
push the summary out of view: the original code takes priority. Widen the
window or preview the fold when you need more detail. The first line remains
the actual source line; no synthetic function signature is substituted.

Native search can open a fold containing a match. Origami's automatic search
pause and its automatic import/comment folding are disabled, keeping `zi`,
output panes, and the open-by-default policy predictable. Fold boundaries can
change when an LSP with folding support attaches.

## Configuration and checks

- `lua/options.lua`: native fold defaults and gutter characters.
- `lua/custom/plugins/origami.lua`: Origami settings and extra bindings.
- `lua/custom/navigation/folds.lua`: focus, preview, and summary alignment.
- `lua/custom/plugins/catppuccin.lua`: fold colors that survive theme reloads.

Run `nvim --headless -n -u NONE -i NONE -l tests/folds.lua` to check focus,
preview isolation, cursor preservation, and output-buffer behavior. This helper
test uses manual fixture folds and does not require Origami or a parser.
