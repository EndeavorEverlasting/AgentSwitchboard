#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/harness/integration-contract.json"
EXPECTED_ORIGIN="kunchenguid/firstmate"

usage() {
  printf 'Usage: %s [--firstmate PATH]\n' "$0" >&2
}

FIRSTMATE_DIR="${FIRSTMATE_DIR:-}"
while (($#)); do
  case "$1" in
    --firstmate)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      FIRSTMATE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[FAIL] Unknown argument: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
done

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

note() {
  printf '[INFO] %s\n' "$*"
}

[[ -f "$CONTRACT" ]] || fail "Missing integration contract: $CONTRACT"
[[ "$(uname -s)" == "Linux" ]] || fail "This sprint proves only the Linux/WSL integration lane. Native Windows is out of scope."

for tool in git gh tmux python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool is unavailable in this Linux environment: $tool"
done

normalize_origin() {
  local raw="$1"
  raw="${raw%.git}"
  raw="${raw#https://github.com/}"
  raw="${raw#http://github.com/}"
  raw="${raw#ssh://git@github.com/}"
  raw="${raw#git@github.com:}"
  printf '%s\n' "$raw"
}

is_firstmate_clone() {
  local candidate="$1"
  [[ -d "$candidate/.git" ]] || return 1
  local origin
  origin="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
  [[ "$(normalize_origin "$origin")" == "$EXPECTED_ORIGIN" ]]
}

if [[ -z "$FIRSTMATE_DIR" ]]; then
  candidates=(
    "$PWD"
    "$HOME/firstmate"
    "$HOME/dev/firstmate"
    "$HOME/src/firstmate"
    "$HOME/Projects/firstmate"
    "$HOME/projects/firstmate"
  )
  for candidate in "${candidates[@]}"; do
    if is_firstmate_clone "$candidate"; then
      FIRSTMATE_DIR="$candidate"
      break
    fi
  done
fi

[[ -n "$FIRSTMATE_DIR" ]] || fail "First Mate clone not found. Re-run with --firstmate PATH or set FIRSTMATE_DIR."
FIRSTMATE_DIR="$(cd -- "$FIRSTMATE_DIR" && pwd)"
is_firstmate_clone "$FIRSTMATE_DIR" || fail "Path is not the audited upstream clone ($EXPECTED_ORIGIN): $FIRSTMATE_DIR"

status="$(git -C "$FIRSTMATE_DIR" status --porcelain=v1)"
[[ -z "$status" ]] || fail "First Mate clone is dirty; preserve that work before interoperability probing."

EXPECTED_HEAD="$(python3 - "$CONTRACT" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    print(json.load(handle)['upstream']['verified_commit'])
PY
)"
ACTUAL_HEAD="$(git -C "$FIRSTMATE_DIR" rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "First Mate HEAD is $ACTUAL_HEAD, but this integration floor was audited at $EXPECTED_HEAD. Refresh the evidence contract before claiming compatibility."

mapfile -t REQUIRED_PATHS < <(python3 - "$CONTRACT" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    for path in json.load(handle)['required_upstream_paths']:
        print(path)
PY
)
for path in "${REQUIRED_PATHS[@]}"; do
  [[ -e "$FIRSTMATE_DIR/$path" ]] || fail "Required audited upstream path is missing: $path"
done

HARNESS=""
for candidate in claude grok pi pi-signed codex opencode; do
  if command -v "$candidate" >/dev/null 2>&1; then
    HARNESS="$candidate"
    break
  fi
done
[[ -n "$HARNESS" ]] || fail "No verified First Mate primary harness is installed in this Linux environment (claude, grok, pi, pi-signed, codex, or opencode)."

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GitHub CLI is not authenticated for github.com in this Linux environment."

note "First Mate path: $FIRSTMATE_DIR"
note "First Mate audited HEAD: $ACTUAL_HEAD"
note "Primary harness available: $HARNESS"
note "tmux: $(tmux -V)"
printf '[PASS] FIRSTMATE_INTEROP=repository-and-toolchain-floor\n'
printf '[PROOF_CEILING] No First Mate task was dispatched; no project remote, PR, merge, credentials, or dependencies were mutated.\n'
