# Testing this configuration

Lua tests use mini.test; Python tests use pytest. Make provides the common entry
point. The initial migration keeps existing regression scripts intact: each is
one named framework case, executed in a fresh subprocess. New granular Lua tests
can be added under `tests/lua/test_*.lua`; Python tests belong under
`tests/python/test_*.py` with a `fast`, `integration`, or `kernel` marker.

## Setup

Requires macOS or Linux, Neovim 0.12.2, Python 3, Git, Make, and uv on PATH.

```sh
make test-setup
make test
```

Setup creates `.test-venv/` with hash-locked test dependencies and downloads
mini.nvim into `.test-deps/`, using the exact revision in `lazy-lock.json`.
It does not modify the editor's Python environment or install a Git hook.
The fast suite has an empty Neovim data directory: it works without your
installed plugins. Pre-commit runs this same suite.

To run the fast suite before each commit, install pre-commit separately, then:

```sh
pre-commit install
pre-commit run nvim-tests --all-files
```

The hook runs `make test`; it does not install dependencies during a commit.

## Commands

| Command | Runs |
| --- | --- |
| `make test` | Fast Lua and Python cases, including runner failure checks |
| `make test-lua` | Fast Lua cases |
| `make test-python` | Fast Python cases |
| `make test-integration` | Installed-plugin and editor integration cases |
| `make test-kernel` | Scientific Python, live kernel, and debugger cases |
| `make test-all` | All registered headless cases in all three suites |
| `make test-list` | Registered scripts, groups, and explicit manual exclusions |

The language targets accept `SUITE=integration`, `SUITE=kernel`, or `SUITE=all`.
A substring selects an existing script; unmatched selectors fail rather than
reporting an empty successful run:

```sh
make test-lua SUITE=all FILE=chainsaw
make test-python SUITE=all FILE=project_home
make test-python ARGS='-k viewport -x'
make test-python ARGS='--lf'
```

Python runner arguments go in `ARGS`. Logs, generated artifacts, and pytest JUnit
XML are retained under `.test-results/run-*`.
That directory is disposable. A failure in either language makes the shared
command fail; one failed suite does not prevent the other from reporting.

## Integration prerequisites

Integration tests intentionally use the locally installed Neovim plugins,
parsers, remote-plugin registration, Mason tools, and editor Python host.
Prepare those with the normal config setup (`scripts/setup-python.sh`, Lazy,
`:UpdateRemotePlugins`, Mason, and Treesitter). Existing legacy tests assume
plugins under `~/.local/share/nvim`. Unlike the fast suite, these runs may trigger
normal editor dependency installation if that setup is incomplete.

Chainsaw integration also needs Python 3, Rust/rustfmt, Clang++, LuaJIT, rg,
and Ruff; its assertion test expects Mason's Ruff installation. Kernel tests
require an additional isolated scientific environment:

```sh
make test-setup-kernel
make test-kernel
```

This creates `.test-kernel/` with locked dependencies (including PyTorch).
Linux x86-64 uses a separate CPU-only lockfile to avoid CUDA downloads.
Each kernel case gets a disposable project outside the checkout referencing
that environment as `.venv`. Projects are removed when their case finishes,
so Neotest and pytest cannot accidentally discover this repo instead. Renderer
tests generate their own plot inputs rather than depending on
test execution order. Missing dependencies fail; no automatic dependency skips
or downloads are performed by the runner itself.

Every case receives separate state/cache/log paths and a config path pointing
at this checkout, including when it is not your installed config. Full-config
cases retain access to installed plugin data. Child processes have timeouts;
the runner terminates their process groups, including remaining kernels and
debug adapters. Integration cases are run sequentially.

## Coverage and migration

`tests/cases.json` classifies every legacy script. An inventory test catches new
scripts that have not been registered. Capture utilities are not tests. The
existing PTY/Ghostty media checks and Playwright browser check remain explicit
manual runs with platform-specific setup; `make test-all` means all registered
headless tests, not these manual checks. `make test-list` names each exclusion.

Existing top-level scripts remain directly runnable. The initial reports are
per script; assertions inside a script are not yet individual cases. Splitting
those into native mini.test sets and pytest functions is a follow-up migration.
New native Lua test files are collected by mini.test alongside the wrappers.
They should be fast and independent of installed plugins; the legacy suite
classification applies only to scripts listed in the manifest.

To update locked Python dependencies deliberately:

```sh
uv pip compile tests/requirements.in --universal --python-version 3.12 --generate-hashes -o tests/requirements.txt
uv pip compile tests/kernel-requirements.in --universal --python-version 3.12 --generate-hashes -o tests/kernel-requirements.txt
make test-setup
make test-setup-kernel
```

## Continuous integration

Every push and pull request runs three Linux jobs: fast, integration, and kernel.
The heavier jobs install the editor Python host, plugins from `lazy-lock.json`,
Tree-sitter CLI/parsers, pinned Mason tools from `scripts/ci-tools.json`, and
remote-plugin registration on a clean runner. Screenshot tests use Nerd Fonts
v3.4.0 via `NVIM_TEST_FONT_DIR` (locally this defaults to `~/Library/Fonts`).
Each test gets a private Jupyter runtime directory. The kernel job also installs the
scientific project environment and a checksum-verified ImageMagick 7 binary.
uv downloads are cached; editor setup is rebuilt
so missing setup steps cannot be hidden by an existing plugin cache.

`scripts/setup-ci.lua` is only for disposable CI installations and requires
`CI=true`; do not run it against your personal editor data. Setup and test failures
fail the job, and each suite uploads separate logs/artifacts even on failure.
The pre-commit hook remains fast. Terminal/browser checks remain manual.

Update the Linux CPU lock with:

```sh
uv pip compile tests/kernel-requirements.in --python-version 3.12 --python-platform x86_64-unknown-linux-gnu --extra-index-url https://download.pytorch.org/whl/cpu --index-strategy unsafe-best-match --generate-hashes --emit-index-url -o tests/kernel-requirements-linux.txt
```
