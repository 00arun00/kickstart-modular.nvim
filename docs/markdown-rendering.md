# Markdown rendering experiments

## Inline math tables

Markdown pipe tables containing equations render directly inside the note using
native Neovim text for labels/borders and separate Snacks images for equations.
`<br>` creates a cell line break; display equations are centered within their
cells, with row height reserved for their images. Ordinary tables retain the
existing render-markdown layout.

Moving the cursor into a math table reveals the complete source table; leaving
restores the rendered layout. Source edits update the layout, and renderer
enable/disable commands apply too. No buffer text, modified state, or saved
Markdown is changed by rendering.

Motions, counts, operators, and Visual mode use native source-line semantics.
Each header/body source row has its own anchor, and the Markdown delimiter row
anchors the border beneath the header. The layout retains every source line
instead of concealing whole lines, avoiding the Neovim cursor/scrolloff loop when
approaching a tall table from below. The window's `scrolloff` setting is unchanged.
Use `Ctrl-E`/`Ctrl-Y` for native viewport scrolling. Resizing recalculates the
layout while retaining the native source cursor position.
Long concealed source lines can still occupy native wrapped screen rows. Those
continuations are painted as cell padding so borders remain continuous, without
repeating labels/equations or disabling wrapping for surrounding prose.

The decorations are shared by windows showing the same buffer. Their layout
uses the narrowest visible text area; revealing source in the active window
reveals it in the other views too. Windows retain their independent native cursor
positions while sharing stable table decorations. A table at the end of a file needs
no extra blank line. If equation conversion fails, the normal source table is
kept visible. Non-image terminals retain their existing table rendering.

The cell layout currently supports plain text, bold labels, `<br>`, and math;
full nested Markdown/HTML and delimiter-based column alignment remain outside
this experiment. The separate preview command below remains available for
comparison.

```sh
make test-lua SUITE=integration FILE=markdown_tables
```

The inline integration test covers equation placements, ordinary-table
isolation, EOF anchoring, split resizing, source reveal, byte-exact saves,
reversed asynchronous parsing callbacks after edits, renderer toggling, and
cleanup. An attached Neovim UI and actual TeX conversion were also checked
against the local `FlowMatching.md` table.

## Cell-by-cell math table preview

Place the cursor anywhere inside a Markdown pipe table and run:

```vim
:MarkdownMathTable
```

The prototype opens a separate preview tab. Cell prose and borders are native
Neovim text, using the terminal's normal font; only equations are images. Inline
`$...$` math occupies one visual row, while `$$...$$` equations get their own
centered block inside the cell. The layout supports bold labels, `<br>` breaks,
wrapped text, and rows tall enough for their equations. Resize the preview to
recalculate column widths and equation sizes. Press `q` to close it.

This separate view is a snapshot for comparing the layout. Edit the source note
and run the command again to refresh it. The source note, its Markdown syntax, and its modified
state are preserved. No vault or attachment path is configured in the prototype.

Requires the existing Snacks image pipeline: Ghostty or Kitty with Unicode image
placeholders, Markdown/LaTeX Tree-sitter parsers, ImageMagick, a LaTeX compiler
(Tectonic or pdfLaTeX), and Ghostscript. Rendering failures retain the native
table text and report a warning.

The initial experiment targets ordinary pipe tables with text, bold labels,
`<br>`, and math. It does not attempt full Markdown/HTML rendering inside cells,
delimiter-based column alignment, or live synchronization with source edits.

Validation:

```sh
make test-lua SUITE=integration FILE=markdown_table_preview
```

The integration test uses the installed parser and real Snacks placement code,
with deterministic equation images and terminal transport. It covers header,
inline and display math, native labels, image/border isolation, resize reflow,
source preservation, and cleanup. Actual TeX conversion and path discovery were
also checked against the table in the local `FlowMatching.md` note.
