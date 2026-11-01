# Rich Markdown view

For directly openable stress notes and the visual review rationale, see
[Markdown reading design review](markdown-view-design-review.md).

`<Space>Tv` opens a rich reading pane beside the current Markdown source. Press
it again in either pane to close the view. The source buffer owns editing and
keeps its normal Vim motions, search, selection, undo, and saving. Whichever
pane is active drives navigation in the other pane. The existing in-buffer
renderer and its `<Space>Tr` Reading-mode toggle remain available independently.

The rich pane uses Pandoc to parse a buffer snapshot, Typst to typeset it, and
Snacks to display PNG tiles inside Neovim. Unsaved edits are included. Both a
continuous layout that reflows to the pane and fixed typeset pages are available.
The view opens only on request and supports one source/preview pair at a time.

## Setup

The Python host prepared by `bash scripts/setup-python.sh` supplies Pillow.
Install the optional rendering tools with:

```sh
bash scripts/setup-markdown-view.sh
```

This downloads checksum-verified Pandoc 3.13 and Typst 0.15.1 into
Neovim's data directory at `markdown-view/bin`. It does not change system
packages or install anything on Neovim startup. The script supports macOS and
Linux on Apple Silicon/ARM64 and x86-64. `NVIM_MARKDOWN_VIEW_DATA` can override
the Neovim data directory, for example for a disposable installation.
Executables already on `PATH` take precedence; the versions above are the ones
tested with this integration. Terminal rendering requires Unicode image
placeholders, as supported by the existing Ghostty setup.

Restart Neovim after updating the config. Run `:MarkdownView check` to inspect
dependencies before opening a note.

## Controls

| Action | Command or keys |
| --- | --- |
| Open/close the paired view | `<Space>Tv` or `:MarkdownView` |
| Continuous layout | `:MarkdownView continuous` |
| Paginated layout | `:MarkdownView paged` |
| Maximize/restore the active pane | `:MarkdownView zoom` |
| Force a fresh render | `:MarkdownView refresh` |
| Show phase, errors, and warnings | `:MarkdownView status` |
| Close the view | `:MarkdownView close` |
| Switch panes | Normal Neovim split navigation, such as `Ctrl-W W` |

In the rich pane, `m` switches layouts, `z` maximizes/restores, `r` refreshes,
and `q` closes. `Enter` or `Tab` returns to the corresponding source location.
Insert-entry keys return to source in Normal mode so editing remains deliberate.
Reading navigation includes `j`/`k`, counts, `gg`/`G`, page scrolling, and
`Ctrl-E`/`Ctrl-Y`. These movements follow canvas rows, rather than text words.

## Assets, updates, and limits

Ordinary local Markdown images and basic Obsidian image embeds are resolved from
the note and vault. Missing, unsupported, ambiguous, or invalid assets get a
readable fallback with a warning rather than failing the whole document.
PDF embeds and note transclusion are not implemented. Check
`:MarkdownView status` when something looks incomplete. Source notes are never
rewritten to resolve assets. Tables and long code blocks can break across pages
in paginated mode.

Rendering runs outside Neovim's main loop. The previous image stays visible
while an edit or resize is rendered. Revision guards reject obsolete results,
and synchronization pauses when its source map is stale. Obsolete generation
directories are pruned, and closing the view cancels its work and removes its
temporary files. Source edits and viewport changes remain usable if rendering
fails.

The rich pane is an image canvas. Native text search, selection, yanking, and
link following remain source operations. Synchronization uses source block
positions and interpolation, so it is approximate within long paragraphs,
equations, and large tables. Full Obsidian feature parity, rendered Mermaid
diagrams, and all LaTeX extensions are not provided by this pipeline.

The initial presentation keeps the prototype's light palette and typography.
Following the current Neovim theme is a separate enhancement. This view does
not alter the native renderer's SVG decoder or the editor's font settings.

Very large documents can take appreciable time and terminal memory to typeset
and display. Full-document rendering is intentional in this first integration;
it has no custom look-ahead scheduler. The Snacks image adapter also retains
small image metadata objects until Neovim exits, following the plugin's cache
lifetime; owned terminal placements and on-disk generation files are released.

## Try a real note

Open an ordinary vault note and press `<Space>Tv`. Wait for the preview bar to
report ready, then navigate from each pane. Compare layouts using `m`, maximize
each pane using `:MarkdownView zoom`, and edit/undo a sentence in source. Use
`:MarkdownView status` for any warnings. Close with `<Space>Tv` and continue
editing normally.

Automated coverage checks asset isolation, rendering, two-way navigation,
source preservation, stale completions, and cleanup. It cannot establish the
terminal's decoded pixel quality; that final visual check happens in Ghostty.

```sh
make test SUITE=all FILE=markdown_view
```
