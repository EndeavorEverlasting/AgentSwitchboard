#!/data/data/com.termux/files/usr/bin/bash
set -eu

PROFILE_ID="android"
CAPABILITY_STATUS="terminal-client-implemented"
CAPABILITY_ROLE="terminal-client"
DEFAULT_SESSION="${AGENT_SWITCHBOARD_SESSION:-dev}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android"

usage() {
  cat <<'EOF'
AgentSwitchboard Android terminal client

Usage:
  agentswitchboard-phone status
  agentswitchboard-phone local-shell [--session NAME] [--plan]
  agentswitchboard-phone remote TARGET --host-profile posix-tmux \
    --repo PATH --expected-origin URL [--session NAME] [--create] [--plan]

Commands:
  status       Show phone-side terminal-client readiness without mutation.
  local-shell  Open or activate a phone-local tmux shell. This is not
               cross-device continuity and is not an AgentSwitchboard runtime.
  remote       Preflight a classified POSIX SSH workspace host, then attach to
               its tmux session. Session creation requires --create.

The Android implementation is a terminal client. The workspace host,
AgentSwitchboard orchestration runtime, agent runtime, and provider state are
separate capabilities and must be proved on their actual host.
EOF
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

validate_session() {
  case "$1" in
    ''|*[!A-Za-z0-9_.-]*) fail "invalid tmux session name: $1" ;;
  esac
}

validate_target() {
  case "$1" in
    ''|-*|*[!A-Za-z0-9_.@:%-]*) fail "invalid SSH target: $1" ;;
  esac
}

validate_repo_path() {
  case "$1" in
    /*) ;;
    *) fail "remote repository path must be absolute: $1" ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_./~+-]*) fail "remote repository path contains unsupported characters: $1" ;;
  esac
}

validate_origin() {
  case "$1" in
    ''|*[!A-Za-z0-9_./:@+-]*) fail "expected origin contains unsupported characters" ;;
  esac
}

write_result() {
  outcome="$1"
  mode="$2"
  target="$3"
  session="$4"
  continuity_scope="$5"
  attachment_observed="$6"
  mkdir -p "$STATE_ROOT"
  {
    printf 'profile=%s\n' "$PROFILE_ID"
    printf 'capability_status=%s\n' "$CAPABILITY_STATUS"
    printf 'role=%s\n' "$CAPABILITY_ROLE"
    printf 'operation=open-or-activate\n'
    printf 'outcome=%s\n' "$outcome"
    printf 'mode=%s\n' "$mode"
    printf 'target=%s\n' "$target"
    printf 'session=%s\n' "$session"
    printf 'continuity_scope=%s\n' "$continuity_scope"
    printf 'attachment_observed=%s\n' "$attachment_observed"
    printf 'native_orchestration_runtime=unimplemented\n'
    printf 'native_agent_runtime=unproved\n'
    printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STATE_ROOT/last-result.env"
}

status() {
  printf 'profile=%s\n' "$PROFILE_ID"
  printf 'capability_status=%s\n' "$CAPABILITY_STATUS"
  printf 'role=terminal-client\n'
  printf 'frontend=termux\n'
  printf 'transport=ssh\n'
  printf 'local_tmux_role=local-shell-only\n'
  printf 'continuity_scope=device-local-only\n'
  printf 'cross_device_continuity=requires-remote-workspace-host\n'
  printf 'native_orchestration_runtime=unimplemented\n'
  printf 'native_agent_runtime=unproved\n'
  for command_name in bash tmux ssh git; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=available-unverified\n' "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
  printf 'last_result=%s\n' "$STATE_ROOT/last-result.env"
  printf 'remote_preflight=%s\n' "$STATE_ROOT/remote-preflight.env"
}

action="${1:-status}"
case "$action" in
  -h|--help|help)
    usage
    exit 0
    ;;
  status)
    status
    exit 0
    ;;
  local)
    printf '[WARN] local is deprecated; use local-shell. This is device-local only.\n' >&2
    action="local-shell"
    shift
    ;;
  local-shell)
    shift
    ;;
  remote)
    shift
    ;;
  *)
    usage >&2
    fail "unknown command: $action"
    ;;
esac

mode="$action"
target=""
session="$DEFAULT_SESSION"
host_profile=""
repo_path=""
expected_origin=""
create_session=0
plan=0

if [ "$mode" = "remote" ]; then
  target="${1:-}"
  [ -n "$target" ] || fail "remote mode requires TARGET"
  validate_target "$target"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session)
      [ "$#" -ge 2 ] || fail "--session requires a value"
      session="$2"
      shift 2
      ;;
    --host-profile)
      [ "$#" -ge 2 ] || fail "--host-profile requires a value"
      host_profile="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || fail "--repo requires a value"
      repo_path="$2"
      shift 2
      ;;
    --expected-origin)
      [ "$#" -ge 2 ] || fail "--expected-origin requires a value"
      expected_origin="$2"
      shift 2
      ;;
    --create)
      create_session=1
      shift
      ;;
    --plan)
      plan=1
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

validate_session "$session"

if [ "$mode" = "local-shell" ]; then
  [ -z "$host_profile" ] || fail "--host-profile is valid only for remote mode"
  [ -z "$repo_path" ] || fail "--repo is valid only for remote mode"
  [ -z "$expected_origin" ] || fail "--expected-origin is valid only for remote mode"
  [ "$create_session" -eq 0 ] || fail "--create is valid only for remote mode"

  if [ "$plan" -eq 1 ]; then
    printf 'PLAN profile=%s capability_status=%s role=local-shell-only mode=local-shell continuity_scope=device-local-only session=%s\n' \
      "$PROFILE_ID" "$CAPABILITY_STATUS" "$session"
    exit 0
  fi

  command -v tmux >/dev/null 2>&1 || fail "tmux is missing; run Bootstrap-AgentSwitchboard-Termux.sh"
  if tmux has-session -t "$session" 2>/dev/null; then
    outcome="activated-local-shell"
  else
    create_log="$STATE_ROOT/local-session-create.log"
    mkdir -p "$STATE_ROOT"
    if tmux new-session -d -s "$session" >"$create_log" 2>&1; then
      outcome="opened-local-shell"
    elif tmux has-session -t "$session" 2>/dev/null; then
      outcome="activated-local-shell"
    else
      printf '[FAIL] local tmux session creation failed; log=%s\n' "$create_log" >&2
      tail -n 20 "$create_log" >&2 || true
      exit 31
    fi
  fi
  write_result "$outcome" "$mode" "android-local" "$session" "device-local-only" "false"
  printf '[PASS] outcome=%s role=local-shell-only session=%s\n' "$outcome" "$session"
  printf '[LIMIT] This session belongs to the phone-local tmux server; it is not a desktop or remote AgentSwitchboard workspace.\n'

  if [ -n "${TMUX:-}" ]; then
    current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    [ "$current_session" = "$session" ] && exit 0
    exec tmux switch-client -t "$session"
  fi
  exec tmux attach-session -t "$session"
fi

[ "$host_profile" = "posix-tmux" ] || fail "remote mode requires --host-profile posix-tmux; other remote shells are not implemented"
[ -n "$repo_path" ] || fail "remote mode requires --repo PATH"
[ -n "$expected_origin" ] || fail "remote mode requires --expected-origin URL"
validate_repo_path "$repo_path"
validate_origin "$expected_origin"

if [ "$plan" -eq 1 ]; then
  printf 'PLAN profile=%s capability_status=%s role=terminal-client topology=android-termux-ssh-posix-workspace-client mode=remote target=%s host_profile=%s repo=%s expected_origin=%s session=%s create=%s\n' \
    "$PROFILE_ID" "$CAPABILITY_STATUS" "$target" "$host_profile" "$repo_path" "$expected_origin" "$session" "$create_session"
  exit 0
fi

command -v ssh >/dev/null 2>&1 || fail "ssh is missing; run Bootstrap-AgentSwitchboard-Termux.sh"
mkdir -p "$STATE_ROOT"
preflight_path="$STATE_ROOT/remote-preflight.env"

set +e
preflight_output="$(ssh -T "$target" sh -s -- "$repo_path" "$expected_origin" "$session" <<'REMOTE_PREFLIGHT'
set -eu
repo_path="$1"
expected_origin="$2"
session="$3"
remote_os="$(uname -s 2>/dev/null || printf unknown)"
remote_shell="${SHELL:-unknown}"
tmux_status="missing"
repo_status="missing"
origin_status="unknown"
working_tree_status="unknown"
session_status="unknown"
session_probe_exit="not-run"

if command -v tmux >/dev/null 2>&1; then
  tmux_status="ready"
fi

if git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
  repo_status="present"
  actual_origin="$(git -C "$repo_path" remote get-url origin 2>/dev/null || printf missing)"
  if [ "$actual_origin" = "$expected_origin" ]; then
    origin_status="expected"
  else
    origin_status="unexpected"
  fi
  if [ -z "$(git -C "$repo_path" status --porcelain 2>/dev/null)" ]; then
    working_tree_status="clean"
  else
    working_tree_status="dirty"
  fi
fi

if [ "$tmux_status" = "ready" ]; then
  session_probe_log="${TMPDIR:-/tmp}/agentswitchboard-tmux-probe-$$.log"
  set +e
  tmux has-session -t "$session" >/dev/null 2>"$session_probe_log"
  session_probe_exit=$?
  set -e
  if [ "$session_probe_exit" -eq 0 ]; then
    session_status="present"
  elif grep -Eq "no server running on|can't find session" "$session_probe_log"; then
    session_status="absent"
  else
    session_status="inspection-error"
  fi
  rm -f "$session_probe_log"
fi

printf 'remote_os=%s\n' "$remote_os"
printf 'remote_shell=%s\n' "$remote_shell"
printf 'tmux_status=%s\n' "$tmux_status"
printf 'repository_status=%s\n' "$repo_status"
printf 'origin_status=%s\n' "$origin_status"
printf 'working_tree_status=%s\n' "$working_tree_status"
printf 'session_status=%s\n' "$session_status"
printf 'session_probe_exit=%s\n' "$session_probe_exit"

if [ "$tmux_status" != "ready" ]; then exit 41; fi
if [ "$repo_status" != "present" ]; then exit 42; fi
if [ "$origin_status" != "expected" ]; then exit 43; fi
if [ "$working_tree_status" != "clean" ]; then exit 44; fi
if [ "$session_status" = "inspection-error" ]; then exit 45; fi
printf 'preflight=pass\n'
REMOTE_PREFLIGHT
)"
preflight_rc=$?
set -e

{
  printf 'profile=%s\n' "$PROFILE_ID"
  printf 'role=terminal-client\n'
  printf 'topology=android-termux-ssh-posix-workspace-client\n'
  printf 'target=%s\n' "$target"
  printf 'host_profile=%s\n' "$host_profile"
  printf 'repository=%s\n' "$repo_path"
  printf 'session=%s\n' "$session"
  printf '%s\n' "$preflight_output"
  printf 'ssh_exit=%s\n' "$preflight_rc"
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$preflight_path"

if [ "$preflight_rc" -ne 0 ] || ! printf '%s\n' "$preflight_output" | grep -Fxq 'preflight=pass'; then
  write_result "blocked-remote-preflight" "$mode" "$target" "$session" "remote-workspace-host-required" "false"
  fail "remote preflight failed; inspect $preflight_path"
fi

session_status="$(printf '%s\n' "$preflight_output" | sed -n 's/^session_status=//p' | tail -n 1)"
if [ "$session_status" = "absent" ]; then
  if [ "$create_session" -ne 1 ]; then
    write_result "blocked-session-absent" "$mode" "$target" "$session" "remote-workspace-host" "false"
    fail "remote tmux session '$session' is absent; rerun with --create only when remote session creation is intended"
  fi
  set +e
  remote_create_output="$(ssh -T "$target" sh -s -- "$repo_path" "$session" <<'REMOTE_CREATE'
set -eu
repo_path="$1"
session="$2"
cd "$repo_path"
create_log="${TMPDIR:-/tmp}/agentswitchboard-tmux-create-$$.log"
if tmux new-session -d -s "$session" >"$create_log" 2>&1; then
  printf 'create_outcome=created\n'
elif tmux has-session -t "$session" 2>/dev/null; then
  printf 'create_outcome=existing-after-race\n'
else
  printf 'create_outcome=failed\n' >&2
  tail -n 20 "$create_log" >&2 || true
  rm -f "$create_log"
  exit 51
fi
rm -f "$create_log"
tmux has-session -t "$session"
REMOTE_CREATE
)"
  remote_create_rc=$?
  set -e
  if [ "$remote_create_rc" -ne 0 ]; then
    write_result "failed-remote-session-create" "$mode" "$target" "$session" "remote-workspace-host" "false"
    printf '[FAIL] remote tmux session creation failed exit=%s\n' "$remote_create_rc" >&2
    printf '%s\n' "$remote_create_output" >&2
    exit 51
  fi
  if printf '%s\n' "$remote_create_output" | grep -Fxq 'create_outcome=created'; then
    remote_outcome="created-remote-session-request"
  else
    remote_outcome="existing-remote-session-request"
  fi
else
  remote_outcome="existing-remote-session-request"
fi

write_result "$remote_outcome" "$mode" "$target" "$session" "remote-workspace-host" "false"
printf '[PASS] remote preflight passed; attaching as terminal client.\n'
printf '[LIMIT] AgentSwitchboard orchestration and agent/provider readiness remain separate remote-host proofs.\n'

set +e
ssh -t "$target" "exec tmux attach-session -t '$session'"
ssh_rc=$?
set -e
write_result "remote-transport-ended" "$mode" "$target" "$session" "remote-workspace-host" "false"
exit "$ssh_rc"
