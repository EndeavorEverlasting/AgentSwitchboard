#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

scope=(
  tooling/profiles/android/harness/termux
  tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh
  tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh
  .ai/skills/android-termux-repo-bootstrap/SKILL.md
  .ai/skills/android-termux-terminal-recovery/SKILL.md
  docs/harness/android-termux-operational-harness.md
  tests/test_android_termux_harness.py
  scripts/Test-AndroidTermuxHarnessCompleteness.ps1
  .github/workflows/android-termux-harness.yml
)

if ! git diff --quiet -- "${scope[@]}"; then
  printf '%s\n' '[FAIL] Android harness has unstaged changes in validated paths; stage or revert them before pre-commit validation.' >&2
  exit 2
fi

python tests/test_android_termux_harness.py

for file in \
  tooling/profiles/android/harness/termux/manifest.json \
  tooling/profiles/android/harness/termux/codebase-map.json \
  tooling/profiles/android/harness/termux/artifact-registry.json \
  tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json \
  tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json \
  tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json \
  tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json; do
  git ls-files --error-unmatch -- "$file" >/dev/null
  python -m json.tool "$file" >/dev/null
done

git diff --check --cached
printf '%s\n' '[PASS] Android Termux harness pre-commit checks validated the staged snapshot boundary'
