#!/usr/bin/env bash
set -euo pipefail

PI_PACKAGE='@earendil-works/pi-coding-agent'
PI_VERSION='0.82.1'
EXPECTED_REPO_SSH='git@github.com:EndeavorEverlasting/AgentSwitchboard.git'
EXPECTED_REPO_HTTPS='https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
DEFAULT_SESSION="${AGENT_SWITCHBOARD_ANDROID_SESSION:-agentswitchboard-android}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-runtime"
SESSION_ROOT="$STATE_ROOT/pi-sessions"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
REPO_ROOT="${AGENT_SWITCHBOARD_REPO:-$DEFAULT_REPO}"

usage() {
  cat <<'EOF'
AgentSwitchboard Android / Termux runtime

Usage:
  Start-AgentSwitchboard-Android.sh [open-or-activate]
  Start-AgentSwitchboard-Android.sh status
  Start-AgentSwitchboard-Android.sh install
  Start-AgentSwitchboard-Android.sh login
  Start-AgentSwitchboard-Android.sh smoke
  Start-AgentSwitchboard-Android.sh proof-sprint
  Start-AgentSwitchboard-Android.sh sprint --prompt-file PATH

Modes:
  open-or-activate  Open or activate one tmux-backed Pi workspace.
  status            Read-only readiness and Git state.
  install           Install/verify the pinned Pi runtime and Termux floor.
  login             Open the Pi workspace for interactive /login.
  smoke             Read-only model/tool runtime proof with durable JSONL evidence.
  proof-sprint      Run the repository-owned first phone editing sprint.
  sprint            Run a supplied bounded sprint on an already-isolated branch.

Generated runtime evidence stays outside the repository under:
  ~/.local/state/agentswitchboard/android-runtime

This launcher never prints or records OAuth device codes, tokens, passwords,
recovery codes, or private SSH key material.
EOF
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[INFO] %s\n' "$*"
}

pass() {
  printf '[PASS] %s\n' "$*"
}

require_termux() {
  [ -n "${PREFIX:-}" ] || fail 'PREFIX is unset; run this inside Termux'
  case "$PREFIX" in
    /data/data/com.termux/files/usr*) ;;
    *) fail "unexpected PREFIX '$PREFIX'; Android runtime requires Termux" ;;
  esac
  command -v pkg >/dev/null 2>&1 || fail 'pkg is unavailable'
}

repo_origin() {
  git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true
}

assert_repo() {
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || fail "not a Git checkout: $REPO_ROOT"
  origin="$(repo_origin)"
  case "$origin" in
    "$EXPECTED_REPO_SSH"|"$EXPECTED_REPO_HTTPS") ;;
    *) fail "unexpected origin '${origin:-missing}'" ;;
  esac
}

pi_version() {
  command -v pi >/dev/null 2>&1 || return 1
  pi --version 2>/dev/null | awk '{print $NF}' | tail -n 1
}

assert_pi() {
  command -v node >/dev/null 2>&1 || fail 'node is missing; run install'
  command -v npm >/dev/null 2>&1 || fail 'npm is missing; run install'
  command -v pi >/dev/null 2>&1 || fail 'pi is missing; run install'
  actual="$(pi_version || true)"
  [ "$actual" = "$PI_VERSION" ] || fail "Pi version '$actual' does not match required $PI_VERSION; run install"
}

assert_tmux() {
  command -v tmux >/dev/null 2>&1 || fail 'tmux is missing; run install'
}

assert_gh_auth() {
  command -v gh >/dev/null 2>&1 || fail 'gh is missing; run install'
  gh auth status --hostname github.com >/dev/null 2>&1 || fail 'GitHub CLI is not authenticated'
}

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

write_env_result() {
  file="$1"
  shift
  mkdir -p "$(dirname "$file")"
  : > "$file"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$file"
  done
}

status() {
  assert_repo
  mkdir -p "$STATE_ROOT"
  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  dirty='false'
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || dirty='true'
  printf 'profile=android\n'
  printf 'runtime=pi\n'
  printf 'runtime_required_version=%s\n' "$PI_VERSION"
  printf 'runtime_observed_version=%s\n' "$(pi_version || printf missing)"
  printf 'repo=%s\n' "$REPO_ROOT"
  printf 'origin=%s\n' "$(repo_origin)"
  printf 'branch=%s\n' "$branch"
  printf 'head=%s\n' "$head"
  printf 'dirty=%s\n' "$dirty"
  if [ -n "${TMUX:-}" ]; then printf 'tmux=attached\n'; else printf 'tmux=outside\n'; fi
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
    printf 'github_auth=ready\n'
  else
    printf 'github_auth=unproved\n'
  fi
  if command -v node >/dev/null 2>&1; then printf 'node=%s\n' "$(node --version)"; else printf 'node=missing\n'; fi
  printf 'state_root=%s\n' "$STATE_ROOT"
  printf 'proof_level=readiness-only\n'
}

install_runtime() {
  require_termux
  assert_repo
  mkdir -p "$STATE_ROOT/install-logs" "$SESSION_ROOT"
  run_id="$(timestamp)"
  log="$STATE_ROOT/install-logs/install-$run_id.log"

  info "Installing Termux runtime floor; log=$log"
  {
    pkg install -y git openssh tmux gh jq nodejs
    node -e 'const [M,m]=process.versions.node.split(".").map(Number); if (M < 22 || (M === 22 && m < 19)) process.exit(1)'
    npm install -g --ignore-scripts "${PI_PACKAGE}@${PI_VERSION}"
    actual="$(pi_version)"
    [ "$actual" = "$PI_VERSION" ]
    npm list -g --depth=0 "$PI_PACKAGE"
  } >"$log" 2>&1 || {
    rc=$?
    tail -n 30 "$log" >&2 || true
    fail "runtime install failed exit=$rc log=$log"
  }

  wrapper="$PREFIX/bin/agentswitchboard-android"
  cat >"$wrapper" <<'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
set -e
repo="${AGENT_SWITCHBOARD_REPO:-$HOME/dev/AgentSwitchboard}"
exec "$repo/Start-AgentSwitchboard-Android.sh" "$@"
WRAPPER
  chmod 0755 "$wrapper"

  actual="$(pi_version)"
  write_env_result "$STATE_ROOT/install-result.env" \
    'profile=android' \
    'runtime=pi' \
    "pi_package=$PI_PACKAGE" \
    "pi_version=$actual" \
    "node_version=$(node --version)" \
    "wrapper=$wrapper" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'proof=installed-command-verification'

  pass "pinned Pi runtime installed version=$actual"
  printf 'EVIDENCE=%s\n' "$STATE_ROOT/install-result.env"
  printf 'NEXT=agentswitchboard-android login\n'
}

open_or_activate() {
  require_termux
  assert_repo
  assert_pi
  assert_tmux
  mkdir -p "$STATE_ROOT" "$SESSION_ROOT"

  if tmux has-session -t "$DEFAULT_SESSION" 2>/dev/null; then
    outcome='activated'
  else
    launch_log="$STATE_ROOT/open-or-activate-$(timestamp).log"
    if tmux new-session -d -s "$DEFAULT_SESSION" -c "$REPO_ROOT" \
      "PI_TELEMETRY=0 PI_SKIP_VERSION_CHECK=1 PI_CODING_AGENT_SESSION_DIR='$SESSION_ROOT' exec pi --approve" \
      >"$launch_log" 2>&1; then
      outcome='opened'
    elif tmux has-session -t "$DEFAULT_SESSION" 2>/dev/null; then
      outcome='activated-after-race'
    else
      tail -n 30 "$launch_log" >&2 || true
      fail "Pi tmux session failed to start; log=$launch_log"
    fi
  fi

  write_env_result "$STATE_ROOT/last-open.env" \
    'profile=android' \
    'runtime=pi' \
    "outcome=$outcome" \
    "session=$DEFAULT_SESSION" \
    "repo=$REPO_ROOT" \
    "head=$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'proof=launcher-session-only'

  pass "outcome=$outcome session=$DEFAULT_SESSION"
  if [ -n "${TMUX:-}" ]; then
    current="$(tmux display-message -p '#S' 2>/dev/null || true)"
    [ "$current" = "$DEFAULT_SESSION" ] && exit 0
    exec tmux switch-client -t "$DEFAULT_SESSION"
  fi
  exec tmux attach-session -t "$DEFAULT_SESSION"
}

login_runtime() {
  require_termux
  assert_repo
  assert_pi
  assert_tmux
  printf '%s\n' \
    '[ACTION] Pi will open in the persistent AgentSwitchboard Android tmux workspace.' \
    '[ACTION] In Pi, type /login and choose OpenAI ChatGPT Plus/Pro (Codex).' \
    '[ACTION] Choose the device/headless flow when offered and complete authorization in the browser.' \
    '[SECRET] Do not copy the device code, OAuth token, or credential files into logs, Git, or chat.'
  open_or_activate
}

assistant_marker_present() {
  events="$1"
  marker="$2"
  jq -s -e --arg marker "$marker" '
    any(.[];
      .type == "message_end"
      and .message.role == "assistant"
      and ((.message.content // []) | tostring | contains($marker))
    )
  ' "$events" >/dev/null
}

successful_tool_present() {
  events="$1"
  tool="$2"
  jq -s -e --arg tool "$tool" '
    any(.[];
      .type == "tool_execution_end"
      and .toolName == $tool
      and .isError == false
    )
  ' "$events" >/dev/null
}

smoke_runtime() {
  require_termux
  assert_repo
  assert_pi
  assert_tmux
  command -v jq >/dev/null 2>&1 || fail 'jq is missing; run install'
  [ -n "${TMUX:-}" ] || fail 'smoke must run from inside tmux'
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail 'smoke requires a clean working tree'

  run_id="smoke-$(timestamp)"
  run_root="$STATE_ROOT/runs/$run_id"
  events="$run_root/events.jsonl"
  stderr_log="$run_root/stderr.log"
  result="$run_root/result.env"
  mkdir -p "$run_root"
  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  head="$(git -C "$REPO_ROOT" rev-parse HEAD)"

  prompt='Read AGENTS.md with the read tool. Then briefly state what rule prevents premature handoff. End your final assistant message with the exact line ANDROID_RUNTIME_SMOKE=PASS'
  set +e
  (
    cd "$REPO_ROOT"
    timeout 300 env \
      PI_TELEMETRY=0 \
      PI_SKIP_VERSION_CHECK=1 \
      PI_CODING_AGENT_SESSION_DIR="$SESSION_ROOT" \
      pi --mode json --approve --no-session --tools read,grep,find,ls "$prompt"
  ) >"$events" 2>"$stderr_log"
  rc=$?
  set -e

  [ "$rc" -eq 0 ] || {
    write_env_result "$result" \
      'result=fail' "exit=$rc" "branch=$branch" "head=$head" \
      "events=$events" "stderr=$stderr_log"
    tail -n 30 "$stderr_log" >&2 || true
    fail "Pi smoke command failed exit=$rc result=$result"
  }

  jq -s -e 'any(.[]; .type == "agent_end")' "$events" >/dev/null ||
    fail "agent_end missing; events=$events"
  jq -s -e '
    any(.[];
      .type == "tool_execution_start"
      and .toolName == "read"
      and ((.args // {}) | tostring | contains("AGENTS.md"))
    )
  ' "$events" >/dev/null || fail "AGENTS.md read tool call missing; events=$events"
  successful_tool_present "$events" read ||
    fail "successful read tool completion missing; events=$events"
  assistant_marker_present "$events" 'ANDROID_RUNTIME_SMOKE=PASS' ||
    fail "assistant behavior marker missing; events=$events"

  write_env_result "$result" \
    'result=pass' \
    'proof_level=live-agent-tool-behavior' \
    "branch=$branch" \
    "head=$head" \
    "pi_version=$(pi_version)" \
    "events=$events" \
    "stderr=$stderr_log" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pass 'Android Pi smoke observed model response + AGENTS.md read tool execution'
  printf 'PROOF_LEVEL=live-agent-tool-behavior\n'
  printf 'EVIDENCE=%s\n' "$result"
  printf 'EVENTS=%s\n' "$events"
}

run_sprint() {
  require_termux
  assert_repo
  assert_pi
  assert_tmux
  assert_gh_auth
  command -v jq >/dev/null 2>&1 || fail 'jq is missing; run install'
  [ -n "${TMUX:-}" ] || fail 'sprint must run from inside tmux'
  prompt_file="$1"
  [ -f "$prompt_file" ] || fail "prompt file missing: $prompt_file"

  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  [ -n "$branch" ] || fail 'detached HEAD is not allowed for a writing sprint'
  [ "$branch" != 'main' ] || fail 'writing sprint refuses main; create an isolated feature branch first'
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail 'writing sprint requires a clean starting tree'

  start_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  run_id="sprint-$(timestamp)"
  run_root="$STATE_ROOT/runs/$run_id"
  events="$run_root/events.jsonl"
  stderr_log="$run_root/stderr.log"
  result="$run_root/result.env"
  mkdir -p "$run_root"

  sprint_text="$(cat "$prompt_file")"
  envelope="$(cat <<EOF
You are the designated writer for this bounded AgentSwitchboard sprint on Android Termux.
Read AGENTS.md before mutation. Execute the task below rather than returning a plan.
Use repository-owned validators. Preserve unrelated work. Do not expose credentials.
Commit and push completed owned work and open or update a PR when safe.
At the very end of the final assistant message, print exactly:
ANDROID_RUNTIME_SPRINT=COMPLETE
Only print that marker after implementation, validation, commit, push, and PR creation/update all succeeded.

SPRINT TASK:
$sprint_text
EOF
)"

  set +e
  (
    cd "$REPO_ROOT"
    timeout 1800 env \
      PI_TELEMETRY=0 \
      PI_SKIP_VERSION_CHECK=1 \
      PI_CODING_AGENT_SESSION_DIR="$SESSION_ROOT" \
      pi --mode json --approve --name "$run_id" \
        --tools read,bash,edit,write,grep,find,ls "$envelope"
  ) >"$events" 2>"$stderr_log"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    write_env_result "$result" \
      'result=fail' "exit=$rc" "branch=$branch" "start_head=$start_head" \
      "events=$events" "stderr=$stderr_log"
    tail -n 30 "$stderr_log" >&2 || true
    fail "Pi sprint process failed exit=$rc result=$result"
  fi

  successful_tool_present "$events" read || fail "read tool proof missing; events=$events"
  if ! successful_tool_present "$events" edit && ! successful_tool_present "$events" write; then
    fail "no successful edit/write tool proof; events=$events"
  fi
  successful_tool_present "$events" bash || fail "bash tool proof missing; events=$events"
  assistant_marker_present "$events" 'ANDROID_RUNTIME_SPRINT=COMPLETE' ||
    fail "completion marker missing; events=$events"

  end_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  [ "$end_head" != "$start_head" ] || fail 'sprint created no commit'
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail 'sprint left a dirty working tree'
  git -C "$REPO_ROOT" diff --check "$start_head...$end_head"

  remote_head="$(git -C "$REPO_ROOT" ls-remote origin "refs/heads/$branch" | awk 'NR==1 {print $1}')"
  [ "$remote_head" = "$end_head" ] || fail "remote branch does not match local HEAD local=$end_head remote=${remote_head:-missing}"

  pr_url="$(cd "$REPO_ROOT" && gh pr view "$branch" --json url --jq .url 2>/dev/null || true)"
  [ -n "$pr_url" ] || fail 'no PR found for sprint branch'

  write_env_result "$result" \
    'result=pass' \
    'proof_level=live-agent-repository-mutation' \
    "branch=$branch" \
    "start_head=$start_head" \
    "end_head=$end_head" \
    "remote_head=$remote_head" \
    "pr_url=$pr_url" \
    "pi_version=$(pi_version)" \
    "events=$events" \
    "stderr=$stderr_log" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  pass "live Android agent sprint committed and pushed branch=$branch"
  printf 'PROOF_LEVEL=live-agent-repository-mutation\n'
  printf 'HEAD=%s\n' "$end_head"
  printf 'PR_URL=%s\n' "$pr_url"
  printf 'EVIDENCE=%s\n' "$result"
  printf 'EVENTS=%s\n' "$events"
}

proof_sprint() {
  require_termux
  assert_repo
  assert_pi
  assert_tmux
  assert_gh_auth
  [ -n "${TMUX:-}" ] || fail 'proof-sprint must run from inside tmux'
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail 'proof-sprint requires a clean tree'
  current="$(git -C "$REPO_ROOT" branch --show-current)"
  [ "$current" = 'main' ] || fail "proof-sprint starts from main; current branch is '$current'"

  info 'Refreshing live main before creating the phone-owned branch'
  git -C "$REPO_ROOT" fetch origin main
  git -C "$REPO_ROOT" merge --ff-only origin/main
  base_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  remote_main="$(git -C "$REPO_ROOT" rev-parse origin/main)"
  [ "$base_head" = "$remote_main" ] || fail 'local main does not match origin/main'

  branch="feat/android-command-transport-$(date -u +%Y%m%d-%H%M%S)"
  git -C "$REPO_ROOT" switch -c "$branch"
  prompt_file="$REPO_ROOT/tooling/profiles/android/runtime-proof-sprint.prompt.md"
  run_sprint "$prompt_file"
}

action="${1:-open-or-activate}"
case "$action" in
  -h|--help|help) usage ;;
  status) status ;;
  install) install_runtime ;;
  open-or-activate|open) open_or_activate ;;
  login) login_runtime ;;
  smoke) smoke_runtime ;;
  proof-sprint) proof_sprint ;;
  sprint)
    shift
    [ "${1:-}" = '--prompt-file' ] || fail 'sprint requires --prompt-file PATH'
    [ "$#" -ge 2 ] || fail 'sprint requires --prompt-file PATH'
    run_sprint "$2"
    ;;
  *) usage >&2; fail "unknown action: $action" ;;
esac
