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
