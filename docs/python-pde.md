# Python PDE

The editor uses basedpyright for types/completion, Ruff for linting and formatting,
Jupytext for notebook editing, and Molten for Jupyter execution. NotebookNavigator
adds `# %%` cell movement and execution in both `.py` and `.ipynb` buffers.

Lua integration modules live in `lua/custom/python/`; their Python runtime
helpers live alongside them in `lua/custom/python/helpers/`. The Lua callers use
`custom.python.paths` to find helpers independently of the current project.
Environment setup remains in `scripts/setup-python.sh`; the host dependency group is declared in `pyproject.toml` and pinned in `uv.lock`.

## Setup

From this config directory, run `bash scripts/setup-python.sh` (requires `uv`).
This installs pinned editor dependencies into `stdpath('data')/python`, using
Python 3.12. Restart Neovim, let Lazy install plugins, then run
`:UpdateRemotePlugins` and restart once more. This machine has already been set up.
Use `NVIM_PYTHON_DATA` to override the data directory for the setup script.
An explicitly configured `g:python3_host_prog` takes precedence; it must have
Molten's dependencies too.

In each uv project:

```sh
uv add --dev ipykernel pytest ruff
uv sync
nvim notebooks/analysis.ipynb
```

For a plain virtual environment without a `pyproject.toml`, use
`uv pip install --python .venv/bin/python ipykernel pytest ruff` instead.
No project dependencies are installed automatically on opening a file.

## Environment selection

The nearest ancestor `.venv` wins, including when Neovim was launched elsewhere.
`:PyVenvInfo` shows the resolved paths. `:checkhealth custom.python` checks the host, project dependencies, and Molten registration. `:PyVenvSet /path/to/venv` overrides the
current project; `:PyVenvReset` returns to automatic detection. Overrides are
session-local. Both commands restart only that project's Python LSP clients.
Stop and reinitialize active notebook kernels after changing environments.

The shared Neovim Python host is separate from project Python. Each notebook
kernel uses an absolute project interpreter and starts in the project root.
Wait for the kernel-ready notification before running cells. Private kernelspecs live under `stdpath('data')/jupyter/kernels/nvim-*`; two
projects with the same directory name cannot collide. With no `.venv`, the
resolver falls back to Python on PATH; check `:PyVenvInfo` before running code.

## Notebooks

Open an existing `.ipynb` or create a new one with `:edit analysis.ipynb`.
You edit Python percent cells, with markdown cells represented as comments.
The metadata header at the top is part of the notebook: keep it intact.
Jupytext saves real notebook JSON back to the same file. Normal `:write` preserves
existing saved outputs; it does **not** export newly executed Molten outputs.
Paired Jupytext notebooks retain their pairing and synchronize on save.

Leader is Space. Existing Noice mappings remain under Space-n.

| Key | Action |
| --- | --- |
| `<leader>ji` | Start kernel using this project's Python |
| `[n` / `]n` | Previous / next cell |
| `<leader>jc` / `<leader>jn` | Run cell / run and advance |
| `<leader>ja` | Run all cells |
| `<leader>jN` | Add a cell below |
| `<leader>jV` | Open variable explorer (uppercase V) |
| `<leader>jl` | Run line |
| `<leader>jv` (visual) | Run selection |
| `<leader>jo` / `<leader>je` / `<leader>jh` | Show / enter / hide output |
| `<leader>jx` / `<leader>jr` / `<leader>jq` | Interrupt / restart / stop kernel |
| `<leader>jI` | Import previously saved outputs after initializing |
| `<leader>js` | Save notebook source and export current outputs |
| `<leader>jb` / `<leader>jp` | Open HTML output / plot externally |
| `<leader>f` | Format and organize imports with project Ruff |

Execution is always explicit. Text outputs appear inline; graphics use Snacks
in supported terminals. Molten's output import/export
is experimental: it matches cells by source text, so duplicate code cells can
be ambiguous. Execute both duplicates before exporting. Saved outputs can remain
stale after code edits until you rerun the cells. See
[Molten's output documentation](https://github.com/benlubas/molten-nvim/blob/main/docs/Advanced-Functionality.md).
Gitsigns is disabled on converted notebook buffers because its JSON diff cannot
safely map to Python lines. It continues to work normally in `.py` files.

Jupytext percent format comments out IPython `%` and `!` syntax. For executable
magics use explicit `get_ipython().run_line_magic(...)` calls in Python cells.

This workflow targets local Python notebooks; other languages open as raw JSON; use a notebook frontend for rich
widget interaction or other notebook languages.

## Verification

```sh
XDG_STATE_HOME=/tmp/nvim-test-state nvim --headless -u NONE -l tests/venv.lua
# Prepare a disposable project with uv and ipykernel/ruff as above, then:
~/.local/share/nvim/python/bin/python tests/notebook.py '/tmp/test project'
stylua --check lua/custom/python lua/custom/plugins/notebooks.lua tests/venv.lua init.lua
```

The integration test creates `pde-smoke.ipynb`, `pde-new.ipynb`, and `pde-foreign.ipynb` in the supplied
disposable project. It checks notebook metadata/output preservation, formatting,
real kernel execution, interpreter/cwd selection, output export, and reopening.

## Tests and debugging

Neotest discovers pytest tests and shows results inline and in a summary tree.
The test interpreter comes from the same resolver as notebook kernels and LSP.
Debugpy itself lives in the editor host; the program being debugged uses project
Python. This avoids requiring debugpy in each project.

| Key | Action |
| --- | --- |
| `<leader>pt` / `<leader>pf` / `<leader>pa` | Run nearest test / file / project |
| `<leader>pd` | Debug nearest test |
| `<leader>ps` | Toggle test summary tree |
| `<leader>po` / `<leader>pO` | Open test output / output panel |
| `<leader>pl` / `<leader>px` | Rerun last / stop tests |
| `<leader>db` / `<leader>dB` | Toggle breakpoint / conditional breakpoint |
| `<F5>` or `<leader>dc` | Start or continue debugger |
| `<F10>` / `<F11>` / `<F12>` | Step over / into / out |
| `<leader>de` | Evaluate expression (normal or visual mode) |
| `<leader>du` / `<leader>dq` | Toggle debugger UI / terminate |

Start debugging from a `.py` file. The launch picker offers current-file and
pytest-current-file configurations. For custom modules/arguments, use a project
`.vscode/launch.json` as supported by nvim-dap. Notebook cell debugging is not
part of this workflow; move code into a Python module and debug/test it there.

To rerun the real debugger/test checks using the disposable uv project:

```sh
~/.local/share/nvim/python/bin/python tests/python_tools.py '/tmp/test project'
```

This test creates `test_pde_smoke.py` (one intentionally failing test) and
`pde_debug.py`, then verifies LSP interpreter selection/restart, both pytest
results, a debugpy breakpoint, and the running debuggee's interpreter.


## Variable explorer

Restart Neovim after updating this config and start a fresh kernel with `Space j i`.
For an already running session, stop its old kernel with `Space j q` first. The
explorer needs the connection registration supplied by this config's launcher;
it does not attach to arbitrary kernels by guessing the newest connection file.

Run a cell, then press **`Space j V`** (uppercase V), or `:MoltenVariables`, from
the notebook. A right-hand split shows a snapshot of that kernel's user variables.
It also works from a `.py` buffer attached to a kernel started through this config.

The pane sits beside your notebook on wide screens and below it on narrow screens;
it adapts when the editor is resized. Press `?` for help at any time.
Slice prompts show the actual tensor expression and valid zero-based ranges:
for `X` shaped `64 × 1 × 28 × 28`, `t` asks for `X[a, b, :, :]`, with
`a=0–63` and `b=0–0`. Enter `5, 0` to inspect the sixth item's only channel.
The table's page counters are one-based positions; `t` and `g` use zero-based indices.
`R` is labelled **custom view**. `p` opens a full-source chart; `P` keeps the quick fetched-page plot.

| In the explorer | Action |
| --- | --- |
| `j` / `k`, `/` | Move and search this page using Vim navigation |
| `Enter` | Drill into a variable/child, or open the selected cell's value text |
| `i` | Open a complete tensor, NumPy, or PIL image |
| `u` / Backspace | Return to the previous view, preserving its selection |
| `r` | Refresh the current snapshot |
| `h` / `l`, Tab / Shift-Tab | Select a table column |
| `f` | Filter namespace names/types, or the selected DataFrame/Series column |
| `s` | Toggle namespace name/type ordering; cycle table ascending/descending/reset |
| `H` | Include hidden names in the namespace |
| `]p` / `[p` | Next/previous page: 100 variables or 20 detail rows |
| `]c` / `[c` | Next/previous group of columns, sized to the pane (up to 8) |
| `g` | Jump to zero-based `row, column` (or just `row`) |
| `t` | Choose leading tensor/array indices, e.g. `1, 2` for a 4D tensor |
| `p` / `P` | Full-source chart / quick current-page plot |
| `R` | Apply a named custom renderer; blank restores the standard view |
| `y` | Copy the selected value text |
| `q` / Esc | Close the explorer or value/plot popup |

`:MoltenInspect tensor_name` opens a named variable directly from the notebook.
Names are looked up literally; this command does not evaluate expressions such
as `model.parameters()` or `data[0]`. Enter traverses dictionaries, lists, tuples,
and stored object fields through structural paths. Properties and custom `repr`
methods are not evaluated. Unsupported dictionary keys and sets have previews but
cannot be traversed. Modules, functions, classes, and hidden names are excluded
from the namespace by default; the list is paginated rather than capped at 200.

For a typical training session:

1. Run the cell defining your tensors and metrics, then `Space j V`.
2. Press `f`, enter `metrics`, and Enter to open the matching DataFrame.
3. Use `h`/`l` to choose `loss`, then `s` to sort. Press `f` and enter `> 0.2`
   to filter it. Other predicates include `contains train`, `== "valid"`, `!=`,
   `>=`, and `<=`; blank clears the filter. These operations affect the view only.
4. Press `p` to open a chart immediately from the original variable or selected
   tensor slice. The large preview shares the image viewer's `+`/`-` zoom,
   `hjkl`/arrow pan, and `0` fit controls. Status and sampling appear at the bottom.
   Choose `t`ype, `x` column, or `y` columns (toggle, then Done); confirmed changes
   redraw automatically. Cancelling a selection preserves the current chart.
   `s` opens settings: `g` row range, `d` sampling budget, `n` histogram bins,
   `L` title/axis labels, and `a` legend. `?` shows all controls and limits.
   `q`/Esc closes the overlay first, then the viewer back to the explorer.
   `r` refreshes the source and chart; `b` opens the interactive browser chart;
   `e` exports PNG, SVG, self-contained HTML or Vega-Lite JSON.
   The previous chart remains visible during updates, explicitly marked as such;
   failed updates retain it with an error and disable export/browser until retry.
   Explorer filtering and sorting do not alter this plot source. Use `P` for a
   quick plot limited to the fetched table page.
5. Return with `q`, then `u` to your previous view. Open a 4D tensor and press `t`
   to choose the first two indices; the last two axes form the table.

PyTorch tensors show shape, dtype, device, and gradient status. NumPy arrays and
pandas tables retain their shape and labels. Table columns fit the pane; long
values are visually abbreviated and floating-point numbers use six significant digits.
Integers and numeric-looking strings preserve their text. Enter
opens the underlying value text, preserving newlines/tabs; `y` also copies directly
from that popup. Text is bounded at
4,000 characters per table cell and 10,000 for scalar strings, with an explicit
truncation marker. Copy uses that bounded text, not the abbreviated table display.
DataFrame sort/filter is limited to 100,000 rows; narrow larger data in Python.

Snapshots do **not** automatically refresh after execution. Press `r` for current
values. Browsing the namespace does not fetch tensor values. Explicitly opening
or refreshing a tensor copies at most 20 × 8 elements to CPU; on a GPU this may
synchronize pending work. Higher-dimensional tensors start at zero in leading
axes. Sparse, quantized, and meta tensors show metadata only. Physical GPU
transfers have not been verified on this test host.

### Complete image viewer

Select `X` and press **`i`**, either in the variable list or its detail view.
For a tensor shaped `64 × 1 × 28 × 28`, this opens the **complete 28 × 28 image**
from batch index zero. Table pagination does not limit this viewer.

| In the image viewer | Action |
| --- | --- |
| `+` / `=` / `-` | Zoom in / out around the viewport center |
| `0` | Fit and center the complete image |
| `h` / `j` / `k` / `l`, arrows | Pan; use counts such as `3l` for larger steps |
| `]` / `[` | Next / previous image in the batch |
| `g` | Jump directly to a zero-based batch index |
| `c` | Choose an individual channel or a color composite |
| `n` | Toggle original display and min/max contrast normalization |
| `L` | Choose the dimension layout explicitly |
| `r` | Reload the image from the kernel |
| `o` | Open the complete PNG externally |
| `e` | Export the complete PNG without overwriting an existing file |
| `?` | Toggle persistent help; `q` / Esc returns from help |
| `q` / Esc | Return to the explorer |

Supported layouts are `HW`, `CHW`, `HWC`, grayscale batches `BHW`, and color
batches `NCHW`/`NHWC`. Common layouts are inferred; ambiguous channel-first
versus grayscale-batch shapes prompt for a choice. `L` always lets you override
the interpretation. PIL images retain palette transparency and alpha when present.
NumPy is required in the project kernel; PIL support additionally requires Pillow.

**Original display** maps floating-point and boolean values from 0–1, and integer
values from 0–255, to display pixels. Values outside that range clip; the header
reports clipping. **Contrast display** maps the selected image's finite color
minimum/maximum to black/white using a shared range across color channels.
Constant images become black; alpha is preserved rather than contrast-scaled.
Nonfinite color components display as black. These are display conversions;
the source tensor/array is never modified, and no training normalization is
automatically reversed. The viewer produces an 8-bit PNG preview.

One complete image (or selected channel) is copied from the GPU to CPU on request,
which can synchronize GPU work. Zoom, pan, and window resizing operate on the
cached PNG locally; they do not query the kernel or repeat GPU transfers.
Images are limited to four million pixels;
larger images must be resized in Python. Sparse, quantized, meta, complex, and
empty tensors are rejected with an explanation.

Images start enlarged and centered to fit the viewer. Zoom is labelled relative
to that fit (`2× fit`, for example), up to 32×. Zooming out continues until the
image's longest edge is one rendered pixel; there is no percentage-based floor. Nearest-neighbor
scaling keeps individual pixels crisp. Panning stops at the edges, and the
bottom status strip reports visible pixel coordinates with zero-based, inclusive endpoints.
Transparent images show a checkerboard. Batch, channel, and contrast changes
retain zoom and position for comparison; changing the dimension layout resets
to fit. Resizing preserves relative zoom and clamps the position to the image.
`o` always opens the complete original PNG preview, regardless of zoom/pan.
Original tensor-value pixel inspection is not implemented yet.

Inline display uses the existing Snacks image support. The external PNG fallback
works when terminal image support is unavailable. PNGs are temporary previews;
only the most recent 16 are retained, and they are removed on normal Neovim exit.
The user confirmed baseline inline image display in their terminal. The zoom
update is checked with pixel-level tests, real Neovim controls, and simulated
terminal-placement callbacks; direct native screenshots remain unavailable
because the computer-use tool denied access to Ghostty.

### Custom renderers

Define a renderer in a notebook cell, run it, then inspect an object and press `R`
to select its registered name. For example:

```python
__nvim_inspect_renderers__ = {
    "training": lambda value: {
        "columns": ["metric", "value"],
        "rows": [[name, score] for name, score in value.items()],
        "note": "Training summary",
    }
}
```

Renderers return `rows` (a list of lists/tuples), optional `columns`, and optional
`note`. Returned data supports paging, selected-cell inspection, copy, and numeric
plots. Up to 10,000 returned rows are accepted. Renderer functions are **explicit,
trusted Python code**: they can mutate state or perform expensive work, unlike
standard structural inspection. Keep their computation bounded. Table sort/filter
is available for standard DataFrame/Series views, not renderer results.

Busy kernels produce a timeout message instead of being interrupted. A queued
inspection may still finish when the running cell ends; it does not add execution
history. Refresh when idle. Restarted/stopped kernels are checked before accepting
results; reopen the pane from a different notebook to inspect its kernel.

### Implementation and compatibility

`lua/custom/python/variables.lua` manages the pane and calls
`lua/custom/python/helpers/inspect-kernel.py`
using the existing editor Python host. That client loads `inspect-namespace.py`
inside the exact project kernel using a silent, history-free expression. No new
plugin or project dependency is required beyond the existing `ipykernel`.

The launcher uses a small `IPythonKernel` subclass to suppress **only our inspector
client's** busy/idle broadcasts. Molten otherwise mistakes those messages for
cell execution events. Normal notebook execution retains its normal messages.
This uses ipykernel's protected `_publish_status` hook and should be regression
tested on ipykernel upgrades. The pane also polls its source through Molten's
existing tick function while focused, because Molten normally polls only the
current buffer. Installed Molten files are not patched.

Each Neovim process gets its own private launch spec and each kernel launch gets
a registry/generation identifier. Temporary specs are removed on normal editor
exit. Source, outputs, namespace names, and execution counts are covered by tests.
The integration test also covers CPU tensors, empty/scalar/3D/meta values,
noncontiguous NumPy arrays, paging, multiple kernels, timeouts, restart, and stop.
Physical GPU transfers have not been verified on this test host.
The adapter was exercised with ipykernel 6.30.1 and 7.3.0.

```sh
~/.local/share/nvim/python/bin/python tests/variables.py /path/to/disposable-project
~/.local/share/nvim/python/bin/python tests/variables_workspace.py /path/to/disposable-project /tmp/variable-review
/path/to/disposable-project/.venv/bin/python tests/variable_values.py
~/.local/share/nvim/python/bin/python tests/image_viewer.py /path/to/disposable-project /tmp/image-review
/path/to/disposable-project/.venv/bin/python tests/image_values.py
make test-python FILE=image_viewport
```

The disposable project's `.venv` needs `ipykernel`, `numpy`, `pandas`, and `torch`.
The image tests additionally use Pillow to verify decoded PNG pixels and PIL objects.

## Reading long outputs

Inline previews show up to 16 lines. Floating output windows show up to 24 rows
and 120 columns, with rounded borders and success/error colors. These limits
control the preview size; the complete captured text remains available. A footer
shows additional lines when the floating window reaches its height limit (space
near the bottom of the editor can limit the window further).

- `Space j o`: preview the active cell's output.
- `Space j e`: open **and enter** the floating output in one press. If the
  output anchor is off-screen, this scrolls to reveal the cell end. A split too
  small for output produces a message asking you to enlarge it.
- Inside output: `j`/`k`, `Ctrl-d`/`Ctrl-u`, `gg`/`G`, and `/` navigate/search normally.
- `gw` toggles wrapping in that output window. Wrapping starts off to preserve
  table columns; `zH`/`zL` scroll wide tables horizontally.
- `q` or `Esc` closes the output and returns to the originating code window.
- `Space j O` (uppercase O) opens the complete output in a normal bottom split.
  This also works from inside the floating output. The split is a read-only
  snapshot, so it stays stable when you change cells or rerun code; reopen it to
  capture updated output. Normal window resizing/maximizing works here.
- `Space j y`, from the code cell, copies its output to the system clipboard.

The snapshot includes the execution header and text output; plots and HTML still
use `Space j p` and `Space j b`. Closing a snapshot removes its temporary buffer.

Regression test (uses a disposable project with ipykernel):

```sh
~/.local/share/nvim/python/bin/python tests/output.py '/tmp/test project'
```

## Plots in Ghostty (with or without tmux)

Molten shares the existing Snacks image renderer with Markdown. ImageMagick
(`brew install imagemagick`) handles image processing. Notebook images are
bounded to 100 columns by 20 rows, independently of Markdown image sizes.
`:checkhealth custom.python` reports the selected renderer; `:checkhealth snacks`
checks graphics support.

No global tmux configuration change is needed. Snacks automatically enables
`allow-passthrough all` for its current pane, just as it does for Markdown.
This setting includes hidden-pane output and can remain after Neovim exits;
it does not enable passthrough in all other panes. Ghostty without tmux uses
Snacks directly.

A local adapter (`lua/custom/python/snacks_canvas.lua`) keeps inline and floating
placements separate and fixes cleanup in Molten's bundled Snacks adapter. It
uses Molten's existing RPC interface without editing installed plugin files.
Unsupported terminals and headless sessions retain text/external output.

Restart Neovim after installing the plugin. Initialize a fresh kernel with
`Space j i` (stop an existing kernel with `Space j q` first). The kernel uses the
project `.venv`; install plotting packages there:

```sh
uv add matplotlib seaborn
uv add --dev ipykernel
```

Run this cell with `Space j c`:

```python
# %%
import matplotlib.pyplot as plt
plt.plot([1, 2, 3], [1, 4, 2])
plt.show()
```

The kernel defaults to Matplotlib's inline backend, including Seaborn plots.
`Space j o` previews output; `Space j e` enters it; `Space j p` opens the full
image externally. `Space j s` saves PNG outputs into the notebook. The `Space j O`
text snapshot does not render images. A deliberate `%matplotlib` backend change
in a cell overrides the default; `%matplotlib inline` restores it.

Interactive Plotly charts open in the browser, not inside terminal images:

```sh
uv add plotly nbformat
```

```python
# %%
import plotly.graph_objects as go
fig = go.Figure(go.Scatter(x=[1, 2, 3], y=[1, 4, 2]))
fig.show(renderer="notebook")
```

Use `Space j b` on that cell to open its HTML output, with zoom and hover.
The explicit renderer avoids needing Plotly in the editor's Python host.
Other libraries must emit a supported image or HTML representation; terminal
output does not provide Jupyter widgets.

Plot payload regression test (disposable project with the packages above):

```sh
~/.local/share/nvim/python/bin/python tests/plots.py '/tmp/test project'
```

To test the actual Snacks graphics path in disposable terminals (protocol capture,
not visual Ghostty inspection), after running the plot payload test:

```sh
~/.local/share/nvim/python/bin/python tests/snacks_plots.py '/tmp/test project'
~/.local/share/nvim/python/bin/python tests/snacks_plots.py '/tmp/test project' --tmux
```

The tmux test uses a private server and lets Snacks configure only its test pane.
Text, tables and tracebacks remain in Molten's navigable output buffers. Snacks
handles plot rendering and the existing notification UI; it does not provide a
browser engine for Plotly or Jupyter widgets.


## Rendered Markdown cells

Markdown cells in `.ipynb` files (and existing Python percent notebooks) render
on open using the same render-markdown styling as `.md` files. Headings, emphasis,
lists, tables, quotes and fenced code are rendered. Snacks handles images,
LaTeX and Mermaid with the same converters as normal Markdown. Pasted PNG/JPEG/GIF
notebook attachments are read from the notebook JSON and cached for display.

- Move into a Markdown cell to reveal the **whole cell's** editable source,
  including the comment prefixes. Move onto the cell-marker line to edit its
  `# %% [markdown]` source.
- Move back into code or another cell to render it again.
- `Space j m` toggles Markdown rendering for the current notebook.
- Add Markdown with `# %% [markdown]`, followed by commented Markdown lines.
  Use `#` for a blank Markdown line. Editing and undo operate on the original
  percent text; rendering never writes to the notebook.

Python completion, formatting, execution and saved notebook JSON keep the same
workflow. A kernel is not needed for Markdown rendering. Images/math/diagrams
still need terminal support and the existing Snacks conversion dependencies.
HTML widgets are not browser-rendered inside Neovim.

The implementation in `lua/custom/python/markdown.lua` parses hidden, per-cell
Markdown buffers and projects decorations onto the Python buffer. It does not
inject Markdown into, or patch, Python's parser. This small adapter uses internal
render-markdown context/handler APIs from the version pinned in `lazy-lock.json`;
rerun the checks when updating that plugin. When one notebook is shown in several
windows, source reveal follows the active window and is shared across them.

Verification (use a disposable project; media checks need ImageMagick, tectonic
and mmdc):

```sh
~/.local/share/nvim/python/bin/python tests/notebook_markdown.py '/tmp/test project'
~/.local/share/nvim/python/bin/python tests/notebook_markdown_media.py '/tmp/test project'
~/.local/share/nvim/python/bin/python tests/notebook_markdown_media.py '/tmp/test project' --tmux
```

The text test checks Neovim's rendered UI grid as well as decorations, code-cell
isolation and save/undo preservation. Media tests check real conversion and
Kitty graphics transmission in disposable terminals, not visual Ghostty screenshots.


## Cell boundaries

Each percent cell has one full-width separator with its number and type.
Code uses the theme's information color, Markdown its accent color, and raw
cells the warning color. The active cell has a brighter rule and an `active`
label. Numbers are document positions, not execution counts.

```text
─ 01 · Markdown ─────────────────────────────────
  Introduction
  Rendered Markdown content
━ 02 · Code · active ────────────────────────────
  print("hello")
  Out[1]: hello
─ 03 · Raw ──────────────────────────────────────
  Raw content
```

Headers replace the displayed `# %%` marker, including long metadata. Moving
onto the marker reveals the editable source underneath its header. Entering a
Markdown cell reveals its complete source in a readable foreground color.
Separators are decorations: they never enter notebook saves, copied source or
execution input. Molten continues to own output layout.

The separator follows the available text width; very narrow windows use `C`,
`M`, `R` and `*` for the active cell. Wrapped Markdown breaks at word boundaries.
That window option is restored when rendering is disabled or the buffer is left.
Legacy whole-line `<font ...>text</font>` prompts display their text in reading
mode; their tags remain editable and literal fenced examples remain untouched.
This is deliberately limited support, not a general HTML renderer.

Notebook `.ipynb` buffers keep diagnostic signs, underlines and navigation floats,
but omit long inline diagnostic messages. `[d` / `]d` still open diagnostic details.
Ordinary Python diagnostics are unchanged.

Ordinary Python without percent markers receives no separators. Markdown rendering
can be toggled independently with `Space j m`. In multiple views of the same
notebook, the last focused window determines separator width and active state,
as with Markdown source reveal. Notebook metadata remains editable at the top.

The initial design took inspiration from [ipynb.nvim](https://github.com/ajbucci/ipynb.nvim).
The refined design uses single separators and retains Jupytext, Molten and Snacks.

Visual review used isolated Neovim grid captures, not screenshots of live Ghostty.
The critic scored the baseline 5.5, the revised design 9.0, then reviewed three
additional rounds covering long metadata, source contrast and concealed content.
`tests/capture_cells.py /tmp/review.png [columns] [source-prefix] [concealed]`
reproduces the fixture; its output rows are representative virtual lines. The
separate Molten/media tests exercise real execution and image placement.

```sh
~/.local/share/nvim/python/bin/python tests/cells_ui.py '/tmp/test project'
```


## Bracket and quote pairing

`nvim-autopairs` inserts closing brackets and quotes as you type, skips existing
single-character closers, and removes both characters when Backspace is pressed
inside an empty pair. Its Enter mapping is disabled (`map_cr = false`), preserving
the normal Python indentation behavior. Blink completion keeps its own mappings;
no nvim-cmp integration is installed.

Python triple quotes automatically insert the closing triple delimiter. Use End
(on a one-line string) or cursor movement to pass it: typing all three closing
quotes again can insert an extra quote with the plugin's default rules.

Run `tests/autopairs.py` with the Neovim Python host to check typed pairing in
Python and notebook buffers. `tests/python_indent.py` checks Enter separately.

## Full-source plot limits and rendering

The editor host uses Vega-Lite via `vl-convert-python`, installed by
`scripts/setup-python.sh`. No plotting package is added to project environments.
Line, scatter, histogram, and heatmap support real numeric DataFrames, Series,
NumPy arrays, and dense PyTorch tensors. For higher-dimensional values, select
leading indices with explorer `t` first. DataFrame indices are not implicit X:
choose a numeric column, or use zero-based source row positions.

Line/scatter budgets are rows per series (10–20,000); heatmap budgets count cells.
A separate 100,000-value extraction cap applies. Uniform row sampling includes
range endpoints and can miss spikes; each chart reports source/range/sample size.
Lines preserve source order and break at missing sampled values. Histograms use
shared bin edges and every finite selected value, rejecting ranges above 100,000
values rather than sampling. Heatmaps sample rows without averaging columns.
Only the first 512 columns are offered, with up to eight line/scatter/histogram
series. Numeric plotting uses floating-point values; very large integers may
lose precision, and magnitudes above 1e150 require rescaling in Python.

Browser charts embed data and JavaScript locally. Line/scatter/histogram support
hover, wheel zoom, drag pan and double-click reset; heatmaps support hover.
Inline preview starts with a native-resolution vector render. Zoom and pan use
smooth scaling of that pinned snapshot while moving, then redraw from the SVG
after a 350 ms pause following the last preview frame. Held keys coalesce into
the latest requested position while cached frames finish, avoiding cancellation
starvation. Resizing redraws at physical resolution; `r` reloads the chart
snapshot and forces a native redraw. Each moving frame uses the original native
snapshot, so repeated navigation does not accumulate blur. The redraw rasterizes only the visible region
(up to 8192 pixels per side and 24 million pixels), keeping text and lines smooth
without kernel reads. Browser zoom instead changes chart axes. Ordinary tensor
image inspection retains nearest-neighbor scaling for individual pixels. Exports preserve snapshots and never overwrite existing files.
Temporary snapshots are retained for the last eight draws and cleaned on exit;
export anything you want to keep. Confirmed setting changes redraw automatically; the last good chart remains
visible and marked as previous until the new chart is ready. Source variables, notebook text, execution history and
cell outputs are not modified by inspection or rendering.
