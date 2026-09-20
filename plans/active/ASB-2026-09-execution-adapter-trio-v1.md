# EXECUTION_ADAPTER_TRIO_V1

**Plan ID:** ASB-2026-09-EXECUTION-ADAPTER-TRIO-V1
**Status:** Active
**Priority:** Critical
**Canonical machine plan:** plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
**Contract:** tooling/harness/execution-adapters/execution-adapter-contract.v1.json

## Mission

Make AgentSwitchboard a real execution broker across three different native harness classes without turning it into an IDE, a prompt taxonomy, or a second crew scheduler. The first trio is local argv, Claude Code, and Cursor CloudAgent.

Prompt Kit remains the semantic owner. AgentSwitchboard chooses and correlates execution adapters. Native harnesses own their process/session/provider mechanics. FirstMate remains the canonical crew/session runtime.

## Fresh evidence floor

The planning branch was cut from main@4685a6db93452880ad091bc47c69791aa0b1dbeb after PR #334. At factoring time the only open AgentSwitchboard PR was #332, P07 Successor: CloudAgent Task-tool binding for Triage dispatch, head 0896bd7861f9ade9a246b3fde2b90925c22ecf0b.

PR #332 owns current Cursor mutation surfaces under tooling/harness/triage-consumer/dispatch/**. Its latest automated-floor run 35480100574 failed on Windows and Ubuntu because test_cloud_agent_orchestration.py contains trailing whitespace. The PR also preserves one observed real Task launch, but its own evidence says the production machine-closed orchestrator is not deployed. Treat those as separate facts.

The repository does not contain scripts/prompt_parallel_dispatch.py. Existing repository doctrine already says not to invent it. This plan uses the canonical AgentSwitchboard public-plan + work-ledger surfaces for coordination.

## Launch order

1. **Panel 01 — EAT-301: Repair PR #332 deterministic floor.** Independent immediate lane; owns #332 only.
2. **Panel 02 — EAT-005: Generic adapter interface + registry.** Shared spine and hard dependency for all new adapter implementations.
3. **Panel 03 — EAT-006: Legacy Triage receipt compatibility bridge.** Starts after EAT-005.
4. **Parallel Group A**
   - **Panel 04 — EAT-101..107: local-argv reference adapter + runtime proof.**
   - **Panel 05 — EAT-201..208: Claude Code adapter + runtime proof.**
   - **Panel 06 — EAT-302..309: Cursor CloudAgent reconciliation + machine-closed runtime proof.**
5. **Panel 07 — EAT-401..407: trio conformance, dispatcher convergence, proof packet, and milestone acceptance.**

Panels 04–06 must use isolated branches/worktrees or equivalent provider-isolated workspaces. Their mutation surfaces are disjoint by adapter. The convergence owner alone edits shared registry/conformance surfaces when integrating them.

## Dependency graph

    Contract floor EAT-001..004 (tracked now)
             |
             v
          EAT-005
         /   |    \
        /    |     \
   local   Claude   Cursor reconciliation
 EAT-101  EAT-201   EAT-302
    |        |         |
 EAT-107  EAT-208   EAT-309
        \     |      /
         \    |     /
          EAT-401
             |
      EAT-402..407

EAT-301 is independent of EAT-005 and should repair #332 as soon as its owner has a writer lane.

## Epic E0 — shared execution-adapter contract

EAT-001 through EAT-004 are the accepted contract floor. EAT-005 implements the executable interface/registry/runner. EAT-006 translates normalized receipts to the legacy Triage lane receipt while downstream migration is incomplete.

The v1 callable boundary is intentionally small:

    probe() -> agentswitchboard.execution-capability-report/v1
    execute(agentswitchboard.execution-request/v1)
        -> agentswitchboard.execution-receipt/v1

Lifecycle interruption, resume, generalized supervision, context rollover, and crew scheduling are not part of v1.

## Epic E1 — local-argv reference adapter

Extract the already-proven subprocess path into the common interface. It is the protected control for later adapters.

Minimum end-to-end gate:
- real child success with known marker and exit 0;
- real child stdout/stderr and exact exit 42;
- bounded hang classified TIMED_OUT;
- cwd, output bounds, identity, and schema-valid receipt verified;
- existing Triage dispatch behavior remains green.

Minimum proof: **LOCAL_RUNTIME_OBSERVED**.

## Epic E2 — Claude Code adapter

Claude Code is the first new native harness implementation. Probe must never open interactive auth. Execution uses a bounded noninteractive native CLI path, explicit working directory, request-governed permission profile, structured result capture, timeout, and normalized receipt.

Minimum end-to-end gate:
- real Claude Code CLI invoked from ASB;
- disposable fixture repository changed only inside allowed scope;
- independent deterministic validator proves the expected postcondition after Claude exits;
- missing binary/auth, timeout, nonzero CLI failure, and malformed structured output fail closed;
- available native session/runtime identity is recorded honestly.

Minimum proof: **CLAUDE_CODE_RUNTIME_OBSERVED**.

## Epic E3 — Cursor CloudAgent adapter

Do not restart #332 from fiction. Repair and preserve it, then migrate useful transport/evidence behind the common adapter contract.

The decisive missing transition is the human orchestration hop. A production-ready v1 Cursor adapter must close:

    ASB request
      -> adapter-private transport
      -> authorized Cursor-native Task bridge
      -> real CloudAgent
      -> machine-observed terminal result
      -> normalized receipt

A socket or metadata endpoint proves transport visibility, not Task dispatch readiness.

Minimum end-to-end gate:
- one ASB dispatch launches a fresh real CloudAgent without operator intervention;
- fresh cloudAgentBcId/provider execution identity captured;
- completion/failure/timeout read back automatically;
- independent deterministic artifact proves the bounded task effect;
- wrong host/API/Task bridge and timeout fail closed.

Minimum proof: **CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED**.

## Epic E4 — trio convergence

After all three adapter lanes prove their own runtime boundary:
- run one common conformance suite;
- replace generic dispatch native-harness branches with registry resolution;
- execute a cross-adapter bounded task fixture;
- preserve three independent runtime receipts/proof identities;
- prove failure isolation;
- document how OpenCode, Codex, Augment, and later harnesses extend the same contract;
- run the milestone acceptance gate.

Milestone closure is **not** “three adapter files exist.” It is: a caller can issue a bounded ASB execution request to any ready trio adapter, receive one normalized terminal receipt, and independently prove that the named native harness performed or correctly refused the work.

## Parallel ownership and collision ledger

| Lane | Owns | Must not touch before convergence |
|---|---|---|
| shared spine | execution-adapters contract/interface/registry/runner + common tests | #332 Cursor legacy files; provider-specific internals |
| PR #332 repair | existing #332 files only | new shared contract or other adapter lanes |
| local argv | adapters/local_argv.py + local fixtures/tests | Claude/Cursor adapter files |
| Claude Code | adapters/claude_code.py + Claude fixtures/tests | local/Cursor adapter files |
| Cursor | adapters/cursor_cloud_agent.py + reconciled #332 transport/tests | local/Claude adapter files; unrelated P67 |
| convergence | registry, shared conformance, generic dispatcher bridge, final docs | unfinished sibling lanes |

Shared schemas are frozen by EAT-001..004. Any lane discovering a necessary schema change stops and routes the proposal to the convergence/shared-contract owner rather than editing the shared schema concurrently.

## Harness factoring

**Keep**
- public-plan-coordination skill as the multi-agent planning/ownership procedure;
- end-to-end-runtime-validation for observed operator/runtime claims;
- existing Triage dispatch receipt as compatibility surface;
- FirstMate crew-runtime ADR;
- automated-test-floor as unattended static regression floor.

**Create now**
- execution-adapter policy;
- request/receipt/capability schemas;
- public-safe fixtures;
- semantic validator and PowerShell entrypoint;
- this public plan and work-ledger index.

**Create in successor implementation waves**
- generic adapter interface/registry/runner;
- local, Claude, and Cursor adapters;
- compatibility translator;
- common conformance suite;
- runtime proof fixtures and evidence packet.

**Do not create**
- another prompt taxonomy;
- another crew scheduler;
- a second public-plan mechanism;
- scripts/prompt_parallel_dispatch.py in this repository;
- a fourth adapter before the trio establishes the extension contract.

No new skill/capability/trigger is required merely to freeze this interface. Deterministic adapter selection belongs in code/registry. A later implementation lane may add a reusable execution capability or deterministic trigger only if the executable registry cannot express the requirement without duplicating routing logic.

## Application-logic factoring

This milestone is harness spine + agent-harness adapter + integration seam + validation + runtime proof. It does not own application UI, persistence/database state, deployment orchestration, business-domain services, or Prompt Kit application semantics.

## Validation order

1. python3 tests/test_execution_adapter_contract.py
2. pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionAdapterContract.ps1
3. python3 tests/test_public_plan_contracts.py
4. pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
5. pwsh -NoLogo -NoProfile -File scripts/Test-RepositoryWorkLedgerContract.ps1
6. pwsh -NoLogo -NoProfile -File scripts/Test-AutomatedTestFloor.ps1
7. git diff --check
8. exact-head hosted checks when a PR is open

Later runtime lanes add their adapter-specific observed gates before claiming the corresponding runtime proof level.

## Evidence state

The contract floor may reach **INTEGRATED CONTRACT_STATIC** after merge. That state deliberately leaves the adapter implementations and runtime proofs as REQUIRED SUCCESSOR WORK. Schema validation, CI, a PR, or merge cannot prove native Claude or Cursor execution.

## Next executable work

- **EAT-301 owner:** PR #332 writer — repair its deterministic whitespace failure and rerun exact-head automated floor.
- **EAT-005 owner:** execution-adapter shared-spine writer — implement the generic adapter interface + registry + runner against the frozen contract.
- Once EAT-005 integrates, create isolated local, Claude, and Cursor writer lanes immediately; do not serialize them merely for convenience.
