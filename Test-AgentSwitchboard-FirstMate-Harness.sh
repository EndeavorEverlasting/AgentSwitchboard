#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
Usage:
  bash Test-AgentSwitchboard-FirstMate-Harness.sh contract
  bash Test-AgentSwitchboard-FirstMate-Harness.sh probe [--firstmate PATH]
EOF
}

MODE="${1:-contract}"
shift || true
case "$MODE" in
  contract)
    python3 tests/test_firstmate_integration_contract.py
    python3 tests/test_firstmate_discovery_behavior.py
    python3 tests/test_firstmate_recovery_routing.py
    python3 tests/test_firstmate_asb_convergence_contract.py
    python3 tests/test_firstmate_operational_harness.py
    python3 tests/test_firstmate_windows_harness_portability.py
    python3 tests/test_firstmate_windows_wsl_bridge.py
    python3 tests/test_firstmate_windows_wsl_prerequisite_gate.py
    bash -n Test-AgentSwitchboard-FirstMate-Harness.sh
    bash -n tooling/firstmate/Test-FirstMateInterop.sh
    git diff --check
    git diff --cached --check
    printf '[PASS] FIRSTMATE_OPERATIONAL_BRIDGE_HARNESS\n'
    printf '[PROOF_CEILING] Contract only; no physical WSL or live FirstMate crew runtime.\n'
    ;;
  probe)
    exec bash tooling/firstmate/Test-FirstMateInterop.sh "$@"
    ;;
  *)
    usage
    exit 64
    ;;
esac
