# Variable explorer review

The Molten adapter was developed against real, disposable Jupyter kernels and
the full Neovim configuration, with a separate skeptical reviewer evaluating
the implementation and rendered Neovim UI captures at each round.

| Round | Independent score | Main findings and refinements |
| --- | --- | --- |
| Baseline | 5.5 | Shallow preview needed a functional inspection workspace. |
| 1 | 7.3 | Added nested objects, slices, table operations, renderers, and plots; review exposed clipped columns, unclear limits, and weak selected-cell feedback. |
| 2 | 8.4 | Adaptive columns, explicit bounds, selection, renderer paging, plot conversion; review found filter/slice errors prevented correction. |
| 3 | 9.0 | Recoverable errors, selection restoration, responsive orientation, persistent contextual controls, taller plot viewer. |
| Extra 1 | 9.1 | Error context retains nested identity; toolbar advertises supported actions. |
| Extra 2 | 9.2 | Multiline/Unicode popup and exact copy, truncation feedback, renderer/source distinction, tiny-window checks. |
| Extra 3 | 9.3 | Lossless large integer keys, exact integer/string displays, ragged plot inputs, compact toolbar and horizontal scroll correction. |

The scores are subjective assessments of the bounded local explorer, not a claim
of parity with every JupyterLab workflow. Three further refinement rounds were
completed after first reaching 9.0.

## Evidence

- `tests/variables_workspace.py`: real Neovim/kernel interaction covering over
  200 variables, nested paths, stored fields, large dictionary keys, 4D slices,
  invalid-input recovery, duplicate DataFrame columns, filtering/sorting,
  custom renderers, actual plot command and PNG conversion, value popup/copy,
  selection restoration, and 150-, 86-, and 50-column layouts.
- `tests/variable_values.py`: adversarial helper contracts for property/repr
  exclusion, exact/truncated text, integer precision, renderer pagination,
  ragged rows, extreme/nonfinite plot values, and empty tensors.
- `tests/variables.py`: original lifecycle regression covering output/history
  preservation, normal reruns while focused, multiple kernels, busy timeout,
  restart, stop, and source-buffer closure.
- Formatting, Ruff, and `git diff --check` were checked for the changed code.

Captures are real isolated Neovim redraw grids rendered to PNG, not photographs
of the user's Ghostty session. The PNG plot comes from the actual explorer
conversion path. The capture font does not cover every Unicode glyph; buffer
and clipboard assertions verify the underlying Unicode text separately.

## Scope and remaining limits

Plots show the requested page only, with its view coordinates. They do not offer
arbitrary x/y selection or full-dataset analysis. Tensor slicing chooses leading
indices and displays the final two axes. Standard inspection is read-only;
explicit custom renderers run trusted user Python and can have side effects.

Native Ghostty/tmux image overlays and physical GPU transfers have not been
visually/hardware verified in this test environment. The existing Snacks image
path is used, with an external SVG fallback. Live variable editing and arbitrary
tensor-axis rearrangement are outside this implementation.

See [the workflow guide](python-pde.md#variable-explorer) for controls and examples.

## Image zoom, pan, and fit refinement

After the user confirmed baseline inline image display, the viewer gained a
centered, enlarged fit; local nearest-neighbor zoom/pan; a persistent help view;
and direct batch-index navigation. The independent reviewer scored the first
pass 8.8/10, then 9.2/10 after compact labels, native-placement callback tests,
color/alpha examples, and no-op boundary handling. No release blockers remained.

`tests/image_viewport.py` verifies actual pixels, center anchoring, pan clamps,
aspect ratios, transparency, and bounded output. `tests/image_viewer.py` exercises
the real Neovim controls, rapid input, source-PNG retention, help scrolling/error
states, tiny windows, and counts kernel requests to establish that viewport
operations do not query the kernel. Mocked terminal callbacks test stale-placement
rejection and placement lifecycle; they do not prove physical HiDPI alignment.
The existing explorer regression suite also passed after its resize handling was
deferred while the image viewer is focused.

Native rendering of the updated viewport still needs a terminal-side check;
the available captures show real Neovim UI grids and separately verified PNG
canvases. Full-data plotting and original tensor-value pixel inspection remain
separate future work.

## Full-source plotting review (2026-09-27)

Implemented a separate plot setup panel using bounded kernel extraction and
Vega-Lite rendering in the editor Python host. `p` configures full-source plots;
`P` preserves quick page plots. No project plotting dependency is required.

Independent skeptic review began at 7.8: control characters in column labels,
overlapping heatmap ticks, incomparable histogram bin edges, and unverified
browser rendering were identified. These were addressed and reviewed at 9.1.
Three additional refinement rounds covered contextual help/error recovery,
chart-specific controls, and label/deletion/async-close edge cases. Intermediate
reviews rated the first two additional rounds 9.2; the final independent
review rated the completed scoped feature 9.3 with no release blockers.

Validation:

- `tests/plot_values.py`: bounded full-source ranges, sampling endpoints,
  shared exact histogram bins, duplicate labels, missing-value gaps, tensor
  slices, empty/invalid/extreme data, and source preservation.
- `tests/plot_renderer.py`: four chart types, PNG/SVG/JSON, bundled HTML,
  and script-closing label escaping.
- `tests/plot_workspace.py`: real Neovim and Jupyter kernel; multi-series
  controls, preview zoom/fit, exports and no-overwrite, resize/focus, invalid
  ranges, newline/CR labels, close during rendering, deleted sources, and
  notebook/source/history/output preservation.
- `tests/plot_browser.cjs`: actual headless Chrome with HTTP blocked; chart
  renders without page errors and wheel zoom changes its axes.
- Existing variable workspace, image viewer, variable/image values and viewport
  regressions pass. Ruff, StyLua, and diff whitespace checks pass.

Actual Neovim grid captures: `/tmp/full-plot-ui`, followed by
`/tmp/full-plot-refine1`, `/tmp/full-plot-refine2`, and `/tmp/full-plot-refine3`.
Rendered chart/browser evidence: `/tmp/full-plot-review`.
These are local temporary QA artifacts, not repository assets. Grid captures
verify TUI layout; they do not establish physical Ghostty/tmux image placement.
The existing Snacks image path is reused, and its placement behavior is covered
by the image-viewer regression. Manual native-terminal confirmation remains.

Limits are documented in `python-pde.md`: uniform sampling may miss spikes,
first 512 columns, eight series, numeric-only axes, bounded extraction, and
floating-point plotting precision. Browser axes are interactive; terminal
preview zoom/pan manipulates the rendered PNG. The broader explorer TUI
consistency pass remains separate follow-up work.
