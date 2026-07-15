#!/usr/bin/env bash
set -euo pipefail

invoked=$(basename "$0")
case "$invoked" in
  *_native) agent=${invoked%_native}; mode=native ;;
  *_win) agent=${invoked%_win}; mode=bridge ;;
  *) agent=$invoked; mode=canonical ;;
esac
case "$agent" in opencode|agy|goose) ;; *) printf 'Unsupported agent wrapper: %s\n' "$agent" >&2; exit 2 ;; esac

managed_dir=$(cd "$(dirname "$0")" && pwd -P)
policy_domain=""
policy_bridge=0
if [[ -f "$managed_dir/policy.env" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      execution_domain) policy_domain=$value ;;
      allow_windows_bridge) policy_bridge=$value ;;
    esac
  done < "$managed_dir/policy.env"
fi
execution_domain=${AGENT_SWITCHBOARD_DOMAIN:-$policy_domain}
allow_windows_bridge=${AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE:-$policy_bridge}
probe=false
if [[ "${1:-}" == "--agent-switchboard-probe" ]]; then probe=true; shift; fi

find_native() {
  local candidate resolved
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    resolved=$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")
    case "$resolved" in "$managed_dir"/*) continue ;; esac
    if [[ "$execution_domain" == windows-wsl ]]; then
      case "$resolved" in /mnt/[a-zA-Z]/*) continue ;; esac
    fi
    printf '%s\n' "$candidate"
    return 0
  done < <(type -aP "$agent" 2>/dev/null || true)
  return 1
}

run_native() {
  local candidate
  candidate=$(find_native) || { printf '%s native command is unavailable\n' "$agent" >&2; return 127; }
  if $probe; then exec "$candidate" --version; else exec "$candidate" "$@"; fi
}

run_bridge() {
  case "$agent" in
    opencode)
      command -v cmd.exe >/dev/null 2>&1 || { printf 'cmd.exe interop is unavailable\n' >&2; return 127; }
      if $probe; then exec cmd.exe /d /s /c "opencode.cmd --version"; else exec cmd.exe /d /s /c opencode.cmd "$@"; fi
      ;;
    agy|goose)
      local executable="${agent}.exe"
      command -v "$executable" >/dev/null 2>&1 || { printf '%s interop is unavailable\n' "$executable" >&2; return 127; }
      if $probe; then exec "$executable" --version; else exec "$executable" "$@"; fi
      ;;
  esac
}

case "$mode" in
  native) run_native "$@" ;;
  bridge) run_bridge "$@" ;;
  canonical)
    if native_candidate=$(find_native); then
      if $probe; then exec "$native_candidate" --version; else exec "$native_candidate" "$@"; fi
    fi
    if [[ "$allow_windows_bridge" == 1 ]]; then run_bridge "$@"; fi
    printf '%s has no healthy native command; set AGENT_SWITCHBOARD_ALLOW_WINDOWS_BRIDGE=1 only when the domain contract permits bridging\n' "$agent" >&2
    exit 127
    ;;
esac
