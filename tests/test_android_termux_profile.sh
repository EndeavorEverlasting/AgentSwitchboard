#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
BOOTSTRAP="$ROOT/Bootstrap-AgentSwitchboard-Termux.sh"

fail() {
  label="$1"
  shift
  message="$*"
  escaped="${message//'%'/'%25'}"
  escaped="${escaped//$'\r'/'%0D'}"
  escaped="${escaped//$'\n'/'%0A'}"
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::error title=Android Termux shell contract/%s::%s\n' "$label" "$escaped" >&2
  fi
  printf '[FAIL] %s: %s\n' "$label" "$message" >&2
  exit 1
}

expect_contains() {
  label="$1"
  haystack="$2"
  needle="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$label" "missing '$needle'; output=$haystack" ;;
  esac
}

run_success() {
  label="$1"
  shift
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "$label" "exit=$rc output=$output"
  printf '%s' "$output"
}

run_failure() {
  label="$1"
  shift
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$label" "expected failure; output=$output"
  printf '%s' "$output"
}

bash -n "$BOOTSTRAP" || fail parse-bootstrap "Bash parser rejected $BOOTSTRAP"
bash -n "$LAUNCHER" || fail parse-launcher "Bash parser rejected $LAUNCHER"

status_output="$(run_success status bash "$LAUNCHER" status)"
expect_contains status-role "$status_output" 'role=terminal-client'
expect_contains status-local-role "$status_output" 'local_tmux_role=local-shell-only'
expect_contains status-continuity "$status_output" 'continuity_scope=device-local-only'
expect_contains status-runtime "$status_output" 'native_orchestration_runtime=unimplemented'

local_plan_output="$(run_success local-plan bash "$LAUNCHER" local-shell --session dev-1 --plan)"
expect_contains local-plan-role "$local_plan_output" 'role=local-shell-only'
expect_contains local-plan-mode "$local_plan_output" 'mode=local-shell'
expect_contains local-plan-continuity "$local_plan_output" 'continuity_scope=device-local-only'
expect_contains local-plan-session "$local_plan_output" 'session=dev-1'

remote_plan_output="$(run_success remote-plan bash "$LAUNCHER" remote user@example-host --host-profile posix-tmux --repo /srv/AgentSwitchboard --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git --session dev --plan)"
expect_contains remote-plan-role "$remote_plan_output" 'role=terminal-client'
expect_contains remote-plan-topology "$remote_plan_output" 'topology=android-termux-ssh-posix-workspace-client'
expect_contains remote-plan-profile "$remote_plan_output" 'host_profile=posix-tmux'
expect_contains remote-plan-target "$remote_plan_output" 'target=user@example-host'

option_output="$(run_failure reject-option-target bash "$LAUNCHER" remote -V --host-profile posix-tmux --repo /srv/AgentSwitchboard --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git --plan)"
expect_contains reject-option-target-message "$option_output" 'invalid SSH target: -V'

unclassified_output="$(run_failure reject-unclassified-host bash "$LAUNCHER" remote user@example-host --repo /srv/AgentSwitchboard --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git --plan)"
expect_contains reject-unclassified-message "$unclassified_output" 'requires --host-profile posix-tmux'

session_output="$(run_failure reject-invalid-session bash "$LAUNCHER" local-shell --session 'bad session' --plan)"
expect_contains reject-invalid-session-message "$session_output" 'invalid tmux session name'

bootstrap_plan_output="$(PREFIX=/tmp/termux-prefix run_success bootstrap-plan bash "$BOOTSTRAP" --plan --repo /tmp/AgentSwitchboard --ref main)"
expect_contains bootstrap-plan-status "$bootstrap_plan_output" 'capability_status=terminal-client-implemented'
expect_contains bootstrap-plan-role "$bootstrap_plan_output" 'role=terminal-client'
expect_contains bootstrap-plan-packages "$bootstrap_plan_output" 'packages=git,openssh,tmux,curl'
expect_contains bootstrap-plan-runtime "$bootstrap_plan_output" 'native_orchestration_runtime=unimplemented'
case "$bootstrap_plan_output" in
  *'pkg install'*) fail bootstrap-plan-no-mutation "plan output exposed a mutation command: $bootstrap_plan_output" ;;
esac

probe_root="$(mktemp -d)"
trap 'rm -rf "$probe_root"' EXIT
probe_bin="$probe_root/bin"
probe_state="$probe_root/state"
mkdir -p "$probe_bin" "$probe_state"

cat > "$probe_bin/ssh" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-T" ] || exit 90
shift
target="${1:-}"
[ -n "$target" ] || exit 91
shift
exec "$@"
EOF

cat > "$probe_bin/git" <<'EOF'
#!/bin/sh
case "${3:-} ${4:-}" in
  'rev-parse --git-dir')
    printf '.git\n'
    ;;
  'remote get-url')
    printf 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git\n'
    ;;
  'status --porcelain')
    ;;
  *)
    printf 'unexpected fake git invocation: %s\n' "$*" >&2
    exit 92
    ;;
esac
EOF

cat > "$probe_bin/tmux" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "has-session" ]; then
  printf 'error connecting to /tmp/tmux-1000/default (Permission denied)\n' >&2
  exit 2
fi
printf 'unexpected fake tmux invocation: %s\n' "$*" >&2
exit 93
EOF

chmod +x "$probe_bin/ssh" "$probe_bin/git" "$probe_bin/tmux"
inspection_output="$(PATH="$probe_bin:$PATH" XDG_STATE_HOME="$probe_state" run_failure remote-tmux-inspection bash "$LAUNCHER" remote fake-host --host-profile posix-tmux --repo /srv/AgentSwitchboard --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git --session dev --create)"
expect_contains remote-tmux-inspection-message "$inspection_output" 'remote preflight failed'
preflight_file="$probe_state/agentswitchboard/android/remote-preflight.env"
[ -f "$preflight_file" ] || fail remote-tmux-inspection-evidence "missing $preflight_file"
preflight_output="$(cat "$preflight_file")"
expect_contains remote-tmux-inspection-status "$preflight_output" 'session_status=inspection-error'
expect_contains remote-tmux-inspection-exit "$preflight_output" 'ssh_exit=45'

printf 'PASS: Android Termux shell behavior contracts\n'
