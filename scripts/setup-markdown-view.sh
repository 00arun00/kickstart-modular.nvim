#!/usr/bin/env bash
# Optional rich-view tools, installed for Neovim without changing system packages.
set -euo pipefail

data_dir="${NVIM_MARKDOWN_VIEW_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-nvim}}"
tools_dir="$data_dir/markdown-view/bin"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/nvim-markdown-view.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

# Tested release archives. Digests are the publishers' GitHub release digests.
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    pandoc_archive=pandoc-3.13-arm64-macOS.zip
    pandoc_sha=f436d18bebbfb3ddd326597686dacab9fac5dc23bd060495020f35a28a43a7c3
    typst_target=aarch64-apple-darwin
    typst_sha=48f62ed034aa3a7978309579ac6ca00045e2ef0da73114e8af27cfd8e74dc05a
    ;;
  Darwin/x86_64)
    pandoc_archive=pandoc-3.13-x86_64-macOS.zip
    pandoc_sha=1823278715aa405aaf21b59cde5dc789346aa8d4fc307467f9a9ee84162bedc5
    typst_target=x86_64-apple-darwin
    typst_sha=7f9fdd9584866245de9a79e0add8f9236fae6f40a8a45e2c4771ccc14db4e0fa
    ;;
  Linux/x86_64)
    pandoc_archive=pandoc-3.13-linux-amd64.tar.gz
    pandoc_sha=38aa33b325a2bc96a4c39409631212db55702f564250bcdbead180b3bf646389
    typst_target=x86_64-unknown-linux-musl
    typst_sha=a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c
    ;;
  Linux/aarch64|Linux/arm64)
    pandoc_archive=pandoc-3.13-linux-arm64.tar.gz
    pandoc_sha=21e1d4ba09bd0b334590d204580fd4f6629b21be4ab6a32b26cc98982e9e0c68
    typst_target=aarch64-unknown-linux-musl
    typst_sha=5aa8d74a3d906e60ea12a66ac2f37f8eef1b14cbad7182a745e393a10c23dcee
    ;;
  *) printf 'Unsupported platform. Install Pandoc 3.13 and Typst 0.15.1 on PATH.\n' >&2; exit 1 ;;
esac

verify() {
  local archive="$1" expected="$2" actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$archive")"
  else
    actual="$(shasum -a 256 "$archive")"
  fi
  actual="${actual%% *}"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Checksum mismatch: %s\n' "$archive" >&2
    exit 1
  fi
}

curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 \
  "https://github.com/jgm/pandoc/releases/download/3.13/$pandoc_archive" -o "$work_dir/$pandoc_archive"
curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 \
  "https://github.com/typst/typst/releases/download/v0.15.1/typst-$typst_target.tar.xz" -o "$work_dir/typst.tar.xz"
verify "$work_dir/$pandoc_archive" "$pandoc_sha"
verify "$work_dir/typst.tar.xz" "$typst_sha"

case "$pandoc_archive" in
  *.zip) unzip -q "$work_dir/$pandoc_archive" -d "$work_dir" ;;
  *) tar -xzf "$work_dir/$pandoc_archive" -C "$work_dir" ;;
esac
tar -xJf "$work_dir/typst.tar.xz" -C "$work_dir"
pandoc_binary="$(find "$work_dir" -type f -path '*/bin/pandoc' -print -quit)"
test -n "$pandoc_binary"

# Validate both tools before replacing an existing Neovim-local installation.
pandoc_version="$("$pandoc_binary" --version)"
printf '%s\n' "${pandoc_version%%$'\n'*}"
"$work_dir/typst-$typst_target/typst" --version
mkdir -p "$tools_dir"
install -m 755 "$pandoc_binary" "$tools_dir/pandoc"
install -m 755 "$work_dir/typst-$typst_target/typst" "$tools_dir/typst"
printf '\nRich-view tools ready in %s\nRun :MarkdownView check in Neovim.\n' "$tools_dir"
