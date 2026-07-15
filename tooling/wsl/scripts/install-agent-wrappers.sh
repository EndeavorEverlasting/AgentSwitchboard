#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_wsl=$(cd "$script_dir/.." && pwd -P)
template="$repo_wsl/templates/agent-wrapper.sh"
destination="$HOME/.local/agent-switchboard/bin"
execution_domain=linux-native
allow_windows_bridge=0
force=0

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    printf '%s requires a value\n' "$option" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      require_value "$1" "${2:-}"
      destination="$2"
      shift 2
      ;;
    --execution-domain)
      require_value "$1" "${2:-}"
      execution_domain="$2"
      shift 2
      ;;
    --allow-windows-bridge)
      allow_windows_bridge=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --help)
      printf 'Usage: %s [--destination PATH] [--execution-domain windows-wsl|linux-native] [--allow-windows-bridge] [--force]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[[ -f "$template" ]] || {
  printf 'Wrapper template missing: %s\n' "$template" >&2
  exit 1
}
case "$execution_domain" in
  windows-wsl|linux-native) ;;
  *)
    printf 'Unsupported execution domain: %s\n' "$execution_domain" >&2
    exit 2
    ;;
esac
if [[ "$allow_windows_bridge" == 1 && "$execution_domain" != windows-wsl ]]; then
  printf 'Windows bridge permission is valid only for windows-wsl\n' >&2
  exit 2
fi

mkdir -p "$destination"

install_managed_file() {
  local source="$1"
  local target="$2"
  local mode="$3"

  if [[ -e "$target" || -L "$target" ]]; then
    if cmp -s "$source" "$target"; then
      printf 'unchanged %s\n' "$target"
      return 0
    fi
    if [[ "$force" != 1 ]]; then
      printf 'preserving existing %s (use --force to replace)\n' "$target"
      return 0
    fi
    local backup="${target}.backup"
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
      cp -p -- "$target" "$backup"
      printf 'backed up %s -> %s\n' "$target" "$backup"
    else
      printf 'preserving existing backup %s\n' "$backup"
    fi
  fi

  local temp="${target}.tmp.$$"
  trap 'rm -f -- "$temp"' RETURN
  cp -- "$source" "$temp"
  chmod "$mode" "$temp"
  mv -- "$temp" "$target"
  trap - RETURN
  printf 'installed %s\n' "$target"
}

for agent in opencode agy goose; do
  for name in "$agent" "${agent}_native" "${agent}_win"; do
    install_managed_file "$template" "$destination/$name" 0755
  done
done

policy_source=$(mktemp)
trap 'rm -f -- "$policy_source"' EXIT
printf 'execution_domain=%s\nallow_windows_bridge=%s\n' "$execution_domain" "$allow_windows_bridge" > "$policy_source"
install_managed_file "$policy_source" "$destination/policy.env" 0600
