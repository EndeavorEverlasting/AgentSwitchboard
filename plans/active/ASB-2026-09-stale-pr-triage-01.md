# Closed-PR Semantic Salvage and Porting Convergence Plan

**Plan ID:** `ASB-2026-09-STALE-PR-TRIAGE-01`
**Repository:** `EndeavorEverlasting/AgentSwitchboard`
**Planning evidence floor:** `main@72d71a74279c5cf1b0c029b68d03c76634d50ea1`
**Current execution floor:** `main@212e2cf3fb31b675fda7205b01f8760046371818`
**Completed slices:** Panel 01 / PR #341 -> `7e637307de01116069b4067b351b96188d12e989`; Panel 02 / PR #342 -> `31d57167330e85fb7b8fc52ab47ceef348771b04`; Lua review recovery PR #343 -> `dd344b339ffc9fa2d417a785f6b17d493fcb2659`; Panel 03 / PR #345 -> `170da052de065e584baa07bce35ccba8d06eebf6`; Panel 04 / PR #348 -> `212e2cf3fb31b675fda7205b01f8760046371818`
**Status:** active / critical
**Plan integration:** PR #339 merged as `67df85da2026104e00ff6bd7c926db0139ca4f63`
**Canonical machine owner:** `plans/active/ASB-2026-09-stale-pr-triage-01.plan.json`
**Portability panel pack:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md`

## 1. LAUNCH ORDER

1. **DONE — Panel 01 / PR #113 OpenCode runtime-resolution semantic salvage** — PR #341 / merge `7e637307de01116069b4067b351b96188d12e989`.
2. **DONE — Panel 02 / PR #112 Lua embedding leaf salvage** — PR #342 / merge `31d57167330e85fb7b8fc52ab47ceef348771b04`; post-merge repair PR #343 / `dd344b339ffc9fa2d417a785f6b17d493fcb2659`.
3. **DONE — Panel 03 / PR #118 external-agent tooling leaf salvage** — PR #345 / merge `170da052de065e584baa07bce35ccba8d06eebf6`.
4. **DONE — Panel 04 / PR #64 Windows machine-profile forensic salvage** — PR #348 / merge `212e2cf3fb31b675fda7205b01f8760046371818`.
5. **BLOCKED — Panel 05 / PR #92 execution-actor routing reconciliation** — PR #118 dependency is satisfied; ASQ-022 still owns active execution-adapter successor work and has not handed off disjoint paths.
6. **READY / NEXT — Panel 06 / PR #79 agent-fleet readiness reconciliation** — machine-profile dependency satisfied by Panel 04.
7. **WAIT — Panel 07 / final convergence and cleanup** — single writer after Panels 05 and 06 have supported terminal dispositions.

**Next executable lane:** Panel 06 / PR #79.
**Waiting lane:** Panel 05 / PR #92, ownership-blocked on ASQ-022.
**Final convergence:** Panel 07.

## 2. PARALLEL DISPATCH MANIFEST

**PARALLEL EXECUTION: NOT_APPLICABLE — current TRIAGE-01 dependency graph width is 1.**

Panels 01-04 are integrated. Panel 06 / PR #79 is the only dependency-ready implementation lane. Panel 05 / PR #92 is blocked by execution-adapter ownership, not by worker capacity. Serial execution of Panel 06 is therefore correct.

The previously recorded autonomy gap remains tracked by ASQ-031 for future multi-lane dispatch; TRIAGE-01 must not invent a second scheduler or claim observed parallelism without a real adapter.

## 3. COMPACT COORDINATION PREAMBLE

- Planning evidence floor: `main@72d71a74279c5cf1b0c029b68d03c76634d50ea1`; current execution floor at this progress checkpoint: `main@212e2cf3fb31b675fda7205b01f8760046371818`; open overlapping TRIAGE-01 PRs: **0**; unrelated PR #347 is plan-only.
- Local worker path authority: resolve `temporaryWorktreeRoot` from `tooling/harness/operational/canonical-path.contract.json`; the Windows technician binding is `%LOCALAPPDATA%\\AgentSwitchboard\\worktrees`. Never derive a sibling directory from whichever checkout invoked the panel.
- Proven completed floor: PR #94 Wayfinder core semantic salvage merged as #338 / `72d71a74279c5cf1b0c029b68d03c76634d50ea1`.
- Preserve historical source branches until final preservation checks; do not bulk merge or bulk cherry-pick.
- Workers own leaf behavior and focused proof. Shared `SKILLS.md`, `TRIGGERS.md`, `CODEBASE_MAP.md`, `HARNESS.md`, plans, ledger, and shared operational registries are convergence-owner surfaces.
- Hard collision families:
  - #113 ↔ current OpenCode LSP + P67 + execution-adapter v1.
  - #92 ↔ current execution-adapter v1 and operational harness. **Hard gate:** ASQ-022 must be terminal or explicitly hand off disjoint execution-adapter paths before #92 mutation.
  - #64 ↔ current machine-profile/bootstrap/device-profile contracts.
  - #79 ↔ #64/current machine-profile + Windows profile ownership.
  - #118 ↔ shared operational registries.
  - #112 is leaf-isolated because `tooling/lua` is absent on current main.
- Proof ceiling: static/synthetic repository proof unless a later authorized runtime lane observes more.

## 4. PORTABILITY FALLBACK SPRINT PANELS

The complete panels live in `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` in exactly the launch order above. They are fallback transport, not dispatch proof.

## 5. SUPPORTING FACTORING LEDGER

### TOPICS FOUND

| Topic | Primary ownership | Disposition |
|---|---|---|
| Historical 47-PR triage | docs/reporting / coordination | Preserve as superseded provenance; no longer current truth |
| PR #94 Wayfinder core | harness spine + agent harness | **Integrated** via #338; residual August shared wiring remains forensic-only |
| PR #113 runtime resolution | Windows/OpenCode harness + integration seam | **Integrated via #341** |
| PR #112 Lua embedding | isolated harness spine | **Integrated via #342 + #343 repair** |
| PR #118 external tooling catalog | operational harness leaf + validation | **Integrated via #345** |
| PR #64 machine-profile harness | Windows profile harness | **Integrated via #348; non-main historical base reconstructed** |
| PR #92 execution actor routing | execution-adapter / operational integration | **Reconcile, probably merge/retire concepts rather than restore router** |
| PR #79 fleet readiness | Windows agent harness + profile integration | **Reconcile after #64** |
| Shared skills/triggers/maps/registries | integration seam | **Final convergence owner only** |
| Live runtime proof | runtime proof | Deferred; not implied by static salvage |
| Branch deletion/cleanup | release/PR hygiene | Last only after preservation proof |

### HARNESS FACTORING

- **Run context / evidence:** current `AGENTS.md`, public plan, WORK_QUEUE, exact source branch SHA, refreshed main, focused validator output, exact candidate SHA.
- **Artifact registries:** leaf registries may be salvaged; shared operational registries are convergence-owned.
- **Schemas / fixtures:** preserve negative fixtures when they still test a current invariant; reject stale schema duplicates.
- **Validators:** focused historical validator is evidence to inspect, not automatic authority; current-main owning validator wins after reconciliation.
- **Workflows:** historical GitHub Actions are adapters, not semantic owners; recreate only if current contract still needs a hosted adapter.
- **Skills / capabilities / triggers:**
  - #113 `opencode-runtime-resolution`: **integrated as a bounded leaf via #341**; shared historical routing was not replayed.
  - #92 `execution-actor-routing`: **prefer retire/merge into execution-adapter v1** unless a unique reusable judgment workflow remains.
  - #79 `agent-fleet-readiness`: **split** reusable judgment into skill and deterministic readiness operation into code/registry; no second bootstrap lifecycle.
  - #112 `lua-embedding-integration`: **integrated as an isolated leaf via #342/#343**; runtime proof remains separately bounded.
  - #64 old machine-profile changes: **integrated via #348 into current machine-profile ownership**; stale path/launcher duplication was retired.
  - #118 `external-agent-tooling-intake`: **integrated via #345 as evidence intake only**; catalog presence still grants no install/trust/execution authority.
- **MCP/tools/hooks:** no successor lane may claim a tool/runtime exists from old files. Hooks are leaf-local unless current repository registration explicitly adopts them.

### APPLICATION LOGIC FACTORING

These six candidates are primarily harness/integration work. No conventional domain service, persistence store, UI, business-state machine, or deployment owner should be created merely to salvage them.

Runtime-facing logic is limited to:
- #113 OpenCode runtime/path resolution readback and diagnosis.
- #64/#79 Windows machine/profile readiness and launcher-adjacent contracts.
- #92 execution-request actor binding relative to current adapter v1.
- #112 Lua embedding sandbox contract.
- #118 external tooling evidence catalogue.

Application/product behavior must remain in deterministic code/contracts, never only in the sprint prompts.

### SPRINT CANDIDATES

| Lane | Why now | Likely owned changes | Forbidden | Dependency | Risk | Proof ceiling |
|---|---|---|---|---|---|---|
| #113 | Highest semantic value + collision complexity | Leaf runtime-resolution contracts/tests/docs after reconciliation | wholesale shared docs/workflows | #94 floor | High | static/synthetic unless Windows lane added |
| #112 | Clean leaf, absent on main | `tooling/lua/**`, focused tests/docs | shared routing docs | #94 floor | Medium | static/synthetic |
| #118 | Small leaf and easy to delegate | external-agent-tooling leaf/tests/docs | shared operational registries | #94 floor | Medium | static/synthetic |
| #64 | Deep Windows owner debt; historical non-main base | current machine-profile owner only | blind commit replay / duplicate launcher | #94 floor | High | static/synthetic; runtime separate |
| #92 | Old actor router collides with modern adapter v1 | missing invariants/fixtures in adapter v1 | restore competing router | #118 disposition + ASQ-022 ownership release/handoff | High | static/synthetic |
| #79 | Fleet semantics depend on current machine-profile truth | leaf readiness behavior/tests | duplicate profile/bootstrap lifecycle | #64 disposition | High | static/synthetic |
| Convergence | Shared wiring must be written once | shared skills/triggers/maps/registries + plan/ledger | unrelated features | all lanes | High | integration proof |

## RECOMMENDED EXECUTION ORDER

The durable panel sequence is exactly: **01 #113, 02 #112, 03 #118, 04 #64, 05 #92, 06 #79, 07 convergence**. Panels 01-04 are dependency-ready in parallel; Panel 05 waits on 03; Panel 06 waits on 04.

## Current exact source identities

| PR | Head | Ahead / behind main | Key collision |
|---|---|---:|---|
| #113 | `2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9` | 13 / 608 | OpenCode LSP, P67, execution adapters |
| #112 | `3053e1898c1de351faf2215d72947f5bd5d880de` | 6 / 608 | shared docs only; `tooling/lua` absent on main |
| #118 | `87abb4546ee1ef440897dfd86a49e58dab827ee6` | 1 / 608 | operational registries |
| #64 | `45b44b158d7f44e18dfbc6c24120a0c02924f48b` | 22 / 732 | machine-profile/bootstrap; historical base is not main |
| #92 | `acc652d5dc7599b18d76983fb96dbd628d2bd759` | 5 / 638 | execution-adapter v1 / operational harness |
| #79 | `b3560cd56e98f7b91dfff2e060c8a27d1c76e76a` | 36 / 701 | machine-profile / Windows profile |

## Proof boundary

This plan proves the current provider floor, current source identities, dependency/collision factoring, and the durable successor map once merged. It does **not** prove any successor implementation, local worktree state, actual parallel dispatch, runtime behavior, or deployment.
