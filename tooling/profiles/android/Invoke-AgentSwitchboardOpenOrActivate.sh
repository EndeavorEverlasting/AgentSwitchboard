#!/data/data/com.termux/files/usr/bin/bash
set -eu

PROFILE_ID="android"
DEFAULT_SESSION="${AGENT_SWITCHBOARD_SESSION:-dev}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android"

usage() {
  cat <<'EOF'
AgentSwitchboard Android Profile

Usage:
  agentswitchboard-phone status
  agentswitchboard-phone local [--session NAME] [--plan]
  agentswitchboard-phone ssh TARGET [--session NAME] [--plan]

Commands:
  status       Show phone-side readiness without changing state.
  local        Open or activate a tmux session inside Termux.
  ssh TARGET   Open or activate the same named tmux session on an SSH host.

TARGET must be an SSH config alias or user@host value without spaces.
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
    ''|*[!A-Za-z0-9_.@:%-]*) fail "invalid SSH target: $1" ;;
  esac
}

write_result() {
  outcome="$1"
  mode="$2"
  target="$3"
  session="$4"
  mkdir -p "$STATE_ROOT"
  {
    printf 'profile=%s\n' "$PROFILE_ID"
    printf 'operation=open-or-activate\n'
    printf 'outcome=%s\n' "$outcome"
    printf 'mode=%s\n' "$mode"
    printf 'target=%s\n' "$target"
    printf 'session=%s\n' "$session"
    printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STATE_ROOT/last-result.env"
}

status() {
  printf 'profile=%s\n' "$PROFILE_ID"
  printf 'frontend=termux\n'
  printf 'operation=open-or-activate\n'
  for command_name in bash tmux ssh git; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf '%s=ready\n' "$command_name"
    else
      printf '%s=missing\n' "$command_name"
    fi
  done
  printf 'state=%s\n' "$STATE_ROOT/last-result.env"
}

action="${1:-status}"
if [ "$action" = "-h" ] || [ "$action" = "--help" ] || [ "$action" = "help" ]; then
  usage
  exit 0
fi
if [ "$action" = "status" ]; then
  status
  exit 0
fi
shift || true

mode="$action"
target=""
case "$mode" in
  local) ;;
  ssh)
    target="${1:-}"
    [ -n "$target" ] || fail "ssh mode requires TARGET"
    validate_target "$target"
    shift
    ;;
  *) usage >&2; fail "unknown command: $mode" ;;
esac

session="$DEFAULT_SESSION"
plan=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --session)
      [ "$#" -ge 2 ] || fail "--session requires a value"
      session="$2"
      shift 2
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

if [ "$plan" -eq 1 ]; then
  printf 'PLAN profile=%s operation=open-or-activate mode=%s target=%s session=%s\n' \
    "$PROFILE_ID" "$mode" "${target:-local}" "$session"
  exit 0
fi

if [ "$mode" = "local" ]; then
  command -v tmux >/dev/null 2>&1 || fail "tmux is missing; run Bootstrap-AgentSwitchboard-Termux.sh"
  if tmux list-sessions -F '#S' 2>/dev/null | grep -Fxq "$session"; then
    outcome="activated"
  else
    tmux new-session -d -s "$session"
    outcome="opened"
  fi
  write_result "$outcome" "$mode" "local" "$session"
  printf '[PASS] outcome=%s profile=%s session=%s\n' "$outcome" "$PROFILE_ID" "$session"

  if [ -n "${TMUX:-}" ]; then
    current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    [ "$current_session" = "$session" ] && exit 0
    exec tmux switch-client -t "$session"
  fi
  exec tmux attach-session -t "$session"
fi

command -v ssh >/dev/null 2>&1 || fail "ssh is missing; run Bootstrap-AgentSwitchboard-Termux.sh"
write_result "requested" "$mode" "$target" "$session"
exec ssh -t "$target" \
  "if tmux list-sessions -F '#S' 2>/dev/null | grep -Fxq '$session'; then printf '\\n[AgentSwitchboard] outcome=activated profile=android session=$session\\n'; else tmux new-session -d -s '$session' && printf '\\n[AgentSwitchboard] outcome=opened profile=android session=$session\\n'; fi; exec tmux attach-session -t '$session'"
