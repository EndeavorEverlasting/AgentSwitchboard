#!/usr/bin/env bash
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
cd "$repo"
python tests/test_android_herdr_client_attach_harness.py
python tooling/profiles/android/harness/herdr/client-attach/Probe-HerdrClientAttach.py contract
python tests/test_android_herdr_server_start_review.py
python tests/test_android_herdr_harness_completeness.py
git diff --check
printf '%s\n' '[PASS] Android Herdr client-attach harness pre-commit validation'
