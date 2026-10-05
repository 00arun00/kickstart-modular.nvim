#!/usr/bin/env bash
# Editor-only dependencies. Project dependencies stay in the project's .venv.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data_dir="${NVIM_PYTHON_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-nvim}}"
UV_PROJECT_ENVIRONMENT="$data_dir/python" uv sync --project "$script_dir/.." --locked --only-group host
printf '\nPython host ready. Restart Neovim and run :UpdateRemotePlugins once.\n'
