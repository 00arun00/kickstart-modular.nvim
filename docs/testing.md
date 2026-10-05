# Testing this configuration

Pytest collects Python tests and launches the existing Lua scripts directly in
headless Neovim. Lua assertions stay in Lua. Make is a thin convenience layer;
there is no second test runner or custom report format.

## Setup and commands

Requires macOS or Linux, Neovim 0.12.2, Make, and uv on PATH. uv supplies Python 3.12.

```sh
make test-setup          # uv sync --locked --only-group test into .test-venv
make test               # fast tests, without installed Neovim plugins
make test-integration   # installed editor/plugins required
make test-setup-kernel   # separate scientific Python environment
make test-kernel         # live Jupyter/debugger/rendering scenarios
make test-all            # all registered headless scenarios
make test-list           # pytest --collect-only, all suites
```

Standard pytest selection works for both languages:

```sh
make test-lua SUITE=all FILE=chainsaw
make test-python SUITE=integration FILE=dropbar
make test ARGS='-k viewport -x'
.test-venv/bin/python -m pytest -m 'integration and lua'
.test-venv/bin/python -m pytest -m 'fast or integration' -k 'not visual'
```

`SUITE` defaults to `fast`; `FILE` passes a pytest `-k` expression; `ARGS` passes
additional pytest options. Direct pytest also defaults to the fast marker via
`pytest.ini`. No matches is a nonzero exit, not an empty successful run.
Ordinary runs do not install dependencies. Tests run sequentially by default.

To enable the optional pre-commit hook, install pre-commit separately and run:

```sh
pre-commit install
pre-commit run nvim-tests --all-files
```

The hook runs `make test`, using the environment prepared by `make test-setup`.

## Dependencies

`pyproject.toml` declares three dependency groups, resolved together in `uv.lock`:

- `host`: the editor's Python provider and notebook helpers.
- `test`: pytest plus host dependencies for test-driving Neovim.
- `kernel`: scientific packages installed separately in `.test-kernel`.

`scripts/setup-python.sh` syncs only the host group into Neovim's data directory.
Test setup syncs only the test group into `.test-venv`. Kernel fixtures reference
`.test-kernel` as their disposable project's `.venv`. A shared lock does not mix
these environments. Linux Torch comes from an explicit CPU-only index; macOS
uses PyPI. There are no parallel requirements.txt exports to keep synchronized.

To update a dependency deliberately:

```sh
uv lock --upgrade-package pytest
make test-setup
# For changes affecting scientific packages:
make test-setup-kernel
```

Commit `pyproject.toml` and `uv.lock` together. `--locked` setup fails when they
are out of sync. The lock is marked generated for GitHub review.

## Integration prerequisites and isolation

Integration tests use installed Neovim plugins, Tree-sitter parsers, Mason tools,
and the registered Python provider. Prepare them through the normal config
setup: `scripts/setup-python.sh`, Lazy, Mason, Tree-sitter, and
`:UpdateRemotePlugins`. Existing scripts assume plugins under
`~/.local/share/nvim`; an incomplete installation may trigger normal editor setup.
Chainsaw checks also need Python, Rust/rustfmt, Clang++, LuaJIT, rg, and Mason's Ruff.

Each script receives a disposable project/config directory and isolated
state, cache, logs, and Jupyter runtime paths. Fast cases also receive an empty
Neovim data directory. Full-config cases retain installed plugin data. The small
subprocess helper enforces timeouts and kills the process group, including
remaining kernels/debug adapters. Plot-renderer fixtures generate their inputs
explicitly; they do not depend on another test having run first.

## Adding tests and reading results

Add native Python tests under `tests/python/test_*.py`, marked `python` and one
of `fast`, `integration`, or `kernel`. Existing standalone Lua/Python scenarios
are registered in `tests/cases.json`; an inventory test catches missing entries.
Each entry declares its suite, timeout, and any arguments/interpreter it needs.
`{project}` and `{artifacts}` arguments refer to the case's disposable paths.
The plot renderer's `prepare_plot` flag requests its input-generation fixture.
This registry is a migration bridge for existing scripts, not a new assertion
framework. Native Lua suites can adopt mini.test later when its structured
assertions/child-editor APIs are useful; it is not needed just to launch scripts.

Every invocation stores logs/artifacts under `.test-results/run-*` and writes a
standard JUnit `results.xml` there. Pass `--junitxml=path.xml` to override the report
location. A script is one pytest case, regardless of how many assertions it
contains. Counts are not line coverage. Failures show the script's output and
log location, including named stages where the script records them.

`make test-all` excludes the PTY/Ghostty media checks and Playwright browser check;
they need interactive/platform-specific setup. `tests/cases.json` lists these
under `manual`, with reasons. Screenshot capture utilities are also not tests.

## CI

Pull requests and pushes to `master` run one workflow, with separate Formatting,
Fast, Editor, Kernel/rendering, and CI result jobs visible in the main graph.
The heavy jobs provision plugins from `lazy-lock.json`, parsers, pinned Mason
tools, the Python host, Nerd Fonts, and (for kernel tests) ImageMagick 7 and the
scientific environment. `scripts/setup-ci.lua` is for disposable CI installations
only. uv downloads are cached; editor provisioning starts clean.

Lua and Python run in separate steps. Python still runs after Lua fails when
setup succeeded. Each suite requires both language reports and uploads its logs,
screenshots, `lua.xml`, and `python.xml`. The pinned `test-summary/action` reads
JUnit directly and displays counts and expandable failures in GitHub's Summary.
The final job combines those reports and fails for any failed/cancelled/skipped
required job or missing report. Job/step durations stay in GitHub's native UI;
there is no custom timing API client or failure-text classifier.

StyLua 2.5.2 checks formatting without installing plugins:

```sh
stylua --check .
stylua .                # apply formatting
```
