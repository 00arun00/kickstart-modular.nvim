#!/usr/bin/env bash
# Editor-only dependencies. Project dependencies stay in the project's .venv.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data_dir="${NVIM_PYTHON_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-nvim}}"
uv venv --python 3.12 --allow-existing "$data_dir/python"
uv pip sync --python "$data_dir/python/bin/python" "$script_dir/python-requirements.txt"
printf '\nPython host ready. Restart Neovim and run :UpdateRemotePlugins once.\n'
