#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

python3 tests/test_firstmate_integration_contract.py
python3 tests/test_firstmate_operational_harness.py
bash -n Test-AgentSwitchboard-FirstMate-Harness.sh
bash -n tooling/firstmate/Test-FirstMateInterop.sh
bash -n tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh
bash -n tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPrePush.sh
python3 tests/test_operational_harness.py
git diff --check
printf '[PASS] FIRSTMATE_HARNESS_PRECOMMIT\n'
