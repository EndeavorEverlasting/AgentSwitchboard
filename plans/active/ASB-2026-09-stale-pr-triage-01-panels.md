# TRIAGE-01 Portability Sprint Panels

> Progress checkpoint: current execution floor `main@dd344b339ffc9fa2d417a785f6b17d493fcb2659`. Panels 01/#113 and 02/#112 are integrated; do not relaunch them. Remaining dependency-ready Wave 1 panels are 03/#118 and 04/#64.

## Panel 01 — PR #113 OpenCode runtime-resolution semantic salvage — COMPLETED / DO NOT RELAUNCH

```text
BANNER: HARD SALVAGE / STRONG AGENT REQUIRED
Repo: EndeavorEverlasting/AgentSwitchboard
Planned floor: main@72d71a74279c5cf1b0c029b68d03c76634d50ea1
Historical source: PR #113, feat/harness-opencode-runtime-resolution-20260809@2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9
Wave: 1
Lane: OpenCode / Windows-profile runtime-resolution
Hard dependencies: PR #94 core salvage integrated via #338; refresh main before mutation.
Safe parallel work: Panels 02, 03, 04 in separate worktrees.
Owned mutation: a new isolated salvage branch; still-unique runtime-resolution leaf code/contracts/tests/docs after comparison.
Forbidden: wholesale old SKILLS/TRIGGERS/CODEBASE_MAP/workflow replay; P67 rewrite; OpenCode LSP rewrite; execution-adapter v1 rewrite; live provider login.
Expected artifacts: file-level preserve/merge/retire matrix; bounded implementation; focused negative/positive tests; exact-head proof.
REPOSITORY LAW
- Read AGENTS.md first, then the nearest triggered owners. Current repository/provider truth outranks this panel if the floor moved.
- Historical source branch is evidence, not an integration target. Never merge or cherry-pick the branch wholesale.
- Preserve unrelated dirty work. Use an isolated worktree + dedicated branch from refreshed origin/main.
- Worker lane must not edit SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md, plans/, .ai/WORK_QUEUE.md, or shared operational registries unless this panel explicitly grants that file.
- Reuse current contracts and names. If the historical concept is already owned by a modern subsystem, merge its missing invariant there or retire it.
- Static/synthetic PASS never proves live runtime.

MISSION
Recover what PR #113 uniquely knew about OpenCode runtime/path resolution, reconcile it against current opencode-lsp-setup, P67 evaluation adapter, and execution-adapter v1, then implement only the missing current-owner behavior.

READ FIRST
AGENTS.md
plans/active/ASB-2026-09-stale-pr-triage-01.plan.json
tooling/harness/operational/opencode-lsp-setup/
tooling/harness/execution-adapters/
plans/active/ASB-2026-09-p67-opencode-evaluation-adapter.plan.json
historical PR #113 diff and its focused tests/validator

COMPACT PREFLIGHT
Refresh origin/main; verify source SHA exactly; inspect status/worktrees/open PRs; prove no active writer owns intended files; compare current-main equivalents before writing.

TASKS
1. Inventory all 23 PR files and classify PRESERVE / MERGE-INTO-CURRENT-OWNER / RETIRE / ALREADY-CONTAINED.
2. Identify the smallest runtime-resolution invariants absent on main: native-vs-WSL declaration, path collision/shim shadowing, target existence, state drift, report shape.
3. Do not create a second OpenCode lifecycle owner. Put deterministic resolution/readback in current canonical code or one leaf subsystem only.
4. Add negative fixtures for stale/shadowed/missing target cases and positive native/declared-WSL controls.
5. If an adapted skill remains necessary, give deterministic trigger, inputs/outputs, guardrails, owner, focused test, and proof ceiling; otherwise route through current OpenCode skill.
6. Run focused validators, then current OpenCode LSP / execution-adapter regression, automated floor, diff hygiene.
7. Commit/push/open PR. Do not merge until exact-head checks/review are green and main is refreshed.

VALIDATION ORDER
historical focused validator if safely executable -> new focused tests -> current OpenCode LSP validator -> execution-adapter contract validator -> automated floor -> git diff --check.

PROOF
Target: integrated current-owner semantic salvage.
Ceiling: static/synthetic repository proof; Windows/OpenCode live behavior requires separate authorized runtime observation.

FINAL RESPONSE CONTRACT
Report source SHA; current base SHA; preserve/merge/retire matrix; files changed; tests/validators and exact results; review repairs; commit/PR/integration state; gaps; proof ceiling; final git status; next command.

NEXT COMMAND
none; completed by PR #341 / merge 7e637307de01116069b4067b351b96188d12e989
```

## Panel 02 — PR #112 Lua embedding leaf salvage — COMPLETED / DO NOT RELAUNCH

```text
BANNER: LEAF SALVAGE / SUITABLE FOR BOUNDED LOWER-CAPABILITY AGENT
Repo: EndeavorEverlasting/AgentSwitchboard
Planned floor: main@72d71a74279c5cf1b0c029b68d03c76634d50ea1
Historical source: PR #112, feat/harness-lua-embedding-20260809@3053e1898c1de351faf2215d72947f5bd5d880de
Wave: 1
Lane: isolated Lua harness
Dependencies: #94 floor only.
Safe parallel work: Panels 01, 03, 04.
Owned mutation: tooling/lua/**, focused Lua tests, focused Lua docs.
Forbidden: shared SKILLS.md/TRIGGERS.md/CODEBASE_MAP.md; global registries; unrelated runtime.
Expected artifacts: isolated Lua contract/manifest/schema/fixtures/workflows/status reader; focused test proof; convergence wiring note.
REPOSITORY LAW
- Read AGENTS.md first, then the nearest triggered owners. Current repository/provider truth outranks this panel if the floor moved.
- Historical source branch is evidence, not an integration target. Never merge or cherry-pick the branch wholesale.
- Preserve unrelated dirty work. Use an isolated worktree + dedicated branch from refreshed origin/main.
- Worker lane must not edit SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md, plans/, .ai/WORK_QUEUE.md, or shared operational registries unless this panel explicitly grants that file.
- Reuse current contracts and names. If the historical concept is already owned by a modern subsystem, merge its missing invariant there or retire it.
- Static/synthetic PASS never proves live runtime.

MISSION
Port the self-contained Lua embedding harness only if its contract still makes sense on current main. Keep sandbox safety explicit and leave shared routing/wiring to Panel 07.

READ FIRST
AGENTS.md
plans/active/ASB-2026-09-stale-pr-triage-01.plan.json
historical PR #112 diff
historical tests/test_lua_harness_contracts.py and scripts/Test-LuaHarnessCompleteness.ps1
current harness doctrine

TASKS
1. Verify tooling/lua remains absent on current main.
2. Reconstruct the leaf without copying shared docs/routing files.
3. Preserve positive sandbox-safe and negative unsafe-OS-access fixtures.
4. Make every registry/schema closed and internally consistent.
5. Ensure status tooling is read-only; no claim that a Lua runtime/embedder is installed or exercised.
6. Run focused tests/validator + automated floor + diff hygiene.
7. Commit/push/open PR; hand shared skill/trigger/map wiring to Panel 07.

PROOF CEILING
Static/synthetic Lua harness contract only; no embedded Lua runtime proof.

FINAL RESPONSE CONTRACT
Exact source/base; changed files; focused validation; skipped runtime checks; commit/PR state; requested convergence wiring; final status; next command.

NEXT COMMAND
none; completed by PR #342 / merge 31d57167330e85fb7b8fc52ab47ceef348771b04 with post-merge review recovery PR #343 / merge dd344b339ffc9fa2d417a785f6b17d493fcb2659
```

## Panel 03 — PR #118 external-agent tooling leaf salvage

```text
STATUS: DONE / INTEGRATED
Repo: EndeavorEverlasting/AgentSwitchboard
Historical source: PR #118 @ 87abb4546ee1ef440897dfd86a49e58dab827ee6
Delivery: salvage/pr118-external-tooling-20260922 / PR #345
Final validated head: a065fe0e7a0ca9a9f85462a63262fe0943b37cb5
Integrated main slice: 170da052de065e584baa07bce35ccba8d06eebf6
Proof: merge tree identical; External Agent Tooling Catalog #4 and automated floor #257 green; source-only boundary/schema validation retained.
Disposition: do not relaunch. Shared registration remains convergence-owned.
NEXT COMMAND
none; completed by PR #345 / merge 170da052de065e584baa07bce35ccba8d06eebf6
```

## Panel 04 — PR #64 Windows machine-profile forensic salvage

```text
STATUS: DONE / INTEGRATED
Repo: EndeavorEverlasting/AgentSwitchboard
Historical source: PR #64 @ 45b44b158d7f44e18dfbc6c24120a0c02924f48b
Historical base: eb91efa9674c0361925905ee6145fd7434190f53
Delivery: salvage/pr64-machine-profile-20260924 / PR #348
Final validated head: 9fbad5db784c25a3aa369cfadb3ef5b97ff43193
Integrated main slice: 212e2cf3fb31b675fda7205b01f8760046371818
Proof: intended delta reconstructed as 22 commits / 20 files; lean preserve/merge/retire matrix tracked; Machine profile operational harness #1, existing bootstrap #259, automated floor #265 green; merge tree identical.
Disposition: current detector/path/launcher ownership preserved; stale Desktop default, candidate wrappers, hook, duplicate skill, and standalone manifest retired.
NEXT COMMAND
none; completed by PR #348 / merge 212e2cf3fb31b675fda7205b01f8760046371818
```

## Panel 05 — PR #92 execution-actor routing reconciliation

```text
BANNER: HARD RECONCILIATION / STRONG AGENT REQUIRED
Repo: EndeavorEverlasting/AgentSwitchboard
Historical source: PR #92, feat/harness-execution-actor-routing-20260808@acc652d5dc7599b18d76983fb96dbd628d2bd759
Wave: 2
Lane: execution-adapter semantic reconciliation
Hard dependencies: PR #118 dependency SATISFIED by PR #345 / 170da052de065e584baa07bce35ccba8d06eebf6. BLOCKED on ASQ-022 ownership until the execution-adapter program is terminal or durably hands off disjoint paths.
Safe parallel work: Panel 06 may proceed independently; this lane must not mutate execution-adapter paths yet.
Owned mutation: missing invariants/tests inside current execution-adapter owner, or one justified leaf seam.
Forbidden: restoring old router as competing lifecycle owner; wholesale operational registry edits; HARNESS.md rewrite.
Expected artifacts: old-vs-current contract matrix; preserve/retire decision; focused regression.
REPOSITORY LAW
- Read AGENTS.md first, then the nearest triggered owners. Current repository/provider truth outranks this panel if the floor moved.
- Historical source branch is evidence, not an integration target. Never merge or cherry-pick the branch wholesale.
- Preserve unrelated dirty work. Use an isolated worktree + dedicated branch from refreshed origin/main.
- Worker lane must not edit SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md, plans/, .ai/WORK_QUEUE.md, or shared operational registries unless this panel explicitly grants that file.
- Reuse current contracts and names. If the historical concept is already owned by a modern subsystem, merge its missing invariant there or retire it.
- Static/synthetic PASS never proves live runtime.

MISSION
Determine whether PR #92 is now superseded by execution-adapter v1. Preserve only semantics the current adapter protocol/registry/runner does not already enforce.

READ FIRST
AGENTS.md
plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json
.ai/WORK_QUEUE.md ASQ-022
tooling/harness/execution-adapters/
historical PR #92 actor-binding schema, router, tests, workflows

TASKS
1. Read `.ai/WORK_QUEUE.md` and fail closed while ASQ-022 remains CLAIMED or otherwise owns the execution-adapter files this lane would change; proceed only after terminal state or explicit ownership handoff is durable.
2. Compare actor identity/binding/verification invariants against current request/receipt/capability contracts.
3. Prefer RETIRE when current adapter v1 already owns a behavior.
4. Convert any missing invariant into the smallest current-owner schema/test/runner repair; do not create a second scheduler/router.
5. Preserve negative mutation fixtures for actor mismatch, unavailable adapter, unauthorized writer, or stale binding when applicable.
6. Reconcile any needed operational registration through Panel 07, not directly here.
7. Run execution-adapter contract tests, focused regression, automated floor, diff hygiene.
8. Commit/push/open PR only if net-new current-owner value remains; otherwise produce a proved retire/no-change disposition.

PROOF CEILING
Static/synthetic adapter contract proof; no provider dispatch or crew-runtime proof.

FINAL RESPONSE CONTRACT
Comparison matrix; implemented or retire verdict with evidence; files/tests; commit/PR if changed; proof ceiling; final status; next command.

NEXT COMMAND
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$true; $root=(git rev-parse --show-toplevel).Trim(); Set-Location $root; git fetch --all --prune --tags; git merge-base --is-ancestor dd344b339ffc9fa2d417a785f6b17d493fcb2659 origin/main; $src=(git rev-parse origin/feat/harness-execution-actor-routing-20260808).Trim(); if($src -ne 'acc652d5dc7599b18d76983fb96dbd628d2bd759'){throw "source moved: $src"}; $pathContract=Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/canonical-path.contract.json') -Raw | ConvertFrom-Json; $wtTemplate=$pathContract.currentBindings.windowsTechnicianProfile.temporaryWorktreeRoot; if(-not $wtTemplate -or -not $env:LOCALAPPDATA){throw 'temporaryWorktreeRoot is not resolvable for this profile'}; $wtRoot=[Environment]::ExpandEnvironmentVariables($wtTemplate); New-Item -ItemType Directory -Path $wtRoot -Force | Out-Null; $wt=Join-Path $wtRoot 'pr92-execution-actor-20260922'; if(Test-Path $wt){throw "worktree exists: $wt"}; if((git branch --list 'salvage/pr92-execution-actor-20260922').Trim()){throw "local branch already exists: salvage/pr92-execution-actor-20260922"}; git worktree add -b salvage/pr92-execution-actor-20260922 $wt origin/main
```

## Panel 06 — PR #79 agent-fleet readiness reconciliation

```text
BANNER: HARD RECONCILIATION / STRONG AGENT REQUIRED
Repo: EndeavorEverlasting/AgentSwitchboard
Current execution floor: main@212e2cf3fb31b675fda7205b01f8760046371818
STATUS: READY / NEXT EXECUTABLE LANE
Historical source: PR #79, feat/harness-agent-fleet-readiness-20260807@b3560cd56e98f7b91dfff2e060c8a27d1c76e76a
Wave: 2
Lane: Windows fleet-readiness
Hard dependency: SATISFIED — Panel 04 / PR #348 merged as 212e2cf3fb31b675fda7205b01f8760046371818.
Safe parallel work: none inside TRIAGE-01; Panel 05 is ownership-blocked.
Owned mutation: unique readiness leaf behavior/tests after current-owner comparison.
Forbidden: duplicate machine-profile/bootstrap/launcher lifecycle; shared CODEBASE_MAP; provider install/login.
Expected artifacts: readiness semantic matrix; leaf implementation if justified; focused fixtures/tests.
REPOSITORY LAW
- Read AGENTS.md first, then the nearest triggered owners. Current repository/provider truth outranks this panel if the floor moved.
- Historical source branch is evidence, not an integration target. Never merge or cherry-pick the branch wholesale.
- Preserve unrelated dirty work. Use an isolated worktree + dedicated branch from refreshed origin/main.
- Worker lane must not edit SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md, plans/, .ai/WORK_QUEUE.md, or shared operational registries unless this panel explicitly grants that file.
- Reuse current contracts and names. If the historical concept is already owned by a modern subsystem, merge its missing invariant there or retire it.
- Static/synthetic PASS never proves live runtime.

MISSION
Recover any useful fleet-readiness semantics without reviving old CMD-shim lifecycle ownership or competing with current machine-profile/bootstrap contracts.

READ FIRST
AGENTS.md
current machine-profile/bootstrap and Windows profile contracts after Panel 04
historical PR #79 tests/fixtures/workflows
current execution-adapter capability/readiness model where relevant

TASKS
1. Compare readiness states/workflows with current machine profile, launcher, and adapter capability semantics.
2. Split judgment from operation: reusable routing guidance may be a skill; readiness calculation must be deterministic code/registry.
3. Reuse canonical launchers; never generate independent lifecycle/fallback logic in CMD shims.
4. Preserve only missing readiness states, failure classifications, handoff/pick-up semantics, or fixtures.
5. Run focused readiness tests, machine-profile/bootstrap, Windows profile launch-mode, automated floor, diff hygiene.
6. Commit/push/open PR only if unique behavior remains.

PROOF CEILING
Static/synthetic readiness proof; no actual fleet/provider/workstation readiness observation.

FINAL RESPONSE CONTRACT
Comparison; preserved/retired semantics; files/tests; commit/PR or no-change proof; proof ceiling; final status; next command.

NEXT COMMAND
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$true; $root=(git rev-parse --show-toplevel).Trim(); Set-Location $root; git fetch --all --prune --tags; git merge-base --is-ancestor dd344b339ffc9fa2d417a785f6b17d493fcb2659 origin/main; $src=(git rev-parse origin/feat/harness-agent-fleet-readiness-20260807).Trim(); if($src -ne 'b3560cd56e98f7b91dfff2e060c8a27d1c76e76a'){throw "source moved: $src"}; $pathContract=Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/canonical-path.contract.json') -Raw | ConvertFrom-Json; $wtTemplate=$pathContract.currentBindings.windowsTechnicianProfile.temporaryWorktreeRoot; if(-not $wtTemplate -or -not $env:LOCALAPPDATA){throw 'temporaryWorktreeRoot is not resolvable for this profile'}; $wtRoot=[Environment]::ExpandEnvironmentVariables($wtTemplate); New-Item -ItemType Directory -Path $wtRoot -Force | Out-Null; $wt=Join-Path $wtRoot 'pr79-fleet-readiness-20260922'; if(Test-Path $wt){throw "worktree exists: $wt"}; if((git branch --list 'salvage/pr79-fleet-readiness-20260922').Trim()){throw "local branch already exists: salvage/pr79-fleet-readiness-20260922"}; git worktree add -b salvage/pr79-fleet-readiness-20260922 $wt origin/main
```

## Panel 07 — Final convergence and cleanup

```text
BANNER: SINGLE-WRITER CONVERGENCE
Repo: EndeavorEverlasting/AgentSwitchboard
Wave: final
Lane: stale-PR semantic-salvage convergence
Dependencies: Panels 01-06 each integrated, blocked with exact gate, or proved no-change/retire.
Owned mutation: shared SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md only when required; shared registries; TRIAGE-01 plan; ASQ-023 ledger; convergence branch.
Forbidden: overwriting unfinished worker branches; deleting source branches before preservation proof; weakening gates; unrelated features.
Expected artifacts: dependency-ordered integrated candidate; shared wiring once; combined proof; durable terminal dispositions.
REPOSITORY LAW
- Read AGENTS.md first, then the nearest triggered owners. Current repository/provider truth outranks this panel if the floor moved.
- Historical source branch is evidence, not an integration target. Never merge or cherry-pick the branch wholesale.
- Preserve unrelated dirty work. Use an isolated worktree + dedicated branch from refreshed origin/main.
- Worker lane must not edit SKILLS.md, TRIGGERS.md, CODEBASE_MAP.md, HARNESS.md, plans/, .ai/WORK_QUEUE.md, or shared operational registries unless this panel explicitly grants that file.
- Reuse current contracts and names. If the historical concept is already owned by a modern subsystem, merge its missing invariant there or retire it.
- Static/synthetic PASS never proves live runtime.

MISSION
Rejoin all salvage lanes on refreshed main, integrate in dependency order, write shared routing/registry surfaces exactly once, prove combined behavior, then update the canonical plan/ledger so future agents do not need this chat.

READ FIRST
AGENTS.md
TRIAGE-01 plan + panel pack
.ai/WORK_QUEUE.md ASQ-023 and ASQ-022
all worker PRs/commits/review state
current shared SKILLS/TRIGGERS/CODEBASE_MAP/HARNESS/registries
automated floor and merge-gate owners

TASKS
1. Refresh main and verify every worker candidate exact head and integration/no-change state.
2. Integrate dependency order: leaf #112/#118 and #113/#64 candidates as gates allow; then #92 after #118 and #79 after #64.
3. Revalidate downstream candidates when proof-relevant bases move.
4. Apply shared skill/trigger/map/registry wiring once, using current owner semantics.
5. Run each focused validator plus public-plan, work-ledger, agent-doc, automated floor, local merge-gate where executable, and diff hygiene.
6. Merge only exact validated heads with no blocking review/conflict/protection gate.
7. Refresh main and prove containment/content. Update TRIAGE-01 + ASQ-023 with integrated SHAs, residual #94 forensic disposition, remaining branch-preservation status, and next real gap.
8. Delete/prune historical branches only under separate explicit cleanup authority after proving no unique unmerged commits/artifacts are still required.

PROOF CEILING
Integrated repository proof. Runtime/live/provider/user acceptance remain separate unless independently observed by the canonical runtime owner.

FINAL RESPONSE CONTRACT
Completed/Proven; remaining gaps; risks; blockers; proof ceiling; integration state with pre/post main SHA and containment; exact changed files/artifacts; validator/check results; skipped checks; preserved branches; final git status; next command.

NEXT COMMAND
$ErrorActionPreference='Stop'; $PSNativeCommandUseErrorActionPreference=$true; $root=(git rev-parse --show-toplevel).Trim(); Set-Location $root; git fetch --all --prune --tags; pwsh -NoLogo -NoProfile -File scripts/Get-RepositoryWorkLedgerFrontier.ps1 -Json; if($LASTEXITCODE){exit $LASTEXITCODE}; git status --short
```
