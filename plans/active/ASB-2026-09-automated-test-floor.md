# ASB-2026-09 Automated Test Floor

## Mission

Bootstrap a deterministic, fail-closed automated test floor for AgentSwitchboard and prove it in GitHub Actions. Infer the stack from repository evidence (PowerShell validators + Python script/unittest contracts). Do not require a novice operator to choose a test framework.

## Phase map

1. **FLOOR-01 — Manifest + canonical runner** *(completed)*
   Explicit runner types, fail-closed zero-gate/zero-unittest behavior, receipt with candidate SHA.
2. **FLOOR-02 — Meta tests + workflow + docs** *(completed)*
   Local negative canary, AFK triggers without cron/secrets.
3. **FLOOR-03 — Provider proof** *(in progress)*
   Exact-head green run, controlled defect fails for the right reason, restore and re-green.
4. **FLOOR-04 — Falsification + handoff**
   Second pass for bypass/false-green gaps; hand evolution to P113; promotion stays with P105.

## Canonical command

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AutomatedTestFloor.ps1
```

## Forbidden

Merge/release/deploy automation, secrets, live runtime mutation, unrelated workflow rewrites, claiming runtime proof from static PASS.

## Proof ceiling

Provider-runtime static floor proof only.
