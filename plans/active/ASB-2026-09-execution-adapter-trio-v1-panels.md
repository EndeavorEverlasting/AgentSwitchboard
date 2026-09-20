# EXECUTION_ADAPTER_TRIO_V1 — portability fallback panels

These panels are fallback transport only. The canonical machine-readable coordination owner is the public plan JSON. Autonomous dispatch should consume the plan/registry directly when a supported execution adapter is available. Human copy/paste is incidental compatibility, not the primary scheduler.

## Panel 01 — EAT-301 — Repair PR #332 deterministic floor

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE EAT-301 — PR #332 deterministic floor repair
Branch/PR: reuse the refreshed exact owner of PR #332; do not create a competing Cursor-dispatch branch.
Wave/Lane: Wave 0 / cursor-pr332-owner
Hard dependencies: none beyond current PR #332 ownership.
Safe parallel work: PR #335 contract-floor validation; no shared mutation files.
Owned scope: only files already owned by PR #332, especially the deterministic whitespace failure in tooling/harness/triage-consumer/dispatch/test_cloud_agent_orchestration.py.
Forbidden scope: new execution-adapter shared contract paths; local/Claude adapters; architecture rewrite; claiming production machine-closed Cursor dispatch.
Expected artifacts: repaired exact PR #332 head; Windows+Ubuntu automated-floor result; preserved prior real Task-launch evidence.
Mission: repair the current deterministic hygiene failure without changing the proof story or throwing away useful #332 implementation/evidence.
Read first: PR #332 body/diff/checks; reports/P07-successor-cloudagent-binding-evidence.md; tooling/harness/triage-consumer/dispatch/ORCHESTRATION.md; .ai/harness/automated-test-floor.manifest.json.
Compact preflight: record refreshed main, #332 head, failing job IDs/log lines, changed files, sibling PR collision state.
Tasks:
1. Confirm the current #332 failure is still the same whitespace family and no newer owner already repaired it.
2. Remove only the offending whitespace/hygiene defects.
3. Run/obtain git diff --check and the owning dispatch tests.
4. Rerun exact-head automated floor on Windows and Ubuntu.
5. Preserve the distinction: observed real Task launch exists; unattended ASB→Task→terminal receipt remains unproven until EAT-305/308.
Validation order: git diff --check; focused dispatch tests; automated test floor; PR required checks.
Commit/push/PR contract: commit only #332-owned repair to the existing PR branch, push normally, do not merge while any required gate is red.
Proof level: deterministic integration hygiene only.
Proof ceiling: does not establish CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED.
Final response contract: CHANGED; PROVED; exact head/checks; remaining Cursor runtime gap; next EAT task.
Exact next command: refresh the #332 branch and run git diff --check against refreshed main before mutation.
```
## Panel 02 — EAT-005 — Generic adapter interface + registry

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE EAT-005 — generic execution-adapter spine
Branch/PR: create one isolated writer branch from refreshed main after PR #335 is integrated.
Wave/Lane: Wave 1 / shared-spine
Hard dependencies: PR #335 integrated; EAT-001..004 contract floor present on main.
Safe parallel work: EAT-301 on PR #332 remains independent.
Owned scope: tooling/harness/execution-adapters interface/registry/runner modules and focused tests; minimal documentation/index updates required by those files.
Forbidden scope: provider-native local/Claude/Cursor runtime implementation; PR #332 files; Prompt Kit semantics; FirstMate scheduler; P67 OpenCode redesign.
Expected artifacts: adapter protocol/base interface; registry; generic runner; unavailable-adapter fixture/tests; normalized fail-closed receipt.
Mission: make the frozen v1 contract executable without implementing any provider-specific adapter yet.
Read first: execution-adapter-contract.v1.json; three v1 schemas; tests/test_execution_adapter_contract.py; docs/harness/execution-adapter-contract-v1.md; CODEBASE_MAP.md; AGENTS.md.
Compact preflight: prove PR #335 ancestry/content on refreshed main; inspect open PRs and changed-file collisions; name branch/worktree and exact owned files.
Tasks:
1. Implement the smallest adapter interface exposing probe() and execute(request).
2. Implement deterministic adapter registration/resolution.
3. Implement generic runner: resolve → probe → execute only when READY; otherwise normalized BLOCKED receipt.
4. Reject duplicate adapter kinds and unknown adapters fail closed.
5. Add focused positive/negative tests and register only the owning validation surface needed.
Validation order: Test-ExecutionAdapterContract; focused new tests; automated floor; git diff --check.
Commit/push/PR contract: one bounded branch/PR; no runtime claims; integrate when exact-head required gates are green.
Proof level: IMPLEMENTED + static/harness validation.
Proof ceiling: no native adapter runtime proof.
Final response contract: files; tests; exact commit/PR/main containment if merged; blockers; next dependency-ready lanes.
Exact next command: pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionAdapterContract.ps1
```
## Panel 03 — EAT-006 — Legacy Triage receipt bridge

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE EAT-006 — legacy Triage receipt compatibility bridge
Branch/PR: isolated writer based on refreshed main containing EAT-005.
Wave/Lane: Wave 1 / shared-spine compatibility
Hard dependencies: EAT-003 and EAT-005 integrated.
Safe parallel work: EAT-301; adapter-specific lanes may prepare read-only evidence but must not assume bridge completion.
Owned scope: execution-adapter compatibility translator + focused tests; legacy schema is read-only unless a proven incompatibility requires shared-owner reconciliation.
Forbidden scope: rewriting Triage semantic mapping; changing Prompt Kit contracts; Cursor #332 implementation; provider execution.
Expected artifacts: execution-receipt/v1 → legacy dispatch-receipt/v1 translator; positive/negative compatibility tests.
Mission: let existing Triage consumers continue operating while native execution moves behind the generic adapter layer.
Read first: execution-receipt.v1.schema.json; tooling/harness/triage-consumer/dispatch/schemas/dispatch-receipt.schema.json; dispatch_lanes.py; EAT-005 registry/runner.
Compact preflight: prove EAT-005 on main; inspect legacy receipt consumers/tests; identify exact translation fields and proof-loss hazards.
Tasks:
1. Define deterministic translation rules for terminal states, identity, artifacts, exit code, blocker, and bounded output.
2. Implement translator without raising proof level.
3. Reject impossible/ambiguous mappings fail closed.
4. Add compatibility fixtures and tests.
5. Prove current Triage receipt consumers still parse translated output.
Validation order: execution-adapter focused tests; Triage dispatch/consumer validators; automated floor; git diff --check.
Commit/push/PR contract: bounded compatibility PR; integrate only green exact-head.
Proof level: compatibility harness proof.
Proof ceiling: no native runtime proof.
Final response contract: mapping table; tests; integration state; unresolved migration gaps; next local/Claude/Cursor lanes.
Exact next command: run the execution-adapter contract validator, then inspect the legacy receipt schema and dispatcher consumers.
```
## Panel 04 — EAT-101..107 — local-argv reference adapter

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE local-argv adapter epic EAT-101..107
Branch/PR: isolated local-argv writer from refreshed main after EAT-005; EAT-006 required before final EAT-107.
Wave/Lane: Parallel Group A / local-argv-lane
Hard dependencies: EAT-005 for implementation; EAT-006 for final legacy regression gate.
Safe parallel work: Claude Code lane and Cursor lane on separate files/workspaces.
Owned scope: tooling/harness/execution-adapters/adapters/local_argv.py; local fixtures/tests; adapter-specific runtime proof artifacts outside tracked source unless deliberately minimized.
Forbidden scope: Claude/Cursor adapter files; shared schemas without convergence approval; PR #332; Prompt Kit/FirstMate semantics.
Expected artifacts: extracted local adapter; probe; bounded execution; success/exit-42/timeout tests; legacy regression proof.
Mission: make the already-working subprocess path the reference implementation of the common adapter contract.
Read first: current dispatch_lanes.py local argv implementation; v1 contract/schemas; EAT-005 runner/registry; legacy bridge when available.
Compact preflight: prove EAT-005 current; inspect exact local behavior to preserve; allocate isolated temp roots; record platform assumptions.
Tasks:
1. EAT-101 extract subprocess mechanics without shell=True.
2. EAT-102 add executable/cwd capability probe.
3. EAT-103 enforce timeout and output bounds.
4. EAT-104 run a real success fixture with expected marker and exit 0.
5. EAT-105 run a real failure fixture and preserve exact exit 42/stdout/stderr.
6. EAT-106 prove bounded hang becomes TIMED_OUT.
7. EAT-107 rerun legacy Triage protected controls through the bridge.
Validation order: focused local tests; independent fixture validators; Triage dispatch tests; common conformance subset; automated floor; git diff --check.
Commit/push/PR contract: adapter-only branch/PR; integrate after exact-head green; preserve untracked runtime evidence identity in report without committing private paths.
Proof level target: LOCAL_RUNTIME_OBSERVED.
Proof ceiling: local process only; no Claude/Cursor/provider claim.
Final response contract: observed commands/effects/receipts; exact proof ceiling; integration state; protected-control result.
Exact next command: run the execution-adapter contract validator from the isolated local-argv worktree before editing.
```
## Panel 05 — EAT-201..208 — Claude Code adapter

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE Claude Code adapter epic EAT-201..208
Branch/PR: isolated Claude writer from refreshed main after EAT-005.
Wave/Lane: Parallel Group A / claude-code-lane
Hard dependencies: EAT-005 integrated; EAT-107 required only for final cross-adapter protected-control closeout.
Safe parallel work: local-argv and Cursor lanes on separate files/workspaces.
Owned scope: tooling/harness/execution-adapters/adapters/claude_code.py; Claude fixtures/tests; disposable public-safe fixture repo/tree; Claude-specific docs.
Forbidden scope: local/Cursor adapter files; shared schemas without shared-owner reconciliation; interactive login automation; global Claude config mutation; Prompt Kit semantic selection.
Expected artifacts: capability probe; request→CLI mapping; permission profiles; structured parser; negative fixtures; disposable E2E fixture + independent validator; runtime receipt.
Mission: add the first new native CLI harness behind the common adapter boundary.
Read first: v1 contract/schemas; EAT-005 interface/registry; CLAUDE.md for repo-local operating discipline; current Claude CLI help/version in the authorized runtime before hard-coding flags.
Compact preflight: refresh provider/runtime truth; record actual Claude binary/version/help capabilities/auth state without exposing credentials; allocate disposable repo.
Tasks:
1. EAT-201 implement read-only capability probe with no interactive login.
2. EAT-202 map generic request to bounded noninteractive CLI invocation.
3. EAT-203 implement READ_ONLY/REPO_EDIT/VALIDATION permission profiles.
4. EAT-204 parse structured output to normalized receipt.
5. EAT-205 prove binary/auth/nonzero/timeout/malformed-output negative paths.
6. EAT-206 build disposable fixture + independent validator.
7. EAT-207 run real Claude E2E and independently validate postcondition.
8. EAT-208 rerun local protected controls.
Validation order: probe tests; parser/negative tests; fixture validator; real E2E only in authorized authenticated environment; local protected control; automated floor; git diff --check.
Commit/push/PR contract: never commit credentials/transcripts/private receipts; merge only exact-head green and after required observed runtime gate is honestly evidenced.
Proof level target: CLAUDE_CODE_RUNTIME_OBSERVED.
Proof ceiling: Claude Code native runtime only; no Cursor/crew/provider-general claim.
Final response contract: native identity/version; exact invocation class (not secrets); independent validation; receipt; failures; integration state.
Exact next command: from the isolated lane, run the contract validator and a read-only Claude version/help probe before implementing mappings.
```
## Panel 06 — EAT-302..309 — Cursor CloudAgent adapter

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE Cursor CloudAgent adapter epic EAT-302..309
Branch/PR: create isolated Cursor adapter writer only after EAT-005; consume/reconcile refreshed PR #332 after EAT-301, never overwrite it blindly.
Wave/Lane: Parallel Group A / cursor-cloud-agent-lane
Hard dependencies: EAT-005 and EAT-301; EAT-208 required for final cross-adapter control EAT-309.
Safe parallel work: local-argv and Claude lanes on separate files/workspaces.
Owned scope: tooling/harness/execution-adapters/adapters/cursor_cloud_agent.py; reconciled adapter-private transport/observer/tests; minimal #332 salvage after explicit comparison.
Forbidden scope: silent rewrite of #332 history; local/Claude files; P67 OpenCode; shared schema mutation without reconciliation; human-operated Task hop presented as production automation.
Expected artifacts: #332 reuse map; capability probe; private transport; machine-closed Task bridge; terminal observer; negative tests; real E2E receipt.
Mission: turn the useful #332 transport and Task evidence into an unattended common-contract Cursor adapter.
Read first: PR #332 exact diff/checks/evidence; #331 fail-closed probe history; v1 contract/schemas; EAT-005 registry; FirstMate boundary ADR.
Compact preflight: refresh main and #332; prove EAT-301 result; compare #332 changed files to target adapter surface; identify Task capability actually callable by the active runtime.
Tasks:
1. EAT-302 reconcile/preserve #332 implementation and evidence.
2. EAT-303 separate HOST_READY, TRANSPORT_READY, and TASK_DISPATCH_READY.
3. EAT-304 move request/result transport behind adapter-private implementation.
4. EAT-305 remove the human orchestration hop using an actually available Cursor-native Task bridge; otherwise return precise BLOCKED_API.
5. EAT-306 machine-observe terminal result and stable execution identity.
6. EAT-307 prove wrong-host/API/bridge/failure/timeout paths.
7. EAT-308 execute one real ASB→Task→fresh CloudAgent→terminal-result→independent-artifact path with no human bridge.
8. EAT-309 rerun local and Claude protected controls.
Validation order: common contract; #332 focused tests; adapter negative tests; real Cursor E2E in authorized Task-capable environment; cross-adapter controls; automated floor; git diff --check.
Commit/push/PR contract: preserve #332 unique work; one isolated migration PR; no runtime PASS from mocks; merge only exact-head green.
Proof level target: CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED.
Proof ceiling: one Cursor execution plane; no FirstMate crew or universal provider claim.
Final response contract: #332 disposition; Task bridge identity; fresh cloudAgentBcId; independent artifact; receipt; blocked paths; integration state.
Exact next command: refresh #332 and main, prove EAT-301 green, then compare its changed files against the new adapter contract before writing.
```
## Panel 07 — EAT-401..407 — trio convergence

```text
Repository: EndeavorEverlasting/AgentSwitchboard
Local path: resolve the active isolated checkout/worktree; do not guess or reuse another writer's workspace.
Safety: refresh remote/default-branch truth first; preserve unrelated work; no force reset/push; no secrets/private runtime receipts; no proof promotion.
Durable authority: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
Contract authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json

Banner: EXECUTE EAT-401..407 — adapter trio convergence
Branch/PR: dedicated convergence worktree/branch from refreshed main after local EAT-107, Claude EAT-208, and Cursor EAT-309 are integrated or available as proven dependency branches.
Wave/Lane: Final convergence / convergence-owner
Hard dependencies: EAT-107, EAT-208, EAT-309.
Safe parallel work: documentation EAT-406 may be prepared after EAT-402 if it does not share uncommitted files.
Owned scope: shared adapter registry/conformance suite; generic dispatcher bridge; cross-adapter fixture; final proof packet; extension docs; milestone/ledger status updates.
Forbidden scope: rewriting provider-specific adapters outside necessary integration fixes; adding a fourth runtime adapter; weakening proof levels; deleting legacy compatibility before consumers migrate.
Expected artifacts: common conformance suite; registry-based generic dispatch; cross-adapter fixture; three-plane proof packet; failure-isolation proof; extension contract; final acceptance report.
Mission: prove the abstraction is real across local process, local/native agent CLI, and remote/cloud agent execution planes, then converge it safely.
Read first: canonical plan and contract; all three adapter PRs/commits/runtime receipts; legacy bridge; generic runner/registry; owning validators.
Compact preflight: refresh main and dependency branches; prove required commits/contents/validators; create dedicated convergence worktree; record proof-relevance fingerprint.
Tasks:
1. EAT-401 run common probe/request/receipt/blocker/timeout conformance against all three.
2. EAT-402 replace generic dispatch native-harness branching with registry resolution.
3. EAT-403 execute equivalent bounded fixture contract through compatible adapters.
4. EAT-404 assemble independently attributable three-plane observed proof.
5. EAT-405 intentionally block one adapter and prove failure isolation.
6. EAT-406 document fourth-adapter extension rules for OpenCode/Codex/Augment without implementing them.
7. EAT-407 run exact-candidate milestone acceptance and update durable state.
Validation order: common conformance; provider-specific protected controls; Triage compatibility; repository required gates; exact-candidate diff hygiene; integration containment proof.
Commit/push/PR contract: convergence owner only; integrate dependency commits in order; preserve sibling unique work; merge only when exact candidate is green and runtime proof identities remain valid.
Proof level target: EXECUTION_ADAPTER_TRIO_V1 accepted with three independently observed adapter proof levels.
Proof ceiling: no deployment/production/user-acceptance claim beyond the observed authorized environments.
Final response contract: three proof identities; conformance/failure isolation; files; checks; merge/main containment; deferred adapters; contract horizon.
Exact next command: refresh main and prove EAT-107/EAT-208/EAT-309 dependency containment before creating the convergence candidate.
```
