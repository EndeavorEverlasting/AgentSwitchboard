#!/data/data/com.termux/files/usr/bin/bash
set -eu

REPOSITORY_URL="https://github.com/EndeavorEverlasting/AgentSwitchboard.git"
REPOSITORY_SSH_URL="git@github.com:EndeavorEverlasting/AgentSwitchboard.git"
REPO_ROOT="${AGENT_SWITCHBOARD_REPO:-$HOME/dev/AgentSwitchboard}"
REF="main"
PLAN=0

usage() {
  cat <<'EOF'
Bootstrap AgentSwitchboard for Termux

Usage:
  Bootstrap-AgentSwitchboard-Termux.sh [--repo PATH] [--ref BRANCH] [--plan]

The bootstrap installs the phone-side package floor, safely acquires or
fast-forwards AgentSwitchboard, and installs the canonical Android launcher
as $PREFIX/bin/agentswitchboard-phone.
EOF
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
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
  printf 'PLAN profile=android frontend=termux repo=%s ref=%s packages=git,openssh,tmux,curl launcher=%s/bin/agentswitchboard-phone\n' \
    "$REPO_ROOT" "$REF" "${PREFIX:-\$PREFIX}"
  exit 0
fi

[ -n "${PREFIX:-}" ] || fail "PREFIX is not set; run this inside Termux"
command -v pkg >/dev/null 2>&1 || fail "pkg is unavailable; use a supported Termux installation"

printf '[INFO] Installing Termux package floor...\n'
pkg install -y git openssh tmux curl

mkdir -p "$(dirname "$REPO_ROOT")"
if [ -d "$REPO_ROOT/.git" ]; then
  origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    "$REPOSITORY_URL"|"$REPOSITORY_SSH_URL") ;;
    *) fail "existing checkout has unexpected origin: ${origin:-missing}" ;;
  esac
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || fail "existing checkout is dirty: $REPO_ROOT"
  current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ "$current_branch" = "$REF" ] || fail "existing checkout branch is '$current_branch'; expected '$REF'"
  git -C "$REPO_ROOT" fetch --prune origin "$REF"
  git -C "$REPO_ROOT" merge --ff-only "origin/$REF"
else
  [ ! -e "$REPO_ROOT" ] || fail "repo path exists but is not a Git checkout: $REPO_ROOT"
  git clone --branch "$REF" --single-branch "$REPOSITORY_URL" "$REPO_ROOT"
fi

launcher_source="$REPO_ROOT/tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh"
[ -f "$launcher_source" ] || fail "Android launcher missing from checkout: $launcher_source"
bash -n "$launcher_source"

install -m 0755 "$launcher_source" "$PREFIX/bin/agentswitchboard-phone"
"$PREFIX/bin/agentswitchboard-phone" local --plan >/dev/null
"$PREFIX/bin/agentswitchboard-phone" ssh example-host --plan >/dev/null

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android"
mkdir -p "$state_root"
{
  printf 'profile=android\n'
  printf 'frontend=termux\n'
  printf 'repo=%s\n' "$REPO_ROOT"
  printf 'ref=%s\n' "$REF"
  printf 'launcher=%s\n' "$PREFIX/bin/agentswitchboard-phone"
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'proof=installed-command-probes\n'
} > "$state_root/bootstrap-result.env"

printf '[PASS] Android Profile installed.\n'
printf '[NEXT] Local workspace: agentswitchboard-phone local\n'
printf '[NEXT] Remote workspace: agentswitchboard-phone ssh <ssh-alias>\n'
