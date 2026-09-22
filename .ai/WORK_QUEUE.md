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

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Admin Box 1
- **Branch / PR:** main
- **Scope:** prove or disprove active Python LSP in a fresh interactive OpenCode TUI vs headless baseline `20260912T194619Z-e3f423df`; open `tests/test_technician_live_cert_surface.py` once; LSP-only hover/goToDefinition/findReferences on `read_text`; write local untracked `opencode-lsp-runtime-smoke.json/.md` under `%LOCALAPPDATA%/AgentSwitchboard/opencode-lsp/runs/<run-id>/` with `nonLspSemanticFallbackUsed No` and verbatim errors; complete durable gates G0–G8 in `docs/harness/asq005-fresh-tui-lsp-runtime-gates.md`
- **Forbidden:** treating Configure/CI/overlay proof as ASQ-005 DONE; non-LSP grep/search/AST/manual semantic fallback; changing `OPENCODE_CONFIG`; free-model confidential data; committing runtime receipts; Cloud/Linux agents claiming live TUI PASS; starting ASQ-008/009 as ASB live adapter expansion (FirstMate FREEZE/HAND-OFF)
- **Dependencies:** ASQ-004
- **References:** `docs/harness/asq005-fresh-tui-lsp-runtime-gates.md`, `tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json`, `tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1`, `docs/harness/opencode-lsp-workstation-setup.md`, `tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json`, `tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md`, `scripts/Test-OpenCodeLspHarness.ps1`
- **Acceptance gate:** G0–G8 all green on Admin Box 1; fresh TUI; fixture opened once; hover/definition/references PASS with `nonLspSemanticFallbackUsed No`; differential class recorded; local receipts schema-valid; verdict exactly `LSP_RUNTIME_SMOKE_TEST: PASS`; owning harness green. Configure-only proof is insufficient.
- **Gate:** none
- **Last proof:** merge:9af49c5e65960080cbfd5c709eca1becc86b30a6 pr:#286+#287; operator-proof:20260915T035056Z-62bcc7ed; Admin Box 1 LIVE_PASS@2026-09-15T03:50Z on main@9af49c5e65960080cbfd5c709eca1becc86b30a6 (contains pr:#286 path-normalize + pr:#287 launcher OPENCODE_EXPERIMENTAL_LSP_TOOL); G0 PASS; G1 PASS_CONFIGURE_ONLY run `20260915T035056Z-62bcc7ed`; G2 generated CMD process start observed; G3/G4 OpenCode LSP tool hover→goToDefinition→findReferences on `read_text` PASS (`(function) def read_text(path: str) -> str`; definition `tests/test_technician_live_cert_surface.py:24`; 22 references; `nonLspSemanticFallbackUsed=No`); G5 `PASS_TUI_HEADLESS_DIFFERENTIAL` vs `20260912T194619Z-e3f423df`; G6 local untracked `opencode-lsp-runtime-smoke.json/.md` under Configure run; G7 `Test-OpenCodeLspHarness.ps1` PASS + `git diff --check` clean; G8 verdict exactly `LSP_RUNTIME_SMOKE_TEST: PASS`. Observation mode: launcher-equivalent OpenCode agent session (`opencode run`) plus G2 CMD launch — not keyboard driving inside interactive TUI chrome. Tracked contract `liveProofStatus` remains UNPROVEN sentinel (configureNeverPromotesToDone). Prior cloud LIVE_ATTEMPT WINDOWS_REQUIRED superseded. ASQ-008/009 remain FirstMate FREEZE/HAND-OFF.
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-15T03:55:00Z

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

- **Status:** DONE
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** Cursor Cloud Agent cursor/asq-015-firstmate-interop-refresh-11b8
- **Branch / PR:** merged #308 / faac296d4b8e292d3ed22893155162d7e17d7a57
- **Scope:** rebase/refresh AgentSwitchboard FirstMate interop harness (PR #96 lineage) onto current main; update upstream pin from 833a9a25… to FirstMate main@b182d0f908b78d08c7ccb8dce3775bdca8c5d657; preserve Windows→WSL anti-regression contracts; keep first_safe_sprint local-only and yolo_enabled false; wire validation hooks into operational manifest
- **Forbidden:** FirstMate upstream mutation; enabling +yolo; claiming live crew dispatch without runtime floor; native-Windows FirstMate compatibility claim; deleting GNHF; unfreezing ASQ-008..012; reviving stale crew orchestration skill/selector
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/96, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/308, https://github.com/kunchenguid/firstmate
- **Acceptance gate:** refreshed verified_commit pin; contract tests green; Windows bridge regressions preserved; hooks wired into manifest; proof ceiling remains below live crew unless physical floor passes
- **Gate:** none
- **Last proof:** PRODUCT_PASS_LOCAL_POSTURE PROVEN on tip 9ee6f8d; merge:faac296; hooks+manifest+tests+docs landed; pin b182d0f; rebaseRequiredBeforePr96StackMerge remains true
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-17T21:35:00Z

## ASQ-016 — Encode GNHF NARROW ownership boundary

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** GNHF contract lane
- **Branch / PR:** main / #300 merged
- **Scope:** document and enforce that tooling/gnhf remains the Windows-first bounded single-agent/fleet launcher with unique readiness contracts, and must not expand into a multi-crew control plane competing with FirstMate; no launcher deletion
- **Forbidden:** deleting GNHF; implementing multi-crew supervision inside GNHF; unfreezing child-bus adapters; provider credential commits; force-merge past red CI
- **Dependencies:** ASQ-014
- **References:** `docs/architecture/asb-firstmate-runtime-boundary.md`, `tooling/gnhf/README.md`, `tooling/gnhf/Start-GnhfSprint.ps1`
- **Acceptance gate:** README or owning contract states NARROW boundary explicitly; optional validator asserts no crew-runtime claim language; launchers remain intact; static validators and required CI pass before merge
- **Gate:** none
- **Last proof:** merge:ba19f7c pr:#300; artifact:tooling/gnhf/README.md Ownership boundary section citing ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME; artifact:tests/test_gnhf_narrow_ownership_contract.py unittest with 13 contract assertions; artifact:scripts/Test-GnhfNarrowOwnershipContract.ps1 PowerShell validator; main@ba19f7c contains preservation commits f71f19a+a8d5118 cherry-picked from original branch
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-17T20:00:00Z

## ASQ-017 — FM-WSL-12 physical-floor-continue live runtime proof

- **Status:** DONE
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** Windows Admin Box operator / runtime-proof lane
- **Branch / PR:** main (durable Admin Box floor entrypoint integrated via #183); live observation pending Admin Box
- **Scope:** prove FM-WSL-12 physical WSL/Ubuntu floor through harness `-Mode physical-floor-continue` on an authorized Windows Admin Box with explicit `Ubuntu`; allowlisted missing packages may be repaired and the floor rerun without another permission round-trip; stop for `BLOCKED_GITHUB_AUTH` only as the credential gate; exercise report-only `-Mode physical-floor` as the protected control in the same session when safe
- **Forbidden:** claiming LIVE PASS from cloud/Linux/contract/CI; automating GitHub credential entry; broadening package allowlist; ASQ-008/009 unfreeze; FirstMate crew dispatch claims (`FM-CREW-13`); committing local receipts/tokens/machine paths
- **Dependencies:** FM-BRIDGE-10 / PR #177 bounded repair authority; PR #178 continuation entrypoint on main; PR #183 durable `Invoke-Asq017AdminBoxLiveFloor.ps1` on main; PR #189 Admin Box `NEXT=` surface + passwordless-sudo preflight on main; PR #192 apt-scoped sudo probe + exit 47 BLOCKED_SUDO propagation on main; PR #194 primary-harness early preflight exit 48 + child `NEXT=` preservation on main; PR #196 FirstMate dirty/pin early preflight exits 49/50 on main; PR #198 `-FirstMatePath` physical-floor dirty/pin override (skips `$HOME/firstmate`) on main; PR #200 skip dirty/off-pin FirstMate auto-discovery (bounded $HOME/firstmate bootstrap) on main; PR #207 surface exit 44 BLOCKED_MISSING_TOOLS on Asq017/continuation after exhausted/failed bounded apt repair on main; PR #211 structure bridge bootstrap/contract exits 51/52 + late interop 45/48 on main; PR #213 PhysicalFloor FirstMate pin loaded from `tooling/firstmate/harness/upstream-pin.json` on main; PR #215 Asq017/oneshot exit-50 NEXT pin loaded from `tooling/firstmate/harness/upstream-pin.json` on main; PR #217 Asq017 reloads FirstMate pin after ff-only git refresh before exit-50 NEXT on main; PR #219 Asq017 prefers child NEXT= over parent fallbacks and ASQ-017 paste loads exit-50 pin from upstream-pin.json on main; PR #221 physical-floor runbook exit-50 paste/table load pin from upstream-pin.json on main; PR #223 behavioral Asq017 NEXT-helper + pin-loader gate proof on main; PR #225 PhysicalFloor prerequisite timeout / head-mismatch structured STATUS+NEXT (no throw) on main; PR #227 bridge Exact-head mismatch / missing wsl.exe structured STATUS+NEXT (no throw) on main; PR #229 oneshot Exact-head mismatch / harness-timeout structured STATUS+NEXT (no throw) on main; PR #231 Asq017 git-refresh / HEAD-resolve structured STATUS+NEXT (no throw) on main; PR #233 oneshot WSL-distribution / HEAD / harness-start structured STATUS+NEXT (no throw) on main; PR #235 PhysicalFloor WSL-distribution / HEAD / FirstMate-pin structured STATUS+NEXT (no throw) on main; PR #237 bridge WSL-distribution / start / source-tree structured STATUS+NEXT (no throw) on main; PR #239 continuation WSL-distribution / start / HEAD structured STATUS+NEXT (no throw) on main; PR #241 PhysicalFloor process-start structured STATUS+NEXT (no throw) on main; PR #243 continuation missing/non-allowlisted NEXT_ACTION structured STATUS+NEXT (no throw) on main; PR #245 bridge git Assert-LastExit failures structured STATUS+NEXT (no throw) on main; PR #247 bridge WSL workspace-cleanup structured STATUS+NEXT (no throw) on main; PR #250 structure Asq017/oneshot harness-start + FirstMate-pin and bridge/PhysicalFloor prerequisite-timeout STATUS+NEXT (no throw) on main; PR #252 emit parent STATUS= on Asq017 blockers + oneshot structured fail STATUS + continuation sudo/apt hang exits keep 124 (STATUS=BLOCKED_PREREQUISITE_TIMEOUT) on main; PR #254 surface Asq017/parent paste/runbook exit 124 as STATUS=BLOCKED_PREREQUISITE_TIMEOUT (no generic FAILED collapse) on main; PR #257 structure Asq017 -ContractOnly failure as STATUS=CONTRACT_FAIL (no throw) on main; PR #259 map oneshot contract/continue child exit 124 to STATUS=BLOCKED_PREREQUISITE_TIMEOUT (not harness-contract/generic continue-fail) on main; PR #262 map oneshot protected-control child exit 124 to STATUS=BLOCKED_PREREQUISITE_TIMEOUT (not BLOCKED_PROTECTED_CONTROL) on main; PR #264 structure continuation exit→STATUS recovery (46–52/124) and STATUS=BLOCKED_CONTINUATION_EXHAUSTED fallthrough on main; PR #266 preserve child STATUS=BLOCKED_* through oneshot/Asq017 (incl. CONTINUATION_EXHAUSTED) on main; PR #268 Admin Box paste/runbook exit-1 STATUS guidance on main; PR #270 tip-cite ContractOnly+exit46 on 4e884b1 after #268 on main; PR #269 FM→ASB observation disposable-home cite on main; PR #271 tip-cite ContractOnly+exit46 on 4258ac2 after #269/#270 on main; PR #272 tip-cite ContractOnly+exit46 on 4b26814 after #271 on main; PR #274 Invoke-*/Test-* early wiring→BLOCKED_HARNESS_CONTRACT/52; PR #275 Harness preserve child exits; PR #276 Harness Python check deferred to contract mode/52 on main
- **References:** `docs/harness/firstmate-wsl-physical-floor-runbook.md`, `Invoke-Asq017AdminBoxLiveFloor.ps1`, `Invoke-FmWsl12AdminBoxLiveProof.ps1`, `Invoke-FirstMatePhysicalFloorContinuation.ps1`, `Test-AgentSwitchboard-FirstMate-Harness.ps1`, `plans/active/ASB-2026-09-multi-product-bootstrap-charter.plan.json`, `tooling/firstmate/harness/integration-contract.json`
- **Acceptance gate:** Admin Box run reaches physical-floor PASS markers with exact-head readback and evidence root, or stops at `BLOCKED_MISSING_TOOLS` after exhausted bounded repair, or at `BLOCKED_WSL_BOOTSTRAP` / `BLOCKED_HARNESS_CONTRACT`, or at a real non-package blocker (`BLOCKED_GITHUB_AUTH` / `BLOCKED_SUDO` / `BLOCKED_PRIMARY_HARNESS` / `BLOCKED_FIRSTMATE_DIRTY` / `BLOCKED_FIRSTMATE_PIN` / transport) with preserved evidence; cloud hosts must emit `STATUS=BLOCKED_WINDOWS_WSL_REQUIRED` exit 46 rather than unstructured crash
- **Gate:** none
- **Last proof:** operator-proof:20260919T205523Z-asq017-physical-floor-pass; reporter:ASB·local·asq017-floor; checkout:AgentSwitchboard-asq017-floor@1f1240a390eb14d226909f8b14b1ab1c843873d0; ASQ017_RESULT=PHYSICAL_FLOOR_PASS; CHILD_EXIT_CODE=0; LIVE_RUNTIME_PROOF=OBSERVED_PHYSICAL_FLOOR_ONLY; host:Windows+Ubuntu Admin Box; primary harness:pi; FirstMate pin:$HOME/firstmate@b182d0f; evidence root:local untracked under operator AppData (operator observation only; not committed); proof ceiling: physical WSL floor only — no FM-CREW-13 crew dispatch; no Prompt Kit dual-path claim; LSP-01/TUT-WAVE may unblock on Windows-only as their deps state; ledger sync landed via PR #333
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-20T01:05:00Z

## ASQ-018 — Deterministic automated test floor bootstrap

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Cursor Auto / automated-test-floor lane
- **Branch / PR:** main / #290 + #291 merged
- **Scope:** FLOOR-01..04 fail-closed floor bootstrap via PR #290 @ main`7effd42`; FLOOR-05 Actions-quota local proof packet + receipt provenance + quota-aware workflow triggers via PR #291 @ main`3c5cca9`
- **Forbidden:** merge/release/deploy automation (P105); secrets; live runtime mutation; rewriting unrelated path-filtered domain workflows; claiming runtime proof from static PASS; cron schedule without explicit operator preference; patching production gates for canary; committing ephemeral receipts
- **Dependencies:** none
- **References:** `plans/active/ASB-2026-09-automated-test-floor.plan.json`, `.ai/harness/automated-test-floor.manifest.json`, `scripts/Test-AutomatedTestFloor.ps1`, `scripts/Prove-AutomatedTestFloorLocal.ps1`, `docs/harness/automated-test-floor.md`, `.github/workflows/automated-test-floor.yml`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/290, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/291
- **Acceptance gate:** local meta + floor PASS; Prove-AutomatedTestFloorLocal PASS; isolated canary fails closed without production-gate mutation; provenance receipts; FLOOR-05 integrated into main
- **Gate:** none
- **Last proof:** merge:7effd421060241d8a0e76e007be052064b5da677 pr:#290; merge:3c5cca988072efbd69969cfe33d3fec18e120bcc pr:#291; merge:1f8c32addd53b598ff0f18e3c4b23796cb8d1f3d pr:#292; canary FAIL workflow:34931598102 @dcecfd4; restore PASS workflow:34932484309 @40d46a4; floor PASS workflow:34938435764 @aa7a3b7; Prove-AutomatedTestFloorLocal PASS on main@3c5cca9
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-15T07:20:00Z

## ASQ-019 — Rank user tutorial paths after FirstMate crew handoff

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Cursor Auto / user-tutorial-ranking lane
- **Branch / PR:** main / #294 merged
- **Scope:** inventory implemented operator journeys; classify readiness; publish durable ranked launch order and disposition ledger in `plans/active/ASB-2026-09-user-tutorial-path-ranking.*`; register plan; leave TUT-01 as first P18 writing sprint; do not author every tutorial in this item
- **Forbidden:** teaching ASB child-bus spawn/nested crew as current product; Open Worker claims without repo evidence; claiming FM-WSL-12 or live-cert PASS from ranking; secrets/private paths in public plans; unfreezing ASQ-008..012; writing full tutorial corpus in this claim
- **Dependencies:** ASQ-014 ADR on main; existing workstation docs and root CMD entrypoints
- **References:** `plans/active/ASB-2026-09-user-tutorial-path-ranking.plan.json`, `plans/active/ASB-2026-09-user-tutorial-path-ranking.md`, `docs/architecture/asb-firstmate-runtime-boundary.md`, `docs/workstation/technician-pull-and-run.md`, `docs/workstation/technician-agentswitchboard-ready.md`, `docs/workstation/opencode-click-launcher.md`, https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/294
- **Acceptance gate:** schema-valid public plan + registry membership; disposition ledger complete; launch order names TUT-01 first; validators PASS; ranking integrated to main
- **Gate:** none
- **Last proof:** merge:fd9ace5ab10644b887a41b48e6ac7183e3ed1257 pr:#294; contains tip d9f9ddb942437804387f80b21693fd38d77a5caf; inventory floor main@3a153c11f9db9cacc1d9d9dda8c7358c0e3ecbf0; Open Worker grep zero matches; Test-PublicPlanContracts PASS; Test-RepositoryWorkLedgerContract PASS
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-15T16:55:00Z

## ASQ-020 — Local merge-gate proof orchestration

- **Status:** DONE
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Cursor Cloud Agent / merge-gate-local implementation
- **Branch / PR:** main / #301 merged
- **Scope:** add the smallest durable AgentSwitchboard change that gives operators one local CLI to emanate/emulate merge-relevant GitHub Actions gates, preserving real app/host validators (not gate-gaming), and failing closed when the host cannot run a selected gate; includes manifest, Prove-MergeGateLocal.ps1, linux-hygiene twin, unittest, docs, registry update
- **Forbidden:** no force-push; no merge; no secrets; no cron; do not claim merge/release/deploy authority; do not rewrite unrelated path-filtered domain workflows; do not touch PR #300 / ASQ-016 preserve branch; never skip-as-pass; no merge authority claims
- **Dependencies:** ASQ-018 (Prove-AutomatedTestFloorLocal exists and is always-on)
- **References:** `.ai/harness/merge-gate-local.manifest.json`, `scripts/Prove-MergeGateLocal.ps1`, `scripts/Test-ApplicationFloorLinuxHygiene.ps1`, `tests/test_merge_gate_local.py`, `docs/harness/merge-gate-local.md`, `tooling/harness/operational/validator-registry.json`, `CODEBASE_MAP.md`
- **Acceptance gate:** Prove-AutomatedTestFloorLocal PASS; Prove-MergeGateLocal -ListOnly lists gates; Prove-MergeGateLocal PASS on clean tree; test_merge_gate_local unittest PASS with multiple tests; packet shows always-on PASS; simulated Windows-only gate on Linux → non-zero exit (not pass); proof ceiling text forbids merge authority; git diff --check clean
- **Gate:** none
- **Last proof:** merge:e999602 pr:#301; artifact:scripts/Prove-MergeGateLocal.ps1 artifact:scripts/Test-ApplicationFloorLinuxHygiene.ps1 artifact:tests/test_merge_gate_local.py artifact:docs/harness/merge-gate-local.md on main@e999602
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-17T20:00:00Z

## ASQ-021 — Persist product-pass posture public plan

- **Status:** DONE
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Cursor Cloud Agent / product-pass-posture plan coordination
- **Branch / PR:** main / #302 through #305 merged
- **Scope:** create durable product-pass posture public plan in `plans/active/ASB-2026-09-product-pass-posture.*` with schema validation; register plan in `plans/plan-registry.json`; encode waves PPP-01..06 with owned/forbidden scope, proof ceiling, and successor tasks; product pass = owning prove PASS + no flags (primary), forge merge = optional land-on-main (secondary)
- **Forbidden:** implementing PPP-03 AGENTS.md doctrine mutation yet; implementing Prove-ProductPassLocal yet; claiming Admin Box physical floor from planning; forcing merge/release/deploy; inventing scripts/prompt_parallel_dispatch.py as if already present
- **Dependencies:** ASQ-020 Prove-MergeGateLocal on main@e999602; ASQ-018 Prove-AutomatedTestFloorLocal completed
- **References:** `plans/active/ASB-2026-09-product-pass-posture.plan.json`, `plans/active/ASB-2026-09-product-pass-posture.md`, `plans/plan-registry.json`, `plans/schemas/public-plan.schema.json`, `docs/governance/repository-work-ledger-contract.md`, `scripts/Test-PublicPlanContracts.ps1`, `scripts/Test-RepositoryWorkLedgerContract.ps1`
- **Acceptance gate:** public plan validates with Test-PublicPlanContracts.ps1; plan-registry lists ASB-2026-09-PRODUCT-PASS-POSTURE; ledger contract passes; git diff --check clean; plan encodes product-pass vs forge-pass posture, waves, owned/forbidden scope, proof ceiling
- **Gate:** none
- **Last proof:** merge:ce78fc5 pr:#302 PPP-01+02; merge:16fc141 pr:#303 PPP-03; merge:64c8350 pr:#304 PPP-04; merge:684672f pr:#305 PPP-05; all tasks integrated on main@684672f
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-17T20:47:16Z

## ASQ-022 — Execute adapter trio v1 implementation waves

- **Status:** CLAIMED
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** execution-adapter shared-spine / convergence coordinator
- **Branch / PR:** main@59649d776bf3db8e73f0401f13a2b32b760892fa contains PR #335 contract floor; active writer PR #336 / `feat/eat-005-execution-adapter-registry-20260920` for EAT-005
- **Scope:** advance the frozen execution-adapter v1 contract into the executable generic adapter interface/registry/runner (EAT-005), preserve the legacy Triage receipt bridge, then open isolated local-argv, Claude Code, and Cursor CloudAgent implementation lanes according to the canonical public plan; EAT-301 PR #332 floor repair may proceed independently.
- **Forbidden:** overwriting PR #332-owned dispatch files before EAT-302 reconciliation; moving Prompt Kit semantics into adapters; creating a second crew scheduler; weakening the FirstMate crew-runtime ADR; inventing `scripts/prompt_parallel_dispatch.py`; interactive provider login; secrets/private runtime receipts; claiming native adapter runtime proof from registry/static CI alone.
- **Dependencies:** execution-adapter contract floor integrated on main (PR #335 / 59649d77…); EAT-301 independently depends only on PR #332 exact-head ownership.
- **References:** plan-id ASB-2026-09-EXECUTION-ADAPTER-TRIO-V1; `plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json`; `plans/active/ASB-2026-09-execution-adapter-trio-v1.md`; `tooling/harness/execution-adapters/execution-adapter-contract.v1.json`; `tooling/harness/execution-adapters/adapter_protocol.py`; `tooling/harness/execution-adapters/registry.py`; `tooling/harness/execution-adapters/runner.py`; `docs/harness/execution-adapter-contract-v1.md`; `scripts/Test-ExecutionAdapterContract.ps1`; PR #332; PR #336
- **Acceptance gate:** EAT-005 generic interface/registry/runner is integrated against the frozen request/receipt/capability contracts with focused tests; unknown/unready adapters fail closed; plan coordination advances local/Claude/Cursor tasks to dependency-ready states without shared-file collisions.
- **Gate:** none for EAT-005 start — contract floor is on main; PR #332 remains a separate writer until EAT-302; PR #336 must pass exact-head required checks before merge.
- **Last proof:** PR #335 merged to main@59649d77…; `Test-ExecutionAdapterContract.ps1` PASS on exact main worktree; legacy `dispatch_lanes.py` local-argv live protected-control observed (exit 0 marker + exit 42) under disposable `%TEMP%/asb-runtime-proof-59649d77`; DeepSeek harness path BLOCKED (empty nested reparse, `dsh` not on PATH); EAT-005 implementation pushed as PR #336 head 40bee8ee….
- **Next action:** repair PR #336 ledger/plan enum and path-reference contract failures, then merge #336 when exact-head gates are green and open EAT-006 + isolated EAT-101/EAT-201/EAT-302 lanes from refreshed main.
- **Updated:** 2026-09-20T22:40:00Z

## ASQ-023 — Factor closed-PR semantic salvage into bounded child work

- **Status:** DONE
- **Priority:** P0
- **Work class:** UNBOUNDED
- **Owner:** stale-PR salvage convergence coordinator
- **Branch / PR:** main / #339 merged
- **Scope:** refresh TRIAGE-01 against main@72d71a74279c5cf1b0c029b68d03c76634d50ea1, preserve #94/#338 proof, build the dependency/collision graph for #113/#112/#118/#64/#92/#79, and create bounded ledger children plus self-contained portability panels
- **Forbidden:** executing successor implementation inside this decomposition item; bulk merge/cherry-pick; destructive Git; inventing prompt-parallel-dispatch runtime/CLI; secrets/private paths; live runtime/provider claims
- **Dependencies:** PR #338 / main@72d71a74279c5cf1b0c029b68d03c76634d50ea1
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01.plan.json`, `plans/active/ASB-2026-09-stale-pr-triage-01.md`, `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md`
- **Acceptance gate:** TRIAGE-01 current floor and exact historical source SHAs refreshed; bounded children ASQ-024..ASQ-030 created with dependency/collision ownership; ASQ-031 routes the missing autonomous prompt-dispatch seam; plan/ledger validation green
- **Gate:** none
- **Last proof:** merge:67df85da2026104e00ff6bd7c926db0139ca4f63 pr:#339; exact validated candidate e2cebd81f0a928274e3b21df54a7f2fa0cde5869 had identical tree; artifact:plans/active/ASB-2026-09-stale-pr-triage-01.plan.json artifact:plans/active/ASB-2026-09-stale-pr-triage-01-panels.md; repository work-ledger contract and automated test floor passed on Windows and Ubuntu
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-22T17:27:00Z

## ASQ-024 — Salvage PR #113 OpenCode runtime-resolution

- **Status:** READY
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** strong salvage agent / OpenCode-Windows profile lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 01: semantically reconcile PR #113 head 2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9 with current opencode-lsp-setup, P67 evaluation adapter, and execution-adapter v1; implement only unique current-owner behavior and focused regressions
- **Forbidden:** wholesale SKILLS/TRIGGERS/CODEBASE_MAP/workflow replay; P67 or OpenCode LSP redesign; provider login; live proof promotion
- **Dependencies:** ASQ-023 DONE; PR #338/main floor integrated
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 01; `tooling/harness/operational/opencode-lsp-setup/`; `tooling/harness/execution-adapters/`; `plans/active/ASB-2026-09-p67-opencode-evaluation-adapter.plan.json`
- **Acceptance gate:** preserve/merge/retire matrix complete; unique behavior tested; current OpenCode/execution-adapter gates + automated floor + diff hygiene green; exact validated head integrated or exact blocker recorded
- **Gate:** none — dependency-ready on the recorded floor; refresh before mutation
- **Last proof:** PR #113 closed-unmerged; 13 unique commits / 23 files / 608 behind at main@72d71a7
- **Next action:** launch Panel 01 in an isolated worktree from refreshed main and verify source SHA 2ff3d81ab806b54dceccf593cd0f39b2c17e8bc9 before mutation
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-025 — Salvage PR #112 Lua embedding leaf

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** bounded lower-capability agent / Lua leaf lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 02: reconstruct the isolated tooling/lua harness, focused tests/docs, sandbox-safe positive fixture, and unsafe-OS-access negative fixture
- **Forbidden:** shared SKILLS/TRIGGERS/CODEBASE_MAP/global registries; claiming a Lua runtime/embedder exists or ran
- **Dependencies:** ASQ-023 DONE
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 02
- **Acceptance gate:** leaf validator/tests + automated floor + diff hygiene green; shared wiring left for ASQ-030
- **Gate:** none — dependency-ready on the recorded floor; refresh before mutation
- **Last proof:** PR #112 closed-unmerged head 3053e1898c1de351faf2215d72947f5bd5d880de; tooling/lua absent on main
- **Next action:** launch Panel 02 in an isolated worktree from refreshed main and verify source SHA 3053e1898c1de351faf2215d72947f5bd5d880de before mutation
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-026 — Salvage PR #118 external-agent tooling leaf

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** bounded lower-capability agent / external-tooling leaf lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 03: salvage only the external-agent-tooling evidence catalog leaf, closed schema, intake workflow, report, and focused regressions
- **Forbidden:** shared operational manifest/validator/workflow registries; treating catalogue presence as install/trust/privacy/execution proof
- **Dependencies:** ASQ-023 DONE
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 03; `tooling/harness/operational/`
- **Acceptance gate:** leaf tests/validator green; proof-promotion negatives retained; exact shared-registry delta handed to ASQ-030
- **Gate:** none — dependency-ready on the recorded floor; refresh before mutation
- **Last proof:** PR #118 closed-unmerged head 87abb4546ee1ef440897dfd86a49e58dab827ee6; 1 unique commit / 15 files / 608 behind
- **Next action:** launch Panel 03 in an isolated worktree from refreshed main and verify source SHA 87abb4546ee1ef440897dfd86a49e58dab827ee6 before mutation
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-027 — Forensically salvage PR #64 Windows machine-profile harness

- **Status:** READY
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** strong salvage agent / Windows machine-profile lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 04: separate PR-intended changes from inherited non-main base history, reconcile with current machine-profile/bootstrap/device-profile owners, and implement only unique current-owner behavior
- **Forbidden:** blind replay of 22 commits; duplicate machine-profile skill/launcher; operator-command-delivery rewrite; live workstation claims
- **Dependencies:** ASQ-023 DONE
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 04; `.ai/skills/machine-profile-bootstrap/SKILL.md`; `tooling/profiles/windows/harness/machine-profile/`
- **Acceptance gate:** merge-base/intended-vs-inherited matrix proven; current machine-profile/device-profile/Windows-profile gates green; exact candidate integrated or blocked with evidence
- **Gate:** none — dependency-ready on the recorded floor; refresh before mutation
- **Last proof:** PR #64 closed-unmerged head 45b44b158d7f44e18dfbc6c24120a0c02924f48b; historical base feat/harness-operator-command-envelope-20260805; 732 behind
- **Next action:** launch Panel 04 in an isolated worktree from refreshed main and reconstruct the PR-intended delta before any cherry-pick or code copy
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-028 — Reconcile PR #92 execution-actor routing with adapter v1

- **Status:** BLOCKED
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** strong salvage agent / execution-adapter reconciliation lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 05 after ASQ-026: compare old actor-binding/router invariants to current execution-adapter request/receipt/capability model; retire superseded lifecycle and preserve only missing current-owner invariants/tests
- **Forbidden:** restoring a competing execution router/scheduler; wholesale operational registry/HARNESS replay; provider dispatch claims
- **Dependencies:** ASQ-026 integrated or proved no-change; ASQ-022 is terminal OR has durably handed off disjoint execution-adapter file ownership to ASQ-028
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 05; `plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json`; `tooling/harness/execution-adapters/`
- **Acceptance gate:** explicit superseded/preserve matrix; any preserved invariant lands in current owner with focused negative/positive tests; adapter floor green
- **Gate:** BLOCKED_OWNERSHIP — do not mutate execution-adapter paths while ASQ-022 remains an overlapping active writer; require terminal state or explicit durable disjoint-file handoff
- **Last proof:** PR #92 closed-unmerged head acc652d5dc7599b18d76983fb96dbd628d2bd759; current main has execution-adapter v1 absent from August branch
- **Next action:** verify ASQ-026 terminal disposition and inspect ASQ-022; launch Panel 05 only after ASQ-022 is terminal or explicitly hands off disjoint execution-adapter paths
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-029 — Reconcile PR #79 agent-fleet readiness after machine-profile salvage

- **Status:** BLOCKED
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** strong salvage agent / fleet-readiness lane
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 06 after ASQ-027: compare fleet-readiness semantics with the post-#64 current machine-profile, Windows profile, launcher, and adapter readiness owners; preserve only unique leaf readiness logic/tests
- **Forbidden:** second machine-profile/bootstrap lifecycle; independent CMD lifecycle/fallback logic; shared CODEBASE_MAP writes; live fleet claims
- **Dependencies:** ASQ-027 integrated or proved no-change
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 06
- **Acceptance gate:** readiness semantic matrix complete; unique behavior tested; current machine-profile and Windows-profile gates remain green; integrated/no-change disposition recorded
- **Gate:** dependency-gated; do not mutate until named dependency is proven
- **Last proof:** PR #79 closed-unmerged head b3560cd56e98f7b91dfff2e060c8a27d1c76e76a; 36 unique commits / 701 behind
- **Next action:** launch Panel 06 only after ASQ-027 establishes the current machine-profile owner and refresh the source/main SHAs before mutation
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-030 — Converge closed-PR salvage lanes and shared wiring

- **Status:** BLOCKED
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** salvage convergence coordinator / single writer
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** execute Panel 07 after ASQ-024..ASQ-029: rejoin validated candidates in dependency order, apply shared skill/trigger/map/registry wiring once, run combined proof, merge exact heads, and update TRIAGE-01/ledger with terminal dispositions
- **Forbidden:** overwriting unfinished workers; shared-file parallel writes; deleting historical branches before preservation proof; unrelated features; gate weakening
- **Dependencies:** ASQ-024, ASQ-025, ASQ-026, ASQ-027, ASQ-028, ASQ-029 each integrated, no-change, or exactly blocked
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01-panels.md` Panel 07; `plans/active/ASB-2026-09-stale-pr-triage-01.plan.json`; `scripts/Prove-MergeGateLocal.ps1`
- **Acceptance gate:** refreshed-main dependency-order convergence; focused validators + public plan/work ledger/agent docs/automated floor/merge-gate where executable + diff hygiene green; containment/content proof on main; preserved branch state reported
- **Gate:** dependency-gated; do not mutate until named dependency is proven
- **Last proof:** not executable yet; dependencies are intentionally isolated to prevent shared-wiring collisions
- **Next action:** launch Panel 07 after all six salvage children have supported terminal dispositions and re-fetch main before integration
- **Updated:** 2026-09-22T17:16:30Z

## ASQ-031 — Decide and route typed prompt-parallel dispatch ownership

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** execution-adapter shared-spine successor / ASQ-022 owner
- **Branch / PR:** none yet; create isolated branch/worktree from refreshed main when this item becomes executable
- **Scope:** inspect whether AgentSwitchboard should own the prompt-parallel-dispatch manifest/runner requested by orchestration prompts; if yes, design it as an execution-adapter v1 consumer/adapter rather than a second scheduler; if no, record the canonical external owner
- **Forbidden:** implementing a second FirstMate crew scheduler; inventing runtime_tool proof; creating Outputs/prompt-parallel-dispatch/manifest.json without a canonical contract/validator; making TRIAGE-01 depend on this enhancement
- **Dependencies:** ASQ-022 current execution-adapter state reconciled by its owner
- **References:** `plans/active/ASB-2026-09-stale-pr-triage-01.plan.json`; `tooling/harness/execution-adapters/`; `plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json`
- **Acceptance gate:** one canonical ownership decision; if kept, typed schema/validator/runner/receipt semantics compose with adapter v1 and prove observed parallelism; if rejected, durable route points to the actual owner
- **Gate:** dependency-gated; do not mutate until named dependency is proven
- **Last proof:** repository search on main@72d71a7 found no harness/contracts/prompt-parallel-dispatch.v1.json, scripts/prompt_parallel_dispatch.py, or Outputs/prompt-parallel-dispatch owner; current chat exposes no local worker runtime
- **Next action:** inspect ASQ-022 and execution-adapter v1 current main, then record KEEP-IN-ASB or ROUTE-ELSEWHERE before any prompt-parallel-dispatch implementation
- **Updated:** 2026-09-22T17:16:30Z
