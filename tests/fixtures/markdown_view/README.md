# Markdown reading design corpus

Open these notes directly in Neovim. `<Space>Tr` controls the native source-buffer
Reading mode; `<Space>Tv` opens the synchronized rich view. In the rich pane,
`m` compares continuous and paginated layouts and `z` maximizes/restores it.

The prose in each fixture describes review criteria to test, rather than adding
new product requirements. The explicit display-math requirement is that `$$…$$`
uses consistent centering within its current content container. Inline `$…$`
stays in prose; internal `aligned`, matrix, and cases structure is preserved.

The native source-buffer renderer still has a known exception for `$$…$$`
surrounded by prose on the same source line: centering that fragment safely
needs a paragraph layout that also preserves the surrounding prose. The rich
view handles that case. An explicit strict expected-failure test keeps the
native limitation visible rather than counting it as supported.

| Note | Review focus |
| --- | --- |
| `01-equation-layout.md` | Delimiter forms, inline/display distinction, list/quote containers, aligned derivations, matrices, cases |
| `02-document-hierarchy.md` | H1–H4 hierarchy, prose measure, lists, quotes, code, footnotes |
| `03-tables-and-math.md` | Default and explicit alignment, wrapping, mathematical cells, wide comparisons |
| `04-figures-and-assets.md` | Small/wide figures, natural document size, equivalent embed forms, failed assets |
| `05-pagination.md` | Mixed content crossing pages, table/code continuation, final markers |
| `06-narrow-layout.md` | Long equations, long code, constrained tables, nested available width |

The diagrams are deliberately simple local PNGs so ordinary figure review does
not depend on the separate native SVG decoder issue. The invalid SVG file is an
explicit failure fixture. Generated review images belong in `.test-results/`,
not this source corpus.

Run the observable rendering checks with:

```sh
make test-python SUITE=integration FILE='markdown_view_design or markdown_native_design'
```
