#!/data/data/com.termux/files/usr/bin/bash
set -eu

REPOSITORY_URL="https://github.com/EndeavorEverlasting/AgentSwitchboard.git"
REPOSITORY_SSH_URL="git@github.com:EndeavorEverlasting/AgentSwitchboard.git"
REPO_ROOT="${AGENT_SWITCHBOARD_REPO:-$HOME/dev/AgentSwitchboard}"
REF="main"
PLAN=0

usage() {
  cat <<'EOF'
Bootstrap the AgentSwitchboard Android terminal client for Termux

Usage:
  Bootstrap-AgentSwitchboard-Termux.sh [--repo PATH] [--ref BRANCH] [--plan]

This installs the phone-side terminal-client package floor, safely acquires or
fast-forwards the AgentSwitchboard source checkout, and installs the Android
terminal launcher as $PREFIX/bin/agentswitchboard-phone.

It does not install or certify the Windows-first AgentSwitchboard orchestration
runtime, GNHF fleet, coding agents, providers, authentication, or a remote
workspace host.
EOF
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

run_logged() {
  step="$1"
  failure_code="$2"
  shift 2
  log_path="$LOG_ROOT/${step}.log"
  if "$@" >"$log_path" 2>&1; then
    printf '[PASS] step=%s log=%s\n' "$step" "$log_path"
    return 0
  fi
  command_rc=$?
  printf '[FAIL] step=%s command_exit=%s launcher_exit=%s log=%s\n' \
    "$step" "$command_rc" "$failure_code" "$log_path" >&2
  tail -n 20 "$log_path" >&2 || true
  exit "$failure_code"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || fail "--repo requires a path"
      REPO_ROOT="$2"
      shift 2
      ;;
    --ref)
      [ "$#" -ge 2 ] || fail "--ref requires a branch"
      REF="$2"
      shift 2
      ;;
    --plan)
      PLAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$REF" in
  ''|*[!A-Za-z0-9._/-]*) fail "invalid ref: $REF" ;;
esac

if [ "$PLAN" -eq 1 ]; then
  printf 'PLAN profile=android capability_status=terminal-client-implemented role=terminal-client frontend=termux repo=%s ref=%s packages=git,openssh,tmux,curl launcher=%s/bin/agentswitchboard-phone native_orchestration_runtime=unimplemented\n' \
    "$REPO_ROOT" "$REF" "${PREFIX:-\$PREFIX}"
  exit 0
fi

[ -n "${PREFIX:-}" ] || fail "PREFIX is not set; run this inside Termux"
command -v pkg >/dev/null 2>&1 || fail "pkg is unavailable; use a supported Termux installation"

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android"
LOG_ROOT="$STATE_ROOT/bootstrap-logs"
mkdir -p "$LOG_ROOT"

printf '[INFO] Installing the Android terminal-client package floor.\n'
run_logged package-install 61 pkg install -y git openssh tmux curl

mkdir -p "$(dirname "$REPO_ROOT")"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    "$REPOSITORY_URL"|"$REPOSITORY_SSH_URL") ;;
    *) fail "existing checkout has unexpected origin: ${origin:-missing}" ;;
  esac
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail "existing checkout is dirty: $REPO_ROOT"
  current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ "$current_branch" = "$REF" ] || fail "existing checkout branch is '$current_branch'; expected '$REF'"
  run_logged repository-fetch 63 git -C "$REPO_ROOT" fetch --prune origin "$REF"
  run_logged repository-fast-forward 64 git -C "$REPO_ROOT" merge --ff-only "origin/$REF"
else
  [ ! -e "$REPO_ROOT" ] || fail "repo path exists but is not a Git checkout: $REPO_ROOT"
  run_logged repository-clone 62 git clone --branch "$REF" --single-branch "$REPOSITORY_URL" "$REPO_ROOT"
fi

launcher_source="$REPO_ROOT/tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
[ -f "$launcher_source" ] || fail "Android terminal-client launcher missing from checkout: $launcher_source"
bash -n "$launcher_source"

install -m 0755 "$launcher_source" "$PREFIX/bin/agentswitchboard-phone"
"$PREFIX/bin/agentswitchboard-phone" status >/dev/null
"$PREFIX/bin/agentswitchboard-phone" local-shell --plan >/dev/null
"$PREFIX/bin/agentswitchboard-phone" remote example-host \
  --host-profile posix-tmux \
  --repo /srv/AgentSwitchboard \
  --expected-origin "$REPOSITORY_URL" \
  --plan >/dev/null

{
  printf 'profile=android\n'
  printf 'capability_status=terminal-client-implemented\n'
  printf 'role=terminal-client\n'
  printf 'frontend=termux\n'
  printf 'transport=ssh\n'
  printf 'local_tmux_scope=device-local-only\n'
  printf 'repo=%s\n' "$REPO_ROOT"
  printf 'repo_purpose=source-and-terminal-client-files-not-runtime-proof\n'
  printf 'ref=%s\n' "$REF"
  printf 'launcher=%s\n' "$PREFIX/bin/agentswitchboard-phone"
  printf 'bootstrap_logs=%s\n' "$LOG_ROOT"
  printf 'native_orchestration_runtime=unimplemented\n'
  printf 'native_agent_runtime=unproved\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'proof=terminal-client-installed-command-probes\n'
} > "$STATE_ROOT/bootstrap-result.env"

printf '[PASS] Android terminal client installed.\n'
printf '[LIMIT] Full AgentSwitchboard runtime is not configured on this phone.\n'
printf '[NEXT] Inspect the capability ceiling: agentswitchboard-phone status\n'
printf '[OPTIONAL] Phone-local shell only: agentswitchboard-phone local-shell\n'
printf '[REMOTE] A remote workspace requires a classified host, repository path, expected origin, and successful preflight.\n'
