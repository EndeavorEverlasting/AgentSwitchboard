"""Negative canary fixture for automated-test-floor fail-closed proofs."""
print("CANARY_DEFECT: intentional failing fixture")
raise SystemExit(1)
