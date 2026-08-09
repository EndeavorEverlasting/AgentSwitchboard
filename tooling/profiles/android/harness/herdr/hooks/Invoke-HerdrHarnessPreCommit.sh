#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
scope=(Test-AgentSwitchboard-Android-Herdr.sh tooling/profiles/android/harness/herdr .ai/skills/android-herdr-migration/SKILL.md docs/workstation/android-herdr-migration.md docs/harness/android-herdr-operational-harness.md tests/test_android_herdr_migration.py tests/test_android_herdr_harness_completeness.py scripts/Test-AndroidHerdrHarnessCompleteness.ps1 .github/workflows/android-herdr-migration.yml tooling/profiles/android/harness/termux/manifest.json tooling/profiles/android/harness/termux/codebase-map.json)
if ! git diff --quiet -- "${scope[@]}"; then printf '%s\n' '[FAIL] Herdr harness has unstaged changes in validated paths; stage or revert them first.' >&2; git status --short -- "${scope[@]}" >&2; exit 2; fi
command -v python >/dev/null 2>&1 || { printf '%s\n' '[FAIL] python is required; run: pkg install -y python' >&2; exit 3; }
bash -n Test-AgentSwitchboard-Android-Herdr.sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_harness_completeness.py
git diff --check --cached
printf '%s\n' '[PASS] Android Herdr harness pre-commit validation'
