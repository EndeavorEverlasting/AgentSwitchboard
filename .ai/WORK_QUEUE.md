portableContractRef: RepoLedgerInteroperability.v1@429237aa41d8712d71859865c9be407ca23d8580
localProfileRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# AgentSwitchboard shared work ledger

This is the canonical coordination ledger for unfinished AgentSwitchboard repository work. It routes work; it does not replace `AGENTS.md`, source code, plans, validators, PRs, CI, or runtime evidence. BlacksmithGuild owns the portable ledger compatibility contract; AgentSwitchboard owns this local queue and execution profile. Read `docs/governance/repository-work-ledger-contract.md` before changing ledger semantics.

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Work class is required by the AgentSwitchboard local execution profile.
Use `pwsh -NoLogo -NoProfile -File scripts/Get-RepositoryWorkLedgerFrontier.ps1 -Json` to select the compact actionable frontier instead of rereading the full ledger.
Canonical terminal action: none; no safe actionable work remains

## ASQ-001 — Initial repository work ledger adoption

- **Status:** DONE
- **Priority:** P1
- **Work class:** UNBOUNDED
- **Owner:** chatgpt-cross-repo-ledger-20260809
- **Branch / PR:** main / #105 merged
- **Scope:** historically factor the portable AxTask queue insight into AgentSwitchboard, create the local ledger/validator/CI, and provide a bounded triage consumer adoption; the original family-level portable-authority claim is superseded by BlacksmithGuild RepoLedgerInteroperability.v1
- **Forbidden:** changing AxTask domain behavior; copying AxTask recovery/deployment tasks; product feature changes; implicit AgentSwitchboard hook installation; claiming runtime proof from ledger metadata
- **Dependencies:** none
- **References:** `AGENTS.md`, `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`
- **Acceptance gate:** historical implementation merged with AgentSwitchboard local ledger, validator, negative/positive tests, CI, and triage local adoption; portable authority is separately reconciled by ASQ-003
- **Gate:** none
- **Last proof:** workflow:31331594284 passed the final AgentSwitchboard repository-work-ledger contract head; merge:62acecf4a590ecadf4a0b1ad1410e659b4e1b650 merged AgentSwitchboard PR #105; merge:189be37114ef2eb11015b0d962eb23e5d12f1ccc merged triage adoption PR #160; merge:07b960fa35b61f4b9be6190b16bf0c21a6e06678 merged triage strict-DONE closeout
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-08-09T19:46:00Z

## ASQ-002 — Add bounded execution classes and compact frontier routing

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** chatgpt-ledger-execution-frontier-20260809
- **Branch / PR:** main / #108 merged
- **Scope:** strengthen the AgentSwitchboard ledger with BOUNDED versus UNBOUNDED classification, derive EXECUTE versus DECOMPOSE routes, add a compact highest-priority frontier reader, and enforce anti-rumination semantics with tests and CI
- **Forbidden:** changing the immutable portable v1 required-field set; forcing the local execution profile onto existing consumer repositories; product behavior changes; Wayfinder implementation changes; implicit hooks; claiming runtime task completion from ledger metadata
- **Dependencies:** ASQ-001 local ledger implementation merged on main
- **References:** `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`, `scripts/Test-RepositoryWorkLedgerContract.ps1`, `scripts/Get-RepositoryWorkLedgerFrontier.ps1`, `tests/test_repository_work_ledger_contract.py`, `tests/test_repository_work_ledger_frontier.py`
- **Acceptance gate:** the local validator rejects missing/invalid work classes and monolithic UNBOUNDED implementation states; READY UNBOUNDED work must create bounded children; the frontier deterministically selects the highest-priority actionable task and derives EXECUTE or DECOMPOSE; Windows and Ubuntu CI pass
- **Gate:** none
- **Last proof:** workflow:31332148720 passed the repository work ledger contract on Windows and Ubuntu; merge:b090637be810b2b25c35a11c299b4f2d9cc90ca3 merged PR #108; artifact:scripts/Get-RepositoryWorkLedgerFrontier.ps1 and artifact:.ai/harness/repository-work-ledger.policy.json are merged on main
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-08-09T19:41:00Z

## ASQ-003 — Reconcile portable ledger authority to BlacksmithGuild

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** chatgpt-blacksmith-ledger-authority-reconcile-20260809
- **Branch / PR:** main / #110 merged
- **Scope:** pin BlacksmithGuild RepoLedgerInteroperability.v1 as the portable compatibility authority while preserving agentswitchboard.repository-work-ledger.v1 as the AgentSwitchboard-local compatibility/execution profile and preserving the existing Work class/frontier behavior
- **Forbidden:** changing frontier implementation behavior; changing portable v1 status/field/proof semantics; forcing Work class onto consumers; modifying product/runtime behavior; copying BlacksmithGuild validators for runtime execution
- **Dependencies:** BlacksmithGuild portable contract merge 429237aa41d8712d71859865c9be407ca23d8580 and authority-registry reconciliation merge ecf0718556e77f10747a997d2cb0173af81b3d29
- **References:** `.ai/harness/repository-work-ledger-adoption.json`, `.ai/harness/repository-work-ledger.policy.json`, `docs/governance/repository-work-ledger-contract.md`, `scripts/Test-RepositoryWorkLedgerContract.ps1`, `tests/test_repository_work_ledger_contract.py`, `.ai/WORK_QUEUE.md`
- **Acceptance gate:** the existing local validator and positive/negative suites pass on Windows and Ubuntu; exact Blacksmith portable pin and stale-ref rejection are enforced; AgentSwitchboard local Work class/frontier behavior remains unchanged; PR diff contains no product/runtime mutation
- **Gate:** none
- **Last proof:** workflow:31332609903 passed the repository work ledger contract on Windows and Ubuntu with 18 contract tests and 5 frontier tests; merge:0b5a0c951da5152f5dbd37b1b207ad4adc4b0420 merged PR #110; artifact:.ai/harness/repository-work-ledger-adoption.json artifact:.ai/harness/repository-work-ledger.policy.json artifact:docs/governance/repository-work-ledger-contract.md artifact:scripts/Test-RepositoryWorkLedgerContract.ps1
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-08-09T19:52:00Z

## ASQ-004 — September coordination floor: bootstrap + child bus program

- **Status:** DONE
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** Admin Box 1
- **Branch / PR:** main
- **Scope:** create durable September program in `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json` + `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, update `plans/plan-registry.json`, add bounded work items for Panels 02–10, record collision ledger for PR #151 Pi mixed, PR #149 path authority, PR #115 stale LSP
- **Forbidden:** product/bootstrap implementation, Pi/OpenCode adapter code, LSP behavior mutation, provider credentials, destructive Git, closing PR #151/#149/#115 before successor containment, committing private OneDrive/Northwell paths or runtime receipts
- **Dependencies:** none
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, `plans/plan-registry.json`, `.ai/WORK_QUEUE.md`, `docs/governance/repository-work-ledger-contract.md`, `scripts/Test-PublicPlanContracts.ps1`, `scripts/Test-RepositoryWorkLedgerContract.ps1`, `AGENTS.md`
- **Acceptance gate:** provider floor refreshed to `main@54cce3b` (parent `2f69049`, LSP runtime-smoke contract intact, `81461e7` lifecycle already beneath main); September plan accurately encodes 10-panel program with waves/dependencies/collision/proof ceilings; plan registry and ledger updated with only public-safe data; no private path committed; PR #151 source material, #149 waiting, #115 stale dispositions recorded; plan/ledger validators pass
- **Gate:** none
- **Last proof:** commit:54cce3b824a982e26595efa8ed5060e555411693 provider floor `main@54cce3b` parent `2f69049`; artifact:plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json artifact:plans/active/ASB-2026-09-agent-bootstrap-child-bus.md artifact:plans/plan-registry.json artifact:.ai/WORK_QUEUE.md
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-005 — OpenCode fresh-TUI LSP runtime certification

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Admin Box 1
- **Branch / PR:** main
- **Scope:** prove or disprove active Python LSP in a fresh interactive OpenCode TUI vs headless baseline `20260912T194619Z-e3f423df`; open `tests/test_technician_live_cert_surface.py` once; LSP-only hover/goToDefinition/findReferences on `read_text`; write local untracked `opencode-lsp-runtime-smoke.json/.md` under `%LOCALAPPDATA%/AgentSwitchboard/opencode-lsp/runs/<run-id>/` with `nonLspSemanticFallbackUsed No` and verbatim errors; complete durable gates G0–G8 in `docs/harness/asq005-fresh-tui-lsp-runtime-gates.md`
- **Forbidden:** treating Configure/CI/overlay proof as ASQ-005 DONE; non-LSP grep/search/AST/manual semantic fallback; changing `OPENCODE_CONFIG`; free-model confidential data; committing runtime receipts; Cloud/Linux agents claiming live TUI PASS; starting ASQ-008/009 as ASB live adapter expansion (FirstMate FREEZE/HAND-OFF)
- **Dependencies:** ASQ-004
- **References:** `docs/harness/asq005-fresh-tui-lsp-runtime-gates.md`, `tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json`, `docs/harness/opencode-lsp-workstation-setup.md`, `tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json`, `tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md`, `scripts/Test-OpenCodeLspHarness.ps1`
- **Acceptance gate:** G0–G8 all green on Admin Box 1; fresh TUI; fixture opened once; hover/definition/references PASS with `nonLspSemanticFallbackUsed No`; differential class recorded; local receipts schema-valid; verdict exactly `LSP_RUNTIME_SMOKE_TEST: PASS`; owning harness green. Configure-only proof is insufficient.
- **Gate:** none
- **Last proof:** merge:24cce9e321a4913dda32f21a2d51a599dd0e4bb4 pr:#163 INTEGRATED Live routing floor; merge:feb9f71 cloud UNPROVEN handoff; current main contains FirstMate interop floor; LIVE_RUNTIME_PROOF:UNPROVEN — Admin Box 1 G0–G8 observation required
- **Next action:** run Admin Box 1 Live-floor fresh-TUI certification through G0–G8: `$ErrorActionPreference='Stop'; $repo = Join-Path $env:USERPROFILE 'dev\AgentSwitchBoard-Live'; Set-Location -LiteralPath $repo; $root=(git rev-parse --show-toplevel).Trim(); if ($root -ne $repo) { throw "WRONG_REPOSITORY_ROOT|actual=$root|expected=$repo" }; $origin=(git remote get-url origin).Trim(); if (($origin -replace '\.git$','').TrimEnd('/') -ne 'https://github.com/EndeavorEverlasting/AgentSwitchboard') { throw "WRONG_REPOSITORY_ORIGIN|$origin" }; git fetch --all --prune --tags; if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }; git pull --ff-only origin main; if ($LASTEXITCODE -ne 0) { throw 'MAIN_NOT_CLEAN_BEHIND_ONLY' }; if (git status --porcelain) { throw 'WORKTREE_NOT_CLEAN' }; $head=(git rev-parse HEAD).Trim(); if (-not (git merge-base --is-ancestor 24cce9e321a4913dda32f21a2d51a599dd0e4bb4 HEAD; $?)) { throw "MAIN_MISSING_ASQ005_FLOOR|head=$head" }; pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryWorkLedgerFrontier.ps1 -Json; python -m unittest tests.test_asq005_canonical_runtime_floor tests.test_opencode_lsp_harness -q; $env:OPENCODE_EXPERIMENTAL_LSP_TOOL='true'; pwsh -NoLogo -NoProfile -File .\tooling\harness\operational\opencode-lsp-setup\Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath $repo; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; $run=Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\AgentSwitchboard\opencode-lsp\runs" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1; & (Join-Path $run.FullName 'Open-AgentSwitchboard-OpenCode-Lsp.cmd'); open `tests/test_technician_live_cert_surface.py` exactly once; LSP-only hover then goToDefinition then findReferences on `read_text` with nonLspSemanticFallbackUsed No; write local `opencode-lsp-runtime-smoke.json/.md` under $run; record differential vs `20260912T194619Z-e3f423df`; pwsh -NoLogo -NoProfile -File .\scripts\Test-OpenCodeLspHarness.ps1 -RootPath $repo; git diff --check
- **Updated:** 2026-09-13T19:50:00Z

## ASQ-006 — Pi reversible system bootstrap lifecycle

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 03 Pi bootstrap lane
- **Branch / PR:** main
- **Scope:** salvage Pi system-bootstrap portion of PR #151 `8d40604e` onto current main and make Pi a reversible `Inspect/Apply/Remove` adapter via `tooling/harness/system-bootstrap-lifecycle/` with `Bootstrap-Pi-SystemWide.cmd` + `Unbootstrap-Pi-SystemWide.cmd` + `tooling/pi/Install-AgentSwitchboardPiSystem.ps1`
- **Forbidden:** Pi child-agent request/result, generic ASB child-bus contracts, OpenCode LSP harness, provider credentials, PR #149 path-policy semantics, arbitrary npm dependency, destructive Git
- **Dependencies:** ASQ-004
- **References:** `tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json`, `tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1`, `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/151
- **Acceptance gate:** Pi registered in `adapters.v1.json` without redesigning shared contract; `Inspect/Apply/Remove` parity via lifecycle module, state under `%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\pi`, preserves credentials/settings/sessions, fails closed on drift, recovers interrupted Remove
- **Gate:** none
- **Last proof:** merge:1f20499 Pi after P13 guard sync; merge:85ecf77 child bus v1 on main; Pi lifecycle already on main, child bus now DONE
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-12T22:45:00Z

## ASQ-007 — Shared ASB child bus v1 contract spine

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 04 shared child-bus lane
- **Branch / PR:** main
- **Scope:** create provider-neutral `tooling/harness/child-agent-bus/` with `child-agent-request.v1`, `child-agent-result.v1`, `child-agent-error.v1`, adapter registry, artifact registry, fixtures, validator, generic `Invoke-AgentSwitchboardChild` front door, docs, CI, capabilities `agent.child.dispatch` etc.
- **Forbidden:** Pi/OpenCode CLI invocation, provider calls, credentials, actual child runtime, Pi fusion product logic, direct agent-to-agent pairwise config, system-bootstrap lifecycle mutation, default-branch child writers
- **Dependencies:** ASQ-004
- **References:** `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/manifest.json`, `docs/governance/harness-doctrine.md`, `tooling/harness/child-agent-bus/`
- **Acceptance gate:** closed schemas with invocationId/lineage/authority/budgets/evidence root, generic dispatcher fails closed when adapter absent, validator + fixture matrix (read-only, isolated writer, dirty/default-branch/base-SHA mismatch, budget exceeded etc.) green, hub-and-spoke `parent → ASB → adapter → child` enforced
- **Gate:** none
- **Last proof:** merge:85ecf77 child bus v1 on main; Pi lifecycle already on main, child bus now DONE
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-12T22:45:00Z

## ASQ-008 — Pi child adapter conformance

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** frozen by ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME
- **Branch / PR:** main
- **Scope:** historically: migrate Pi child-execution behind shared bus. Architecture decision FREEZES ASB live Pi child-bus adapter implementation; Pi live child runtime hands off to FirstMate harness adapters. Pi system bootstrap and experimental pi-fusion-orchestration remain separately owned.
- **Forbidden:** implementing ASB Pi child-bus adapter launchers; redefining common request/result fields to invent a second crew runtime; pairwise Pi↔OpenCode calls; persistent RPC; provider fallback; main/default-branch child writer
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `tooling/harness/child-agent-bus/`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`
- **Acceptance gate:** remain frozen until an explicit superseding architecture revision reopens ASB-owned live child adapters; no adapter registry mutation for Pi launch
- **Gate:** FREEZE — FirstMate is canonical crew runtime; do not implement Panel 05 as ASB live launcher
- **Last proof:** artifact:docs/architecture/asb-firstmate-runtime-boundary.md disposition FREEZE/HAND-OFF; child-bus `adapters: []` on main@e76ba4b
- **Next action:** none; no safe actionable work remains under frozen scope — route crew runtime through ASQ-015 FirstMate interop
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-009 — OpenCode child adapter parity

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** frozen by ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME
- **Branch / PR:** main
- **Scope:** historically: OpenCode as second bus adapter. Architecture decision FREEZES ASB OpenCode child-bus adapter implementation; live child runtime hands off to FirstMate.
- **Forbidden:** implementing ASB OpenCode child-bus adapters; OpenCode LSP harness redesign; pairwise Pi/OpenCode config; global OPENCODE_CONFIG mutation; provider fallback
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `tooling/harness/child-agent-bus/`
- **Acceptance gate:** remain frozen until an explicit superseding architecture revision; no OpenCode adapter registry entry for ASB live launch
- **Gate:** FREEZE — FirstMate is canonical crew runtime; do not implement Panel 06 as ASB live launcher
- **Last proof:** artifact:docs/architecture/asb-firstmate-runtime-boundary.md disposition FREEZE
- **Next action:** none; no safe actionable work remains under frozen scope — route crew runtime through ASQ-015
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-010 — Heterogeneous read-only pilot (Pi + OpenCode)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** frozen/repurposed by ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME
- **Branch / PR:** main
- **Scope:** historically: ASB child-bus Pi+OpenCode fan-out. FREEZE ASB dual-adapter pilot; REPURPOSE any heterogeneous crew pilot through FirstMate after ASQ-015 interop floor.
- **Forbidden:** ASB bus dual-adapter fan-out implementation; repository mutation via ASB nested children; direct Pi↔OpenCode spawning; persistent RPC
- **Dependencies:** ASQ-014, ASQ-015
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `tooling/harness/child-agent-bus/`
- **Acceptance gate:** no ASB child-bus heterogeneous pilot proceeds; future FirstMate crew pilot requires refreshed interop floor and explicit local-only posture
- **Gate:** FREEZE/REPURPOSE — do not implement Panel 07 on the ASB child-bus spine
- **Last proof:** artifact:docs/architecture/asb-firstmate-runtime-boundary.md disposition FREEZE/REPURPOSE
- **Next action:** none; no safe actionable work remains under frozen ASB-bus scope — after ASQ-015, open a FirstMate-routed crew pilot task if needed
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-011 — Mediated nested delegation v1 (maxDepth 2)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** retired as ASB live nested bus; FirstMate flat crew/secondmates cover parallelism
- **Branch / PR:** main
- **Scope:** historically: ASB child→ASB→grandchild nested bus. RETIRE ASB nested live program. FirstMate secondmates are flat direct reports and do not implement ASB maxDepth lineage; any future lineage guarantee is POLICY-INPUT/bridge only.
- **Forbidden:** implementing ASB nested bus runtime; direct Pi↔OpenCode subprocess; unlimited recursion; multiple concurrent writers; child merge/push; automatic retries; silent fallback; persistent RPC
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`
- **Acceptance gate:** ASB nested bus remains unimplemented; FirstMate owns nesting/secondmates unless a superseding ADR proves an ASB-only guarantee
- **Gate:** RETIRE/FREEZE — do not implement Panel 08 on the ASB child-bus spine; do not treat FirstMate as an ASB nested-bus clone
- **Last proof:** artifact:docs/architecture/asb-firstmate-runtime-boundary.md disposition RETIRE (ASB live) + POLICY-INPUT residue; FirstMate flat secondmates at b182d0f
- **Next action:** none; no safe actionable work remains under retired ASB nested-bus scope
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-012 — Nested runtime certification (depth-2 chain)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** retired as ASB live nested certification; route crew runtime proofs through FirstMate after ASQ-015
- **Branch / PR:** main
- **Scope:** historically: ASB depth-2 heterogeneous child-bus certification. RETIRE ASB-owned nested bus certification program. Future depth/parallelism proofs use FirstMate flat crew after interop floor.
- **Forbidden:** ASB depth-2 child-bus certification implementation; writer children via ASB bus; direct cross-agent subprocess; automatic retries/fallback; persistent RPC; repository mutation; secrets
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`
- **Acceptance gate:** ASB nested runtime certification program remains frozen; any depth-2 crew proof uses FirstMate after ASQ-015
- **Gate:** RETIRE/FREEZE — do not implement Panel 09 as ASB-owned live nested bus certification
- **Last proof:** artifact:docs/architecture/asb-firstmate-runtime-boundary.md disposition RETIRE (ASB live nested certification)
- **Next action:** none; no safe actionable work remains under retired ASB nested-bus scope
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-013 — PR/path authority cleanup and final convergence

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 10 convergence lane
- **Branch / PR:** main
- **Scope:** reconcile superseded PR #151 Pi mixed, #115 stale LSP harness, #149 draft path authority; close/supersede with containment proof after successors integrated; close September plan/work-ledger to terminal states. Dependencies narrowed by FirstMate ADR: no longer waits on ASQ-008..012 live runtime.
- **Forbidden:** closing unrelated PRs, deleting worktrees without proof, force operations, silently invalidating explicit operator OneDrive path, new feature implementation, lowering proof gates, reopening frozen ASQ-008..012 as ASB live runtime
- **Dependencies:** ASQ-005, ASQ-006, ASQ-007, ASQ-014
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `docs/architecture/asb-firstmate-runtime-boundary.md`, `.ai/WORK_QUEUE.md`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/151, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/115, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/149
- **Acceptance gate:** PR #151/#115/#149 dispositioned only with successor containment proof; frozen ASQ-008..012 remain skipped/blocked rather than silently reopened; September plan terminal only when remaining proceed gates are satisfied
- **Gate:** ASQ-005 still required for LSP certification; ASQ-014 ADR must be on main
- **Last proof:** none
- **Next action:** after ASQ-014 integrates and ASQ-005 completes or is explicitly waived, refresh main and PRs #151/#115/#149, prove containment, then close as superseded with successor references
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-014 — Accept FirstMate canonical crew-runtime boundary

- **Status:** DONE
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** P95 architecture lane
- **Branch / PR:** main / #164 merged
- **Scope:** persist accepted architecture decision that FirstMate is the canonical live crew runtime; ownership matrix; subtraction analysis; KEEP/NARROW/HAND-OFF/RETIRE dispositions; revise September plan and freeze ASQ-008..012
- **Forbidden:** implementing adapters; deleting GNHF or child-bus; Prompt Kit FirstMate bridge; README rewrite; claiming live FirstMate crew proof
- **Dependencies:** ASQ-004, ASQ-007
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, https://github.com/kunchenguid/firstmate, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/96
- **Acceptance gate:** ADR committed with matrix/subtraction/dispositions; September plan tasks updated; ledger FREEZE/PROCEED states recorded; public-plan and work-ledger validators pass
- **Gate:** none
- **Last proof:** merge:3a1aa4fb4c700af251a7e94cbbcccf3cb5fb0016 artifact:docs/architecture/asb-firstmate-runtime-boundary.md artifact:plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-015 — Refresh FirstMate interop floor to b182d0f

- **Status:** READY
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** FirstMate interop lane
- **Branch / PR:** none yet — derive from PR #96 lineage on current main
- **Scope:** rebase/refresh AgentSwitchboard FirstMate interop harness (PR #96 lineage) onto current main; update upstream pin from 833a9a25… to FirstMate main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657; preserve Windows→WSL anti-regression contracts; keep first_safe_sprint local-only and yolo_enabled false
- **Forbidden:** FirstMate upstream mutation; enabling +yolo; claiming live crew dispatch without runtime floor; native-Windows FirstMate compatibility claim; deleting GNHF; unfreezing ASQ-008..012
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/96, https://github.com/kunchenguid/firstmate
- **Acceptance gate:** refreshed verified_commit pin; contract tests green; Windows bridge regressions preserved; proof ceiling remains below live crew unless physical floor passes
- **Gate:** none
- **Last proof:** none
- **Next action:** create isolated branch from refreshed main, import/rebase PR #96 FirstMate harness surfaces, update upstream pin to b182d0f, run firstmate contract tests and Windows -ContractOnly bridge
- **Updated:** 2026-09-13T17:30:00Z

## ASQ-016 — Encode GNHF NARROW ownership boundary

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** GNHF contract lane
- **Branch / PR:** none yet
- **Scope:** document and enforce that tooling/gnhf remains the Windows-first bounded single-agent/fleet launcher with unique readiness contracts, and must not expand into a multi-crew control plane competing with FirstMate; no launcher deletion
- **Forbidden:** deleting GNHF; implementing multi-crew supervision inside GNHF; unfreezing child-bus adapters; provider credential commits
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `tooling/gnhf/README.md`, `tooling/gnhf/Start-GnhfSprint.ps1`
- **Acceptance gate:** README or owning contract states NARROW boundary explicitly; optional validator asserts no crew-runtime claim language; launchers remain intact
- **Gate:** none
- **Last proof:** none
- **Next action:** open isolated branch and add NARROW ownership clause plus focused contract check referencing the ADR
- **Updated:** 2026-09-13T17:30:00Z
