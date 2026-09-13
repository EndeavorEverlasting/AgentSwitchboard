#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/harness/integration-contract.json"
EXPECTED_ORIGIN="kunchenguid/firstmate"

usage() {
  printf 'Usage: %s [--firstmate PATH] [--normalize-origin URL]\n' "$0" >&2
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

note() {
  printf '[INFO] %s\n' "$*"
}

normalize_origin() {
  local raw="${1:-}"
  raw="${raw%/}"
  raw="${raw%.git}"
  raw="${raw%/}"

  if [[ "$raw" =~ ^https?://([^/@]+@)?github\.com/(.+)$ ]]; then
    raw="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^git://github\.com/(.+)$ ]]; then
    raw="${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    raw="${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ ^git@github\.com:(.+)$ ]]; then
    raw="${BASH_REMATCH[1]}"
  fi

  raw="${raw%/}"
  raw="${raw%.git}"
  printf '%s\n' "$raw"
}

FIRSTMATE_DIR="${FIRSTMATE_DIR:-}"
NORMALIZE_ONLY=""
while (($#)); do
  case "$1" in
    --firstmate)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      FIRSTMATE_DIR="$2"
      shift 2
      ;;
    --normalize-origin)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      NORMALIZE_ONLY="$2"
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

if [[ -n "$NORMALIZE_ONLY" ]]; then
  normalize_origin "$NORMALIZE_ONLY"
  exit 0
fi

[[ -f "$CONTRACT" ]] || fail "Missing integration contract: $CONTRACT"
[[ "$(uname -s)" == "Linux" ]] || fail "This sprint proves only the Linux/WSL integration lane. Native Windows is out of scope."

for tool in git gh tmux python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool is unavailable in this Linux environment: $tool"
done

CONTRACT_OUTPUT=""
if ! CONTRACT_OUTPUT="$(python3 - "$CONTRACT" <<'PY'
import json
import re
import sys
from pathlib import PurePosixPath

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

verified = data.get("upstream", {}).get("verified_commit")
if not isinstance(verified, str) or not re.fullmatch(r"[0-9a-f]{40}", verified):
    raise SystemExit("upstream.verified_commit must be a 40-character lowercase hex SHA")

paths = data.get("required_upstream_paths")
if not isinstance(paths, list) or not paths:
    raise SystemExit("required_upstream_paths must be a non-empty list")

for item in paths:
    if not isinstance(item, str) or not item.strip():
        raise SystemExit("required_upstream_paths entries must be non-empty strings")
    parsed = PurePosixPath(item)
    if parsed.is_absolute() or ".." in parsed.parts:
        raise SystemExit(f"required_upstream_paths entry must be relative and traversal-free: {item}")

safe = data.get("first_safe_sprint", {})
if safe.get("project_delivery_mode") != "local-only":
    raise SystemExit("first_safe_sprint.project_delivery_mode must be local-only")
if safe.get("yolo_enabled") is not False:
    raise SystemExit("first_safe_sprint.yolo_enabled must be explicitly false")

print(verified)
for item in paths:
    print(item)
PY
)"; then
  fail "Invalid integration contract: $CONTRACT"
fi

mapfile -t CONTRACT_LINES <<<"$CONTRACT_OUTPUT"
EXPECTED_HEAD="${CONTRACT_LINES[0]}"
REQUIRED_PATHS=("${CONTRACT_LINES[@]:1}")
[[ ${#REQUIRED_PATHS[@]} -gt 0 ]] || fail "Invalid integration contract: no required upstream paths resolved"

is_firstmate_clone() {
  local candidate="$1"
  [[ -d "$candidate" ]] || return 1
  [[ "$(git -C "$candidate" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]] || return 1
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

ACTUAL_HEAD="$(git -C "$FIRSTMATE_DIR" rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "First Mate HEAD is $ACTUAL_HEAD, but this integration floor was audited at $EXPECTED_HEAD. Refresh the evidence contract before claiming compatibility."

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
