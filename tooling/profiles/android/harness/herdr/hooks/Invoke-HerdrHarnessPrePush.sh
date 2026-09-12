#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
branch="$(git branch --show-current)"; [ -n "$branch" ] || { printf '%s\n' '[FAIL] pre-push requires an attached branch' >&2; exit 2; }; [ "$branch" != main ] || { printf '%s\n' '[FAIL] Herdr harness pre-push refuses main' >&2; exit 3; }
if [ -n "${EXPECTED_HEAD:-}" ]; then actual="$(git rev-parse HEAD)"; [ "$actual" = "$EXPECTED_HEAD" ] || { printf '[FAIL] expected HEAD %s; observed %s\n' "$EXPECTED_HEAD" "$actual" >&2; exit 4; }; fi
bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh
base="${HERDR_HARNESS_BASE_REF:-origin/main}"; git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || { printf '[FAIL] base ref unavailable: %s; fetch it without force before validation\n' "$base" >&2; exit 5; }
git merge-base --is-ancestor "$base" HEAD || { printf '[FAIL] %s is not an ancestor of HEAD; reconcile current main without force\n' "$base" >&2; exit 6; }
git diff --check "$base...HEAD"; test -z "$(git status --porcelain)"; printf '[PASS] Android Herdr harness pre-push branch=%s head=%s base=%s\n' "$branch" "$(git rev-parse HEAD)" "$base"
