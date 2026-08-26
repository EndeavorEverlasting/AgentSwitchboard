#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

MODE="${1:-status}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-herdr-migration"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

value_or_missing() {
  command -v "$1" 2>/dev/null || printf 'missing'
}

require_termux() {
  [ -n "${PREFIX:-}" ] || fail 'PREFIX is unset; run this probe inside Termux'
  case "$PREFIX" in
    /data/data/com.termux/files/usr*) ;;
    *) fail "unexpected PREFIX '$PREFIX'; this probe is scoped to Termux" ;;
  esac
}

collect() {
  require_termux
  arch="$(uname -m 2>/dev/null || printf unknown)"
  kernel="$(uname -s 2>/dev/null || printf unknown)"
  android_release="$(getprop ro.build.version.release 2>/dev/null || true)"
  [ -n "$android_release" ] || android_release='unknown'

  herdr_path="$(value_or_missing herdr)"
  herdr_version='missing'
  herdr_help='unproved'
  if [ "$herdr_path" != 'missing' ]; then
    herdr_version="$(herdr --version 2>/dev/null | head -n 1 || true)"
    [ -n "$herdr_version" ] || herdr_version='version-readback-failed'
    if herdr --help >/dev/null 2>&1; then herdr_help='pass'; else herdr_help='fail'; fi
  fi

  tmux_path="$(value_or_missing tmux)"
  tmux_version='missing'
  if [ "$tmux_path" != 'missing' ]; then
    tmux_version="$(tmux -V 2>/dev/null || true)"
    [ -n "$tmux_version" ] || tmux_version='version-readback-failed'
  fi

  if [ "$herdr_path" = 'missing' ]; then
    decision='KEEP_TMUX_HERDR_NOT_INSTALLED'
    next_gate='install-herdr-by-reviewed-method-then-rerun-probe'
  elif [ "$herdr_help" != 'pass' ] || [ "$herdr_version" = 'version-readback-failed' ]; then
    decision='KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY'
    next_gate='resolve-binary-compatibility-before-server-test'
  else
    decision='HERDR_BINARY_CANDIDATE_ONLY'
    next_gate='live-server-detach-reattach-and-agent-state-proof'
  fi

  cat <<EOF
profile=android
frontend=termux
kernel=$kernel
arch=$arch
android_release=$android_release
herdr_path=$herdr_path
herdr_version=$herdr_version
herdr_help=$herdr_help
tmux_path=$tmux_path
tmux_version=$tmux_version
migration_decision=$decision
next_gate=$next_gate
proof_level=binary-readiness-only
EOF
}

case "$MODE" in
  status)
    collect
    ;;
  evidence)
    require_termux
    mkdir -p "$STATE_ROOT"
    out="$STATE_ROOT/herdr-readiness-$(date -u +%Y%m%dT%H%M%SZ).env"
    collect > "$out"
    cat "$out"
    printf 'EVIDENCE=%s\n' "$out"
    ;;
  contract)
    printf '%s\n' \
      'HERDR_MIGRATION_CONTRACT=PASS' \
      'CANONICAL_ANDROID_MULTIPLEXER=tmux' \
      'HERDR_ANDROID_STATUS=experimental-unproved' \
      'PROMOTION_REQUIRES=live-termux-persistence-agent-state-sprint-proof'
    ;;
  *)
    printf 'Usage: %s [status|evidence|contract]\n' "$0" >&2
    exit 64
    ;;
esac
