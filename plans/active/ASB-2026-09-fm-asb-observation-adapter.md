# ASB-2026-09 FirstMate→ASB observation adapter

Phase map for translating FirstMate `fm-fleet-snapshot.v1` into `asb.agent-observation/v1` without a second watcher.

## Completed floor

| Phase | Result | Evidence |
|---|---|---|
| Protocol contract freeze | **INTEGRATED** | PR #184 / merge `6c80be9c…` |
| Observation adapter v1 | **INTEGRATED** | PR #204 / merge `5187195382584787bf30c7043660d74327549cd7` on main; contained in later heads via ancestor check |
| Admin Box adoption of Phase-2 head | **PROVEN** | Live checkout `AgentSwitchBoard-Live` refreshed; adapter tests 13/13 PASS; protocol contract 90/90 PASS @ `af7f013` then tip |
| Disposable-home live emitter→adapter | **OBSERVED** | Admin Box Ubuntu: FirstMate pin `b182d0f` `fm-fleet-snapshot.sh --json` → ASB `emit_agent_observation.py`; receipt under `%LOCALAPPDATA%\AgentSwitchboard\runtime-proof\fm-asb-observation\20260914T204242Z\` |

## Successor phases

1. **Operator/crew live observation (current gap).** Emit observation from an actual FirstMate operator home / live crew task (not disposable seeded `FM_HOME`). Preserve privacy bounds. Expected artifact: local receipt with live taskId + non-fixture generated timestamp.
2. **Crew-state fidelity.** Disposable seed observed `phase=unknown` for a `working:` status line; prove `working→running` (and other mappings) against FirstMate crew-state on a real or correctly instrumented home.
3. **Phase 3 — Prompt Kit routing adapter.** Consume observations into `asb.routing-request/v1` / decision path. Out of observation mutation scope.
4. **Later — prompt dispatch / rollover.** Durable inbox + context-pressure automation. Out of current slice.

## Owned / forbidden

- Owned: observation adapter, fixtures, regressions, live observation receipts (untracked), durable phase-map cite.
- Forbidden: `fm-send` / `fm-control`, new watcher/scheduler, Prompt Kit routing implementation in this plan's mutation scope, committing machine-local receipts/secrets, personal FirstMate home mutation.

## Proof ceiling

Disposable-home OBSERVED proves the real FirstMate JSON emitter and ASB adapter on Admin Box WSL. It does **not** prove operator-crew observation, Prompt Kit routing, or rollover.

## Validation

```text
python tests/test_firstmate_agent_observation_adapter.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
```

## Next command (operator/crew observation)

Owner: Admin Box operator. Dependency: an authorized FirstMate home with at least one live task (or FM-WSL-12 physical-floor PASS creating one). Do not use the disposable cache home as operator proof.
