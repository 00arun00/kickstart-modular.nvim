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
Private kernelspecs live under `stdpath('data')/jupyter/kernels/nvim-*`; two
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

This workflow targets local Python notebooks; use a notebook frontend for rich
widget interaction or other notebook languages.

## Verification

```sh
XDG_STATE_HOME=/tmp/nvim-test-state nvim --headless -u NONE -l tests/venv.lua
# Prepare a disposable project with uv and ipykernel/ruff as above, then:
~/.local/share/nvim/python/bin/python tests/notebook.py '/tmp/test project'
stylua --check lua/custom/python lua/custom/plugins/notebooks.lua tests/venv.lua init.lua
```

The integration test creates `pde-smoke.ipynb` and `pde-new.ipynb` in the supplied
disposable project. It checks notebook metadata/output preservation, formatting,
real kernel execution, interpreter/cwd selection, output export, and reopening.
