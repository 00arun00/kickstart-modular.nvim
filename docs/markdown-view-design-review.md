# Markdown reading design review

This review compares the native source-buffer renderer, continuous rich view,
and paginated rich view using the same source documents. The aim is comfortable
reading with coherent mathematical layout, while source editing stays native.

## Design criteria

- `$$…$$` is display mathematics and is centered within its containing reading
  column. `$…$` remains in prose. Alignment inside derivations, matrices, and
  cases is mathematical structure and must be preserved.
- Source-position metadata must not change the document's layout.
- Hierarchy, spacing, figure scale, and table geometry must support reading,
  rather than merely produce a successful compile.
- Native editor and typeset views need coherent behavior, not identical pixels.
  The terminal grid has constraints that a separate typesetter does not.

Obsidian is a useful reference for reading behavior, not a ceiling on typography
or presentation. Its [formatting documentation](https://obsidian.md/help/advanced-syntax)
distinguishes block and inline mathematics and describes table alignment. The
review uses that documentation and the user's experience as references; it is
not a live pixel comparison against the Obsidian application.

## Openable review documents

The [corpus guide](../tests/fixtures/markdown_view/README.md) describes the cases.
Open any of these in Neovim and use `<Space>Tr` for source-buffer Reading mode,
then `<Space>Tv` for the rich view. `m` in the rich pane switches layouts.

| Document | Focus |
| --- | --- |
| [Equation layout](../tests/fixtures/markdown_view/01-equation-layout.md) | Delimiters, surrounding prose, lists, quotes, derivations, matrices, cases |
| [Document hierarchy](../tests/fixtures/markdown_view/02-document-hierarchy.md) | Headings, reading measure, lists, quotes, code, footnotes |
| [Tables and mathematics](../tests/fixtures/markdown_view/03-tables-and-math.md) | Alignment, wrapping, mathematical scale, wide tables |
| [Figures and assets](../tests/fixtures/markdown_view/04-figures-and-assets.md) | Compact/wide figures, embed syntax, asset failures |
| [Pagination](../tests/fixtures/markdown_view/05-pagination.md) | Table/code continuation and mixed page boundaries |
| [Narrow layout](../tests/fixtures/markdown_view/06-narrow-layout.md) | Long equations, literal code, constrained tables, quotes |

The fixture prose includes proposed design expectations. These do not silently
become original product requirements. Display-math centering is an explicit user
requirement; broader typography choices are evaluated against reading quality.

## Cycle 1: structural equation layout

The rich renderer's CommonMark source positions introduced provenance Divs.
Pandoc translated them into shrink-wrapped Typst blocks. Display math centered
inside those narrow blocks, so equations appeared left aligned or shifted with
the length of surrounding prose. Moving individual equations would leave the
underlying layout defect intact.

The fix flattens only parser-created provenance wrappers while retaining their
source anchors and preserving real attributed Divs. Quote content uses one
full-width panel, so its equation alignment does not depend on the text length.

Native review also found that quote prefixes could enter the converted LaTeX,
and that quote/list displays did not consistently use the available content
column. The native change recognizes those structural prefixes, strips them
from conversion while preserving mathematical `>` relations, and centers the
image decorations within the available source text area. It does not rewrite
the source buffer.

Validation checks actual glyph ink in rendered PNGs and actual image placeholder
columns in the native UI grid. A centered outer block alone is insufficient
evidence. The source is checked for preservation and the layout is exercised at
multiple widths and in both rich modes.

## Cycle 2: scale, hierarchy, and table presentation

The second review found excessive compact-image enlargement, weak H3/H4
distinction, inherited centering of default narrative table columns, and native
table-cell spacing/mathematical scale.

The rich view now uses the typesetter's intrinsic image sizing, bounded by its
container, while preserving explicit image sizes. Compact figures no longer
become blurred full-width panels. H3 and H4 have distinct sizes and spacing.
Default table columns align left; explicitly centered and right-aligned columns
retain their source semantics.

Native single-dollar table mathematics now shares the prose inline conversion
profile. Layout remains the table's responsibility: compact expressions use one
row, while tall matrices/fractions receive their natural additional height.
Unconditional top/bottom row padding was removed. A separate source cursor
anchor is retained when needed so multirow image chunks stay together in
contiguous virtual rows even when the underlying Markdown source line wraps.
This avoids broken images without remapping native source motions.

The reviewer verified generated glyph scale, source-label visibility, and
encoded image row order. The representative matrix's two image rows are
consecutive in the actual UI grid, with one visual origin. Existing tests that
assumed every label had to occupy the physical source anchor were updated to
check ownership of that source row's complete rendered surface instead.

## Explicit open items

One native case remains a distinct architectural problem: `before $$math$$
after` on the same source line. Centering an overlay would cover neighboring
prose; moving only the equation below it changes the reading order. Correct
presentation needs source-backed paragraph-fragment layout. The rich view can
typeset this case correctly without that additional native presentation layer.
This limitation must not be reported as satisfying all native display-math cases.
It is represented by a strict expected-failure test, rather than counted as a
passing centering case.

Very wide continuous prose also needs a deliberate reading-measure policy.
A universal narrow document column would constrain wide figures and tables;
per-paragraph wrappers would reintroduce layout responsibilities that need their
own evaluation. This is a design preference still under review, not a hidden
change to the original requirements.

## Reproduce

The completed layout pass passed 62 fast tests, 53 existing Markdown/rich-view
checks, and 58 design checks. One additional design check is an explicit strict
expected failure for native prose-adjacent display math. Installed plugin
revisions matched the committed lockfile. These counts overlap between selected
suites and must not be added as independent coverage.

Local review packets are in
`.test-results/markdown-view-design-cycle-1/` and
`.test-results/markdown-view-design-cycle-2/`, including same-source before/after
images and review records. The final design run is
`.test-results/run-_gc1s44o/`; the broader Markdown regression run is
`.test-results/run-1snzcqs4/`.

```sh
make test-python SUITE=integration FILE='markdown_view_design or markdown_native_design'
make test-python SUITE=all FILE=markdown_view
```

The design suite leaves source snapshots, PNG tiles, source maps, and measured
geometry under the invocation's `.test-results/run-*/markdown-view-design/`.
Native layout reconstructions combine real Neovim redraw grids and generated
equation PNGs; they are explicitly distinct from Ghostty screenshots. The final
terminal visual check remains useful after automated and reconstructed evidence.
