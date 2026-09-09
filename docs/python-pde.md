# Python PDE

The editor uses basedpyright for types/completion, Ruff for linting and formatting,
Jupytext for notebook editing, and Molten for Jupyter execution. NotebookNavigator
adds `# %%` cell movement and execution in both `.py` and `.ipynb` buffers.

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
| `<leader>jl` | Run line |
| `<leader>jv` (visual) | Run selection |
| `<leader>jo` / `<leader>je` / `<leader>jh` | Show / enter / hide output |
| `<leader>jx` / `<leader>jr` / `<leader>jq` | Interrupt / restart / stop kernel |
| `<leader>jI` | Import previously saved outputs after initializing |
| `<leader>js` | Save notebook source and export current outputs |
| `<leader>jb` / `<leader>jp` | Open HTML output / plot externally |
| `<leader>f` | Format and organize imports with project Ruff |

Execution is always explicit. Text outputs appear inline; inline graphics are
not enabled because they depend on terminal support. Molten's output import/export
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
