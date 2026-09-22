# Closed-PR Semantic Salvage and Porting Convergence Plan

**Plan ID:** `ASB-2026-09-STALE-PR-TRIAGE-01`
**Repository:** `EndeavorEverlasting/AgentSwitchboard`
**Current floor:** `main@72d71a74279c5cf1b0c029b68d03c76634d50ea1`
**Status:** active / critical
**Canonical machine owner:** `plans/active/ASB-2026-09-stale-pr-triage-01.plan.json`
**Portability panel pack:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md`

## 1. LAUNCH ORDER

1. **Panel 01 — PR #113 OpenCode runtime-resolution semantic salvage** — Wave 1, strong agent.
2. **Panel 02 — PR #112 Lua embedding leaf salvage** — Wave 1, bounded lower-capability agent.
3. **Panel 03 — PR #118 external-agent tooling leaf salvage** — Wave 1, bounded lower-capability agent.
4. **Panel 04 — PR #64 Windows machine-profile forensic salvage** — Wave 1, strong agent.
5. **Panel 05 — PR #92 execution-actor routing reconciliation** — Wave 2; wait for Panel 03 because both occupy the operational harness namespace.
6. **Panel 06 — PR #79 agent-fleet readiness reconciliation** — Wave 2; wait for Panel 04 because fleet readiness depends on the current machine-profile owner.
7. **Panel 07 — Final convergence and cleanup** — single writer after Panels 01-06 are validated or explicitly dispositioned.

**First chat / strongest-agent lane:** Panel 01.
**Parallel group 1:** Panels 01-04.
**Waiting lanes:** Panel 05 waits on Panel 03; Panel 06 waits on Panel 04.
**Final convergence:** Panel 07.

## 2. PARALLEL DISPATCH MANIFEST

**PARALLEL EXECUTION: DEGRADED — graph width is 4, but the current planning runtime does not expose an AgentSwitchboard/OpenCode/FirstMate worker-execution adapter.**

The prompt-assumed artifacts do not exist on current main:
- `harness/contracts/prompt-parallel-dispatch.v1.json`
- `scripts/prompt_parallel_dispatch.py`
- `Outputs/prompt-parallel-dispatch/manifest.json`

Repository search also found no equivalent `prompt-parallel-dispatch` owner. Creating an ad-hoc manifest would invent a second scheduler and violate current execution-adapter ownership.

**AUTONOMY_GAP:** route a typed prompt/lane dispatch contract to **ASQ-022 / execution-adapter shared-spine** if AgentSwitchboard should own this feature. It must compose with `tooling/harness/execution-adapters/`, prove real overlap in receipts, and must not become a competing FirstMate crew scheduler.

Until that owner exists, `ASB-2026-09-stale-pr-triage-01-panels.md` is the durable machine-ingestible portability/recovery transport.

## 3. COMPACT COORDINATION PREAMBLE

- Repo floor: `main@72d71a74279c5cf1b0c029b68d03c76634d50ea1`; open PRs: **0** at initial salvage-plan refresh.
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
| PR #113 runtime resolution | Windows/OpenCode harness + integration seam | **Salvage first; strong agent** |
| PR #112 Lua embedding | isolated harness spine | **Leaf salvage; safe lower-capability lane** |
| PR #118 external tooling catalog | operational harness leaf + validation | **Leaf salvage; safe lower-capability lane** |
| PR #64 machine-profile harness | Windows profile harness | **Forensic salvage; strong agent; non-main historical base** |
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
  - #113 `opencode-runtime-resolution`: **merge or create only after comparison** with current `opencode-lsp-workstation-setup` and execution-adapter ownership.
  - #92 `execution-actor-routing`: **prefer retire/merge into execution-adapter v1** unless a unique reusable judgment workflow remains.
  - #79 `agent-fleet-readiness`: **split** reusable judgment into skill and deterministic readiness operation into code/registry; no second bootstrap lifecycle.
  - #112 `lua-embedding-integration`: **keep/create as isolated explicit-trigger skill** if the leaf implementation survives proof.
  - #64 old machine-profile changes: **merge into existing machine-profile-bootstrap owner**, never duplicate the canonical skill/launcher.
  - #118 `external-agent-tooling-intake`: **keep only as evidence-intake workflow**; catalog presence never grants install/trust/execution authority.
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
