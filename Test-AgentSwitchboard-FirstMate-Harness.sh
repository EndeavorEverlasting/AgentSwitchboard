#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
Usage:
  bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
  bash Test-AgentSwitchboard-FirstMate-Harness.sh report [--output PATH|--stdout]
  bash Test-AgentSwitchboard-FirstMate-Harness.sh route [selector arguments]
  bash Test-AgentSwitchboard-FirstMate-Harness.sh probe [--firstmate PATH]
EOF
}

MODE="${1:-contract}"
shift || true
case "$MODE" in
  contract)
    python3 tests/test_firstmate_integration_contract.py
    python3 tests/test_firstmate_operational_harness.py
    python3 tests/test_firstmate_windows_harness_portability.py
    python3 tests/test_firstmate_windows_wsl_bridge.py
    bash -n Test-AgentSwitchboard-FirstMate-Harness.sh
    bash -n tooling/firstmate/Test-FirstMateInterop.sh
    bash -n tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPreCommit.sh
    bash -n tooling/firstmate/harness/operational/hooks/Invoke-FirstMateHarnessPrePush.sh
    git diff --check
    git diff --cached --check
    printf '[PASS] FIRSTMATE_OPERATIONAL_HARNESS\n'
    ;;
  report)
    exec python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py "$@"
    ;;
  route)
    exec python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py "$@"
    ;;
  probe)
    exec bash tooling/firstmate/Test-FirstMateInterop.sh "$@"
    ;;
  *)
    usage
    exit 64
    ;;
esac
