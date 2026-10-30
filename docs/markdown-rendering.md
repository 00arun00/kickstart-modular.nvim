# Markdown rendering experiments

## Equation colors

Equation images use the active theme palette's teal/cyan accent, distinct from
ordinary prose. The shared theme layer sets SnacksImageMath on each colorscheme
change, including the darker accent adjustment used by light themes.

After colorscheme handlers finish, Markdown equation placements are discarded
and rediscovered with the new color. Inline and display images then use the
normal converter/cache; tables invalidate their layout/image listeners too.
Cached files are retained so switching back can reuse previously generated
images. Old-theme parsing results and queued placement updates cannot restore
stale-colored images. Mermaid and ordinary image placements are retained.

## Inline math

Single-dollar Markdown expressions outside tables use inline LaTeX text style.
Symbols and compact fractions share a transparent reference canvas/baseline and
one terminal-row placement. Longer expressions gain columns at the same scale;
subscripts and other mathematical proportions retain their natural sizes.
Transparent horizontal padding rounds widths to terminal columns rather than
stretching each tightly cropped expression independently.

The inline converter uses its own cache/file type and retains transparent
padding. Display equations and table math keep their existing conversion/sizing
policies. Source text, native motions and Reading mode behavior are unchanged.
Very tall structures or formulas exceeding the available width retain Snacks'
existing fallback; multi-row inline layout is outside this first step.

    make test-lua SUITE=integration FILE=markdown_inline
    make test-python SUITE=integration FILE=markdown_inline_raster

The parser/placement test uses deterministic metadata. The optional raster test
uses real Tectonic, ImageMagick and Ghostscript, checking shared canvas height,
compact inline placement, increasing expression width, transparency, and the same
rho glyph dimensions/baseline inside a longer expression. It skips when those
external tools are absent.

## Reading mode

`<Space>Tr` toggles Reading mode for all Markdown buffers, including scratch
notes and files opened later. It is enabled at the start of each session.
Which-key shows the action only in Markdown, with an Enable/Disable description.

With Reading mode on, Normal-mode motions and searches keep tables, equations,
and Mermaid diagrams rendered even under the cursor. Insert or Replace mode
exposes source for editing; `Esc` restores rendering. With Reading mode off,
moving the cursor onto rendered content reveals source as before. The original
Markdown is never changed. `j`/`k`, Up/Down, and counts such as `5j` use native
Vim source-line movement everywhere, including rendered math tables. Relative
line numbers therefore match motion counts. Each source row has a stable rendered
anchor; one motion can cross a tall table cell or equation. Use native
`Ctrl-E`/`Ctrl-Y` to scroll through the rendered content. Vim may move the cursor
when necessary to keep it visible. No table-specific movement maps or visual
offset state are installed.

Lualine shows ` on/off` only in Markdown. Scratch-note footers show the same
coffee indicator. Reading mode suppresses diagnostic decorations and automatic
diagnostic jump floats; turning Reading mode off shows diagnostic display again.
Entering Insert mode while reading exposes source without turning diagnostics
back on. Diagnostics continue updating in Trouble, Telescope, quickfix, and
location lists throughout. There is one toggle and no separate diagnostic
preference to manage.

```sh
make test-python SUITE=integration FILE=markdown_reading
```

The attached-editor tests exercise real Normal/Insert transitions, delayed
image completion during Insert mode, toggle behavior, inherited split settings,
diagnostic display and lists, lualine, scratch footers, new buffers, and
isolation from other filetypes. The image converter and terminal transport are
deterministic test stand-ins; render-markdown and Snacks controllers are real.
Table navigation checks cover source-line motions/counts, arrow keys, the upward
scrolloff regression, native scrolling, resize, Insert-mode reveal, BOF/EOF,
operators/Visual mode, direct jumps/searches, cursor positions across splits, and
continuous borders with wrapped source lines.

## Inline math tables

Markdown pipe tables containing equations render directly inside the note using
native Neovim text for labels/borders and separate Snacks images for equations.
`<br>` creates a cell line break; display equations are centered within their
cells, with row height reserved for their images. Ordinary tables retain the
existing render-markdown layout.

In Reading mode, moving the cursor into a math table keeps it rendered; enter
Insert mode to reveal the source, and `Esc` restores the layout. With Reading
mode off, cursor entry reveals the complete table and leaving restores it.
Source edits update the layout, and renderer enable/disable commands apply too.
No buffer text, modified state, or saved Markdown is changed by rendering.
Insert/Replace exposes the original table. Motions, operators and Visual mode
all act on source lines; rendered virtual rows are display content. Reading mode
off restores cursor-triggered source reveal. Each header/body source row has its
own anchor, and the Markdown delimiter row anchors the border beneath the header.
Direct line jumps and searches therefore land on the corresponding rendered row;
Insert mode exposes that same source row. The layout retains every source line
instead of concealing whole lines, avoiding the Neovim cursor/scrolloff loop when
approaching a tall table from below. The window's `scrolloff` setting is unchanged.
Resizing recalculates the layout while retaining the native source cursor position.
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
