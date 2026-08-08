#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

python tests/test_android_termux_harness.py

for file in \
  tooling/profiles/android/harness/termux/manifest.json \
  tooling/profiles/android/harness/termux/codebase-map.json \
  tooling/profiles/android/harness/termux/artifact-registry.json \
  tooling/profiles/android/harness/termux/workflows/task-intake.workflow.json \
  tooling/profiles/android/harness/termux/workflows/validate-terminal-boundary.workflow.json \
  tooling/profiles/android/harness/termux/workflows/handle-input-boundary-failure.workflow.json \
  tooling/profiles/android/harness/termux/workflows/capture-terminal-output.workflow.json; do
  python -m json.tool "$file" >/dev/null
done

git diff --check --cached
printf '%s\n' '[PASS] Android Termux harness pre-commit checks'
