#!/usr/bin/env bash
set -euo pipefail

CODEX_PACKAGE='@openai/codex'
CODEX_VERSION='0.147.0'
CODEX_NODE_PLATFORM='android'
CODEX_NODE_ARCH='arm64'
CODEX_TARGET_TRIPLE='aarch64-unknown-linux-musl'
EXPECTED_REPO_SSH='git@github.com:EndeavorEverlasting/AgentSwitchboard.git'
EXPECTED_REPO_HTTPS='https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
DEFAULT_SESSION="${AGENT_SWITCHBOARD_ANDROID_SESSION:-agentswitchboard-android}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-runtime"

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
  open-or-activate  Open or activate one tmux-backed Codex workspace.
  status            Read-only Codex, authentication, repository, and Git state.
  install           Install/verify the pinned official Codex CLI and Termux floor.
  login             Sign in to Codex with the official device-auth flow.
  smoke             Read-only Codex command/tool runtime proof with durable JSONL evidence.
  proof-sprint      Run the repository-owned first phone editing sprint with Codex.
  sprint            Run a supplied bounded Codex sprint on an already-isolated branch.

Generated runtime evidence stays outside the repository under:
  ~/.local/state/agentswitchboard/android-runtime

This launcher never prints or records OAuth device codes, access tokens, API keys,
passwords, recovery codes, or private SSH key material.
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

codex_version() {
  command -v codex >/dev/null 2>&1 || return 1
  codex --version 2>/dev/null | awk '{print $NF}' | tail -n 1
}

assert_codex() {
  command -v node >/dev/null 2>&1 || fail 'node is missing; run install'
  command -v npm >/dev/null 2>&1 || fail 'npm is missing; run install'
  command -v codex >/dev/null 2>&1 || fail 'codex is missing; run install'
  actual="$(codex_version || true)"
  [ "$actual" = "$CODEX_VERSION" ] || fail "Codex version '$actual' does not match required $CODEX_VERSION; run install"
}

assert_codex_auth() {
  codex login status >/dev/null 2>&1 || fail 'Codex is not authenticated; run agentswitchboard-android login'
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
  printf 'agent=codex\n'
  printf 'runtime=codex\n'
  printf 'runtime_required_version=%s\n' "$CODEX_VERSION"
  printf 'runtime_observed_version=%s\n' "$(codex_version || printf missing)"
  printf 'expected_node_platform=%s\n' "$CODEX_NODE_PLATFORM"
  printf 'expected_node_arch=%s\n' "$CODEX_NODE_ARCH"
  printf 'expected_target=%s\n' "$CODEX_TARGET_TRIPLE"
  printf 'repo=%s\n' "$REPO_ROOT"
  printf 'origin=%s\n' "$(repo_origin)"
  printf 'branch=%s\n' "$branch"
  printf 'head=%s\n' "$head"
  printf 'dirty=%s\n' "$dirty"
  if [ -n "${TMUX:-}" ]; then printf 'tmux=attached\n'; else printf 'tmux=outside\n'; fi
  if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
    printf 'codex_auth=ready\n'
  else
    printf 'codex_auth=unproved\n'
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
    printf 'github_auth=ready\n'
  else
    printf 'github_auth=unproved\n'
  fi
  if command -v node >/dev/null 2>&1; then
    printf 'node=%s\n' "$(node --version)"
    printf 'node_platform=%s\n' "$(node -p 'process.platform')"
    printf 'node_arch=%s\n' "$(node -p 'process.arch')"
  else
    printf 'node=missing\n'
    printf 'node_platform=unknown\n'
    printf 'node_arch=unknown\n'
  fi
  printf 'state_root=%s\n' "$STATE_ROOT"
  printf 'proof_level=readiness-only\n'
}

install_runtime() {
  require_termux
  assert_repo
  mkdir -p "$STATE_ROOT/install-logs"
  run_id="$(timestamp)"
  log="$STATE_ROOT/install-logs/install-$run_id.log"

  info "Installing official pinned Codex CLI; log=$log"
  {
    pkg install -y git openssh tmux gh jq nodejs
    node -e 'const major=Number(process.versions.node.split(".")[0]); if (major < 16) process.exit(1)'
    platform="$(node -p 'process.platform')"
    arch="$(node -p 'process.arch')"
    [ "$platform" = "$CODEX_NODE_PLATFORM" ]
    [ "$arch" = "$CODEX_NODE_ARCH" ]
    npm install -g --ignore-scripts "${CODEX_PACKAGE}@${CODEX_VERSION}"
    actual="$(codex_version)"
    [ "$actual" = "$CODEX_VERSION" ]
    npm list -g --depth=0 "$CODEX_PACKAGE"
  } >"$log" 2>&1 || {
    rc=$?
    tail -n 30 "$log" >&2 || true
    fail "Codex runtime install failed exit=$rc log=$log"
  }

  wrapper="$PREFIX/bin/agentswitchboard-android"
  cat >"$wrapper" <<'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
set -e
repo="${AGENT_SWITCHBOARD_REPO:-$HOME/dev/AgentSwitchboard}"
exec "$repo/Start-AgentSwitchboard-Android.sh" "$@"
WRAPPER
  chmod 0755 "$wrapper"

  actual="$(codex_version)"
  write_env_result "$STATE_ROOT/install-result.env" \
    'profile=android' \
    'agent=codex' \
    'runtime=codex' \
    "codex_package=$CODEX_PACKAGE" \
    "codex_version=$actual" \
    "node_version=$(node --version)" \
    "node_platform=$(node -p 'process.platform')" \
    "node_arch=$(node -p 'process.arch')" \
    "codex_target=$CODEX_TARGET_TRIPLE" \
    "wrapper=$wrapper" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'proof=installed-command-verification'

  pass "official pinned Codex CLI installed version=$actual"
  printf 'EVIDENCE=%s\n' "$STATE_ROOT/install-result.env"
  printf 'NEXT=agentswitchboard-android login\n'
}

open_or_activate() {
  require_termux
  assert_repo
  assert_codex
  assert_tmux
  mkdir -p "$STATE_ROOT"

  if tmux has-session -t "$DEFAULT_SESSION" 2>/dev/null; then
    outcome='activated'
  else
    launch_log="$STATE_ROOT/open-or-activate-$(timestamp).log"
    printf -v launch_cmd 'exec codex -C %q' "$REPO_ROOT"
    if tmux new-session -d -s "$DEFAULT_SESSION" -c "$REPO_ROOT" "$launch_cmd" \
      >"$launch_log" 2>&1; then
      outcome='opened'
    elif tmux has-session -t "$DEFAULT_SESSION" 2>/dev/null; then
      outcome='activated-after-race'
    else
      tail -n 30 "$launch_log" >&2 || true
      fail "Codex tmux session failed to start; log=$launch_log"
    fi
  fi

  write_env_result "$STATE_ROOT/last-open.env" \
    'profile=android' \
    'agent=codex' \
    'runtime=codex' \
    "codex_version=$(codex_version)" \
    "outcome=$outcome" \
    "session=$DEFAULT_SESSION" \
    "repo=$REPO_ROOT" \
    "head=$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'proof=launcher-session-only'

  pass "outcome=$outcome agent=codex session=$DEFAULT_SESSION"
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
  assert_codex

  if codex login status >/dev/null 2>&1; then
    pass 'Codex authentication is already ready'
    return 0
  fi

  printf '%s\n' \
    '[ACTION] Starting the official Codex device-auth flow.' \
    '[ACTION] Complete authorization in your browser, then return to Termux.' \
    '[SECRET] The device code and resulting credentials are not written to AgentSwitchboard evidence.' \
    '[SECRET] Do not copy device codes, tokens, API keys, passwords, or credential files into Git, logs, or chat.'
  codex login --device-auth
  codex login status >/dev/null 2>&1 || fail 'Codex login command returned but authentication status is not ready'
  pass 'Codex ChatGPT authentication is ready'
}

codex_marker_present() {
  events="$1"
  marker="$2"
  jq -s -e --arg marker "$marker" '
    any(.[];
      .type == "item.completed"
      and .item.type == "agent_message"
      and ((.item.text // "") | contains($marker))
    )
  ' "$events" >/dev/null
}

codex_turn_completed() {
  events="$1"
  jq -s -e 'any(.[]; .type == "turn.completed")' "$events" >/dev/null
}

successful_command_matching() {
  events="$1"
  needle="$2"
  jq -s -e --arg needle "$needle" '
    any(.[];
      .type == "item.completed"
      and .item.type == "command_execution"
      and .item.status == "completed"
      and ((.item.exit_code // 0) == 0)
      and ((.item.command // "") | contains($needle))
    )
  ' "$events" >/dev/null
}

successful_command_present() {
  events="$1"
  jq -s -e '
    any(.[];
      .type == "item.completed"
      and .item.type == "command_execution"
      and .item.status == "completed"
      and ((.item.exit_code // 0) == 0)
    )
  ' "$events" >/dev/null
}

successful_file_change_present() {
  events="$1"
  jq -s -e '
    any(.[];
      .type == "item.completed"
      and .item.type == "file_change"
      and .item.status == "completed"
      and ((.item.changes // []) | length > 0)
    )
  ' "$events" >/dev/null
}

smoke_runtime() {
  require_termux
  assert_repo
  assert_codex
  assert_codex_auth
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

  prompt='Read AGENTS.md using a shell command, briefly state the rule that prevents premature handoff, and end the final answer with the exact line ANDROID_RUNTIME_SMOKE=PASS. Do not modify any file.'
  set +e
  timeout 300 codex exec --json --ephemeral -s read-only -C "$REPO_ROOT" "$prompt" \
    >"$events" 2>"$stderr_log"
  rc=$?
  set -e

  [ "$rc" -eq 0 ] || {
    write_env_result "$result" \
      'result=fail' "exit=$rc" "branch=$branch" "head=$head" \
      "events=$events" "stderr=$stderr_log"
    tail -n 30 "$stderr_log" >&2 || true
    fail "Codex smoke command failed exit=$rc result=$result"
  }

  codex_turn_completed "$events" || fail "turn.completed missing; events=$events"
  successful_command_matching "$events" 'AGENTS.md' ||
    fail "successful AGENTS.md command proof missing; events=$events"
  codex_marker_present "$events" 'ANDROID_RUNTIME_SMOKE=PASS' ||
    fail "completion marker missing; events=$events"

  write_env_result "$result" \
    'result=pass' \
    'agent=codex' \
    'proof_level=live-agent-tool-behavior' \
    "branch=$branch" \
    "head=$head" \
    "codex_version=$(codex_version)" \
    "events=$events" \
    "stderr=$stderr_log" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pass 'Android Codex smoke observed model response + successful AGENTS.md command execution'
  printf 'PROOF_LEVEL=live-agent-tool-behavior\n'
  printf 'EVIDENCE=%s\n' "$result"
  printf 'EVENTS=%s\n' "$events"
}

run_sprint() {
  require_termux
  assert_repo
  assert_codex
  assert_codex_auth
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
You are Codex, the designated writer for this bounded AgentSwitchboard sprint on Android Termux.
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
  timeout 1800 codex exec --json --ephemeral --approve-for-me -C "$REPO_ROOT" "$envelope" \
    >"$events" 2>"$stderr_log"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    write_env_result "$result" \
      'result=fail' "exit=$rc" "branch=$branch" "start_head=$start_head" \
      "events=$events" "stderr=$stderr_log"
    tail -n 30 "$stderr_log" >&2 || true
    fail "Codex sprint process failed exit=$rc result=$result"
  fi

  codex_turn_completed "$events" || fail "turn.completed missing; events=$events"
  successful_command_matching "$events" 'AGENTS.md' ||
    fail "AGENTS.md command proof missing; events=$events"
  successful_file_change_present "$events" ||
    fail "no successful Codex file-change proof; events=$events"
  successful_command_present "$events" ||
    fail "no successful Codex command-execution proof; events=$events"
  codex_marker_present "$events" 'ANDROID_RUNTIME_SPRINT=COMPLETE' ||
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
    'agent=codex' \
    'proof_level=live-agent-repository-mutation' \
    "branch=$branch" \
    "start_head=$start_head" \
    "end_head=$end_head" \
    "remote_head=$remote_head" \
    "pr_url=$pr_url" \
    "codex_version=$(codex_version)" \
    "events=$events" \
    "stderr=$stderr_log" \
    "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  pass "live Android Codex sprint committed and pushed branch=$branch"
  printf 'PROOF_LEVEL=live-agent-repository-mutation\n'
  printf 'HEAD=%s\n' "$end_head"
  printf 'PR_URL=%s\n' "$pr_url"
  printf 'EVIDENCE=%s\n' "$result"
  printf 'EVENTS=%s\n' "$events"
}

proof_sprint() {
  require_termux
  assert_repo
  assert_codex
  assert_codex_auth
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
