#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s --base <exact-base-ref>\n' "$0" >&2
}

BASE=""
while (($#)); do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      BASE="$2"
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

[[ -n "$BASE" ]] || { usage; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
git rev-parse --verify "${BASE}^{commit}" >/dev/null
bash tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh
git diff --check "$BASE"...HEAD
printf '[PASS] FIRSTMATE_HARNESS_PREPUSH base=%s head=%s\n' "$BASE" "$(git rev-parse HEAD)"
