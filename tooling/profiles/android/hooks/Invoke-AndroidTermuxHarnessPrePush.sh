#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

if [ -n "$(git status --porcelain)" ]; then
  printf '%s\n' '[FAIL] Pre-push validation requires a clean working tree so validated content equals the commit being pushed.' >&2
  git status --short >&2
  exit 2
fi

command -v python >/dev/null 2>&1 || {
  printf '%s\n' '[FAIL] python is required by the Android Termux harness; run: pkg install -y python' >&2
  exit 3
}
python --version
python tests/test_android_termux_harness.py
bash -n tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh
bash -n tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh

git diff --check

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1
else
  printf '%s\n' '[SKIP] pwsh unavailable; completeness and repository-family status proof are owned by hosted/PowerShell validation on Termux.'
fi

printf '%s\n' '[PASS] Android Termux harness pre-push checks validated the clean HEAD snapshot'
