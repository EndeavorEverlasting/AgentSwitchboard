#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT="$SCRIPT_DIR/harness/integration-contract.json"
UPSTREAM_PIN="$SCRIPT_DIR/harness/upstream-pin.json"
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
[[ -f "$UPSTREAM_PIN" ]] || fail "Missing upstream pin: $UPSTREAM_PIN"
[[ "$(uname -s)" == "Linux" ]] || fail "This sprint proves only the Linux/WSL integration lane. Native Windows is out of scope."

for tool in git gh tmux python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "Required tool is unavailable in this Linux environment: $tool"
done

CONTRACT_OUTPUT=""
if ! CONTRACT_OUTPUT="$(python3 - "$CONTRACT" "$UPSTREAM_PIN" <<'PY'
import json
import re
import sys
from pathlib import PurePosixPath

contract_path = sys.argv[1]
pin_path = sys.argv[2]
with open(contract_path, encoding="utf-8") as handle:
    data = json.load(handle)
with open(pin_path, encoding="utf-8") as handle:
    pin = json.load(handle)

verified = data.get("upstream", {}).get("verified_commit")
pin_commit = pin.get("commit")
if not isinstance(verified, str) or not re.fullmatch(r"[0-9a-f]{40}", verified):
    raise SystemExit("upstream.verified_commit must be a 40-character lowercase hex SHA")
if not isinstance(pin_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", pin_commit):
    raise SystemExit("upstream-pin.json commit must be a 40-character lowercase hex SHA")
if verified != pin_commit:
    raise SystemExit("integration-contract verified_commit must match upstream-pin.json commit")

stale = data.get("upstream", {}).get("pr96_audited_commit")
if isinstance(stale, str) and stale == verified:
    raise SystemExit("verified_commit must not remain on the historical PR #96 audit SHA")

paths = data.get("required_upstream_paths")
if not isinstance(paths, list) or not paths:
    raise SystemExit("required_upstream_paths must be a non-empty list")

for item in paths:
    if not isinstance(item, str) or not item.strip():
        raise SystemExit("required_upstream_paths entries must be non-empty strings")
    if any(ch in item for ch in ("\n", "\r", "\0")):
        raise SystemExit("required_upstream_paths entries must not contain control characters")
    parsed = PurePosixPath(item)
    if parsed.is_absolute() or ".." in parsed.parts:
        raise SystemExit(f"required_upstream_paths entry must be relative and traversal-free: {item}")

safe = data.get("first_safe_sprint", {})
if safe.get("project_delivery_mode") != "local-only":
    raise SystemExit("first_safe_sprint.project_delivery_mode must be local-only")
if safe.get("yolo_enabled") is not False:
    raise SystemExit("first_safe_sprint.yolo_enabled must be explicitly false")

platform = data.get("platform_contract", {})
if platform.get("native_windows") != "unverified and out of scope":
    raise SystemExit("platform_contract.native_windows must remain unverified and out of scope")
if platform.get("windows_host_role") != "bridge_only":
    raise SystemExit("platform_contract.windows_host_role must be bridge_only")

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

has_required_upstream_paths() {
  local candidate="$1"
  local path
  for path in "${REQUIRED_PATHS[@]}"; do
    # The path must be part of the audited commit itself. A worktree-only ignored
    # file, directory, or symlink cannot satisfy the contract merely by existing.
    git -C "$candidate" cat-file -e "$EXPECTED_HEAD:$path" 2>/dev/null || return 1
    [[ -e "$candidate/$path" ]] || return 1
  done
  return 0
}

is_viable_discovered_firstmate() {
  local candidate="$1"
  local dirty head
  is_firstmate_clone "$candidate" || return 1
  dirty="$(git -C "$candidate" status --porcelain=v1 2>/dev/null || true)"
  [[ -z "$dirty" ]] || return 1
  head="$(git -C "$candidate" rev-parse HEAD 2>/dev/null || true)"
  [[ "$head" == "$EXPECTED_HEAD" ]] || return 1
  has_required_upstream_paths "$candidate"
}

if [[ -z "$FIRSTMATE_DIR" ]]; then
  # Prefer $HOME/firstmate whenever it is already a FirstMate clone (any state).
  # Bounded bootstrap cannot replace that path; dirty/pin/path checks must surface it.
  if is_firstmate_clone "$HOME/firstmate"; then
    FIRSTMATE_DIR="$HOME/firstmate"
  else
    # Alternate auto-discovery must not false-block bounded $HOME/firstmate
    # bootstrap: skip dirty/off-pin/incomplete leftovers under ~/dev, ~/Projects,
    # $PWD, etc. A discovered clone is viable only when the audited path contract
    # is present in both the audited Git tree and the worktree before selection.
    candidates=(
      "$PWD"
      "$HOME/dev/firstmate"
      "$HOME/src/firstmate"
      "$HOME/Projects/firstmate"
      "$HOME/projects/firstmate"
    )
    for candidate in "${candidates[@]}"; do
      if is_viable_discovered_firstmate "$candidate"; then
        FIRSTMATE_DIR="$candidate"
        break
      elif is_firstmate_clone "$candidate"; then
        note "Skipping non-viable auto-discovery candidate ${candidate} (dirty, off audited pin, or missing required audited paths); continuing toward bounded \$HOME/firstmate bootstrap"
      fi
    done
  fi
fi

# Bounded Admin Box helper: clone audited FirstMate to $HOME/firstmate at the
# contract pin when discovery misses. Never mutates an existing path or upstream.
if [[ -z "$FIRSTMATE_DIR" ]]; then
  bootstrap_dir="$HOME/firstmate"
  clone_url="https://github.com/${EXPECTED_ORIGIN}.git"
  note "First Mate clone not found; attempting bounded bootstrap at ${bootstrap_dir} @ ${EXPECTED_HEAD}"
  if [[ -e "$bootstrap_dir" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=repair or remove %s so bounded bootstrap can clone %s@%s, or re-run with --firstmate PATH / FIRSTMATE_DIR\n' "$bootstrap_dir" "$EXPECTED_ORIGIN" "$EXPECTED_HEAD"
    exit 50
  fi
  if ! git clone --quiet "$clone_url" "$bootstrap_dir"; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=manually clone %s to %s and checkout %s, then rerun\n' "$clone_url" "$bootstrap_dir" "$EXPECTED_HEAD"
    exit 50
  fi
  if ! git -C "$bootstrap_dir" checkout --quiet "$EXPECTED_HEAD"; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=in %s run: git fetch --all && git checkout %s, then rerun\n' "$bootstrap_dir" "$EXPECTED_HEAD"
    exit 50
  fi
  FIRSTMATE_DIR="$bootstrap_dir"
  note "BOOTSTRAPPED_FIRSTMATE=${FIRSTMATE_DIR}@${EXPECTED_HEAD}"
fi

[[ -n "$FIRSTMATE_DIR" ]] || fail "First Mate clone not found. NEXT=re-run with --firstmate PATH or set FIRSTMATE_DIR."
FIRSTMATE_DIR="$(cd -- "$FIRSTMATE_DIR" && pwd)"
if ! is_firstmate_clone "$FIRSTMATE_DIR"; then
  printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
  printf 'NEXT=point --firstmate at a clean %s checkout (audited pin %s), then rerun\n' "$EXPECTED_ORIGIN" "$EXPECTED_HEAD"
  exit 50
fi

status="$(git -C "$FIRSTMATE_DIR" status --porcelain=v1)"
if [[ -n "$status" ]]; then
  printf 'STATUS=BLOCKED_FIRSTMATE_DIRTY\n'
  printf 'NEXT=commit/stash/move dirty work in %s, or remove that path so bounded bootstrap can run, then rerun\n' "$FIRSTMATE_DIR"
  exit 49
fi

ACTUAL_HEAD="$(git -C "$FIRSTMATE_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_HEAD" != "$EXPECTED_HEAD" ]]; then
  printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
  printf 'NEXT=in %s run: git fetch --all && git checkout %s, then rerun\n' "$FIRSTMATE_DIR" "$EXPECTED_HEAD"
  exit 50
fi

# Distinguish a damaged local object database from a healthy audited commit whose
# contents contradict AgentSwitchboard's required-path contract. Retrying the same
# SHA cannot repair a healthy commit that genuinely lacks a required path.
if ! git -C "$FIRSTMATE_DIR" fsck --no-dangling "$EXPECTED_HEAD" >/dev/null 2>&1; then
  printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
  printf 'NEXT=repair local FirstMate Git objects in %s (git fetch --all --prune, then verify git fsck %s) and rerun; if integrity remains broken, replace the local checkout without changing the audited pin\n' "$FIRSTMATE_DIR" "$EXPECTED_HEAD"
  exit 50
fi

for path in "${REQUIRED_PATHS[@]}"; do
  if ! git -C "$FIRSTMATE_DIR" cat-file -e "$EXPECTED_HEAD:$path" 2>/dev/null; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=the healthy audited FirstMate commit %s does not contain required path %s; repair AgentSwitchboard tooling/firstmate/harness/integration-contract.json and tooling/firstmate/harness/upstream-pin.json (or refresh the audited pin) before rerun; do not retry the same SHA checkout\n' "$EXPECTED_HEAD" "$path"
    exit 50
  fi
  if [[ ! -e "$FIRSTMATE_DIR/$path" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=restore required audited path %s in %s from commit %s (git restore --source %s -- %s), then rerun\n' "$path" "$FIRSTMATE_DIR" "$EXPECTED_HEAD" "$EXPECTED_HEAD" "$path"
    exit 50
  fi
done

HARNESS=""
for candidate in claude grok pi pi-signed omp codex opencode cursor-agent; do
  if command -v "$candidate" >/dev/null 2>&1; then
    HARNESS="$candidate"
    break
  fi
done
if [[ -z "$HARNESS" ]]; then
  printf 'STATUS=BLOCKED_PRIMARY_HARNESS\n'
  printf 'NEXT=install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun\n'
  exit 48
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  printf 'STATUS=BLOCKED_GITHUB_AUTH\n'
  printf 'NEXT=run gh auth login inside Ubuntu, then rerun\n'
  exit 45
fi

note "First Mate path: $FIRSTMATE_DIR"
note "First Mate audited HEAD: $ACTUAL_HEAD"
note "Primary harness available: $HARNESS"
note "tmux: $(tmux -V)"
printf '[PASS] FIRSTMATE_INTEROP=repository-and-toolchain-floor\n'
printf '[PROOF_CEILING] No First Mate task was dispatched; no project remote, PR, merge, credentials, or dependencies were mutated. Bounded local clone of the audited FirstMate pin into $HOME/firstmate is environment setup only. Physical WSL crew proof and Windows bridge remain out of scope for this foundation.\n'
