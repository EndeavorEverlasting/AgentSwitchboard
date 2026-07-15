#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_wsl=$(cd "$script_dir/.." && pwd -P)
template="$repo_wsl/templates/agent-wrapper.sh"
destination="$HOME/.local/agent-switchboard/bin"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) destination="$2"; shift 2 ;;
    --help) printf 'Usage: %s [--destination PATH]\n' "$(basename "$0")"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -f "$template" ]] || { printf 'Wrapper template missing: %s\n' "$template" >&2; exit 1; }
mkdir -p "$destination"
for agent in opencode agy goose; do
  for name in "$agent" "${agent}_native" "${agent}_win"; do
    target="$destination/$name"
    if [[ -f "$target" ]] && ! cmp -s "$template" "$target"; then cp -p "$target" "${target}.backup"; fi
    temp="${target}.tmp.$$"
    cp "$template" "$temp"
    chmod 0755 "$temp"
    mv -f "$temp" "$target"
    printf 'installed %s\n' "$target"
  done
done
