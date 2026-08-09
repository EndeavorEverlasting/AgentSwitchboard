#!/usr/bin/env bash
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
cd "$repo"
bash tooling/profiles/android/harness/herdr/client-attach/hooks/Invoke-HerdrClientAttachHarnessPreCommit.sh
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrClientAttachHarnessCompleteness.ps1
else
  printf '%s\n' '[SKIP] pwsh unavailable; hosted Windows completeness remains required.'
fi
printf '%s\n' '[PASS] Android Herdr client-attach harness pre-push validation'
