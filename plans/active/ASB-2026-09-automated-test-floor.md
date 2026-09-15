# ASB-2026-09 Automated Test Floor

## Mission

Bootstrap a deterministic, fail-closed automated test floor for AgentSwitchboard and prove it in GitHub Actions. Infer the stack from repository evidence (PowerShell validators + Python script/unittest contracts). Do not require a novice operator to choose a test framework.

## Phase map

1. **FLOOR-01 — Manifest + canonical runner** *(completed)*
   Explicit runner types, fail-closed zero-gate/zero-unittest behavior, receipt with candidate SHA.
2. **FLOOR-02 — Meta tests + workflow + docs** *(completed)*
   Local negative canary, AFK triggers without cron/secrets.
3. **FLOOR-03 — Provider proof** *(completed)*
   Exact-head green run, controlled defect fails for the right reason, restore and re-green.
4. **FLOOR-04 — Falsification + handoff** *(completed)*
   Second pass repaired PR-head SHA logging and trailing-whitespace hygiene; hand evolution to P113; promotion stays with P105.
5. **FLOOR-05 — Closeout hardening** *(completed)*
   Actions-quota local proof packet, receipt provenance, quota-aware CI triggers; merged via PR #291 @ `3c5cca9`; ASQ DONE via PR #292 @ `1f8c32a`.

## Canonical command

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AutomatedTestFloor.ps1
```

Actions-quota local proof:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Prove-AutomatedTestFloorLocal.ps1
```

## Forbidden

Merge/release/deploy automation, secrets, live runtime mutation, unrelated workflow rewrites, claiming runtime proof from static PASS.

## Proof ceiling

Provider-runtime static floor proof only. Local proof substitutes for Actions minutes, not for merge authority.
