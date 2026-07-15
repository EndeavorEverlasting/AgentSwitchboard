#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_wsl=$(cd "$script_dir/.." && pwd -P)
template="$repo_wsl/templates/agent-wrapper.sh"
destination="$HOME/.local/agent-switchboard/bin"
execution_domain=linux-native
allow_windows_bridge=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination) destination="$2"; shift 2 ;;
    --execution-domain) execution_domain="$2"; shift 2 ;;
    --allow-windows-bridge) allow_windows_bridge=1; shift ;;
    --help) printf 'Usage: %s [--destination PATH] [--execution-domain windows-wsl|linux-native] [--allow-windows-bridge]\n' "$(basename "$0")"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -f "$template" ]] || { printf 'Wrapper template missing: %s\n' "$template" >&2; exit 1; }
case "$execution_domain" in windows-wsl|linux-native) ;; *) printf 'Unsupported execution domain: %s\n' "$execution_domain" >&2; exit 2 ;; esac
if [[ "$allow_windows_bridge" == 1 && "$execution_domain" != windows-wsl ]]; then
  printf 'Windows bridge permission is valid only for windows-wsl\n' >&2
  exit 2
fi
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
policy_temp="$destination/policy.env.tmp.$$"
printf 'execution_domain=%s\nallow_windows_bridge=%s\n' "$execution_domain" "$allow_windows_bridge" > "$policy_temp"
chmod 0600 "$policy_temp"
mv -f "$policy_temp" "$destination/policy.env"
printf 'installed %s\n' "$destination/policy.env"
