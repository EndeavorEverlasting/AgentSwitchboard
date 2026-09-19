# P67 OpenCode Evaluation Adapter

Concrete implementation plan for replacing P67's generic external-agent placeholder with a bounded runtime path:

`P67 scientific harness -> AgentSwitchboard adapter -> OpenCode V2 provider runtime -> neutral structural evidence -> P67 grading`.

## Evidence floor

- AgentSwitchboard: `main@320998d` (includes PR #312 TRIAGE-01, #313, #314 routing-builder salvage).
- P67 Gen2: integrated/deployed in `EndeavorEverlasting/web-excel-repair-triage@e0038eec048af029f6f27bb2f0dc70f875e09e06`.
- Gen2 control is the byte-frozen pre-`a583b333` baseline; treatment is released Operant v0.9.0 at `fc9437ff3fa83ce9df82c6ad85a79d09d7e0bd17`.
- P67 already owns argv-only execution, temporary result transport, privacy allowlists, pair identity, timeouts, isolated workspaces, and invalid-run semantics.
- AgentSwitchboard owns provider/runtime routing and evidence normalization. FirstMate remains the canonical crew/session runtime; this adapter must not become another scheduler.
- Registry now registered after PR #309 was salvaged via #314 onto main; registry includes TRIAGE-01 and FM-ASB-ROUTING-REQUEST-BUILDER entries.

## Architectural decision

| Surface | Owner | Responsibility |
| --- | --- | --- |
| experiment identities, cases, pairing, grading, thresholds, validity | Triage P67 | scientific authority |
| provider launch, readiness, subprocess boundary, neutral event normalization | AgentSwitchboard | runtime/evidence transport |
| model/tool runtime | OpenCode V2 + explicit provider/model | external execution |
| crew lifecycle / durable task delivery | FirstMate | unchanged canonical owner |

The first backend is OpenCode V2. Implementation must verify the exact installed/upstream capability set before relying on CLI flags, config, plugins, or event shapes.

### Measurement-integrity rule

The runtime being evaluated must **not grade itself**.

Before observed Gen2 runs, Triage must version the capture boundary so the adapter emits neutral structural telemetry only. Evaluative judgments such as usefulness, first-green sufficiency, true fixed point, contract correctness, and effectiveness are derived by P67 from deterministic workspace/validation/contract evidence.

## Dependency graph

Two lanes start in parallel:

1. **ADP-00 — Triage neutral-capture authority.** Version the capture/annotation boundary; add negative self-rating and positive neutral-telemetry fixtures.
2. **ADP-01 — ASB OpenCode capability/readiness.** Verify noninteractive structured execution, explicit provider/model/agent identity, isolated config/instrumentation, auth/quota readiness, and typed blockers.

They converge into **ADP-02**, the actual adapter.

## Canonical implementation surfaces

Planned ASB owner: `tooling/evals/p67-opencode-adapter/`

- `Get-P67OpenCodeAdapterStatus.ps1` — read-only capability/provider readiness.
- `Invoke-P67OpenCodeAdapter.ps1` — canonical P67 argv target.
- `New-P67AdapterConfig.ps1` — machine-local config generator; never stores secret values.
- deterministic neutral-event normalizer.
- local instrumentation plugin that records structural tool/session/subagent lifecycle only.
- `tests/test_p67_opencode_adapter.py`.
- `scripts/Test-P67OpenCodeAdapter.ps1`.

Generated P67 config shape:

```json
{
  "schema_version": "compute-authority-agent-adapter/v1",
  "argv": [
    "pwsh", "-NoLogo", "-NoProfile", "-File",
    "<ASB>/tooling/evals/p67-opencode-adapter/Invoke-P67OpenCodeAdapter.ps1",
    "-Workspace", "{workspace}",
    "-Task", "{task}",
    "-Prompt", "{prompt}",
    "-Result", "{result}"
  ],
  "timeout_seconds": 900,
  "env_allowlist": ["<credential variable names only>"]
}
```

The file contains names, paths, provider/model identity and limits—not credential values.

## Runtime contract

For each run the adapter:

1. accepts only workspace/task/frozen-prompt/result placeholders;
2. resolves exact OpenCode/provider/model/agent identity;
3. starts isolated execution rooted at the fixture workspace;
4. applies only evaluation-owned config/instrumentation;
5. prevents project/global config drift from silently changing the experiment;
6. enforces workspace, external-directory, process-tree, and timeout bounds;
7. keeps raw provider stdout/stderr/model text ephemeral;
8. emits one sanitized neutral result JSON;
9. cleans its own ephemeral state without deleting P67 evidence;
10. returns nonzero for transport/launch failure so P67 records INVALID.

Pair members must use the same resolved provider/agent/model identity.

## Neutral telemetry

Adapter may report structural identity, action/tool category, action index, monotonic timestamps, independently observed validation identity/return code, child/subagent lane timing, termination reason, and trustworthy provider usage/cost counters.

Adapter may **not** decide usefulness, first-green semantic sufficiency, true fixed point, contract correctness, seeded-defect success, or treatment effectiveness.

## Phases

- **ADP-00 — Neutral capture authority (Triage):** ✓ COMPLETE. Self-rating rejected; neutral telemetry accepted; frozen prompt identities unchanged.
- **ADP-01 — Capability/readiness (ASB):** ✓ COMPLETE. Exact capabilities and provider identity proven or one typed blocker.
- **ADP-02 — Adapter + instrumentation (ASB):** ✓ COMPLETE. P67 placeholder invocation produces privacy-bounded neutral JSON; timeout/nonzero/missing-result fail closed.
- **ADP-03 — Synthetic interoperability:** ✓ COMPLETE. Fake structured events exercise action, validation, subagent/parallel, timeout, malformed-result, privacy, and mutation-boundary paths. 8 synthetic fixtures + durable runner + machine-readable receipt. Proof: SYNTHETIC_INTEROPERABILITY only.
- **ADP-04 — Observed adapter smoke:** one TC01 control/treatment pair. If real worker capacity >=2, add one TC06 pair. Smoke proves adapter runtime only, not effectiveness.
- **ADP-05 — Gen2 16-run pilot:** 16 classified paired runs, stable pair identity, zero forbidden escape/gold leakage, pilot aggregate and fixture-validity disposition.
- **ADP-06 — P67 Sprint 3:** only after valid pilot; keep Gen2 treatment and thresholds frozen.

## Safety and collisions

- No FirstMate scheduler expansion.
- No provider login automation or tracked credentials.
- No raw prompt/response/transcript/clipboard/query/tool-output persistence.
- No global OpenCode config mutation.
- No full pilot before neutral-capture + synthetic + smoke gates.
- No static/synthetic/smoke proof promoted into effectiveness.
- GNHF may later become another backend only behind the same proven adapter contract; it is not a hidden v1 measurement layer.

## Validation

1. Triage neutral-capture focused tests.
2. ASB capability/readiness fixtures.
3. ASB adapter synthetic tests.
4. `pwsh -NoLogo -NoProfile -File scripts/Test-P67OpenCodeAdapter.ps1`.
5. `pwsh -NoLogo -NoProfile -File scripts/Test-AgentGovernanceDoctrine.ps1`.
6. `pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1` after registry ownership is available.
7. `pwsh -NoLogo -NoProfile -File scripts/Prove-AutomatedTestFloorLocal.ps1`.
8. `git diff --check`.
9. bounded live smoke.
10. Gen2 16-run pilot.

## Proof ceiling

Current: **SYNTHETIC INTEROPERABILITY (ADP-03)**.

ADP-00 through ADP-03 are COMPLETE: neutral capture contract integrated, capability/readiness probe validated, adapter implementation complete, synthetic interoperability proven via 8-path fixture coverage with machine-readable receipt. Live OpenCode smoke (ADP-04) remains pending. Only the P67 pilot can promote the tested Gen2 population to observed pilot behavior; the final effectiveness verdict remains Sprint 3.

## Cross-repository coordination

Triage scientific/capture authority is integrated via PR #559 / merge `ce22389e10813b7ed611d56d2c19b6afe5bfcbb6`.

## Immediate next action

ADP-03 COMPLETE. Next: **ADP-04 bounded observed adapter smoke** with real OpenCode provider auth/quota on authorized workstation/runtime. One TC01 paired smoke (control/treatment), conditional TC06 paired parallel smoke only when >=2 real worker slots exist. Smoke proves adapter runtime only, not effectiveness. No live smoke until operator confirms provider readiness and machine-local config.
