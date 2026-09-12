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

## ASQ-001 ΓÇö Initial repository work ledger adoption

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

## ASQ-002 ΓÇö Add bounded execution classes and compact frontier routing

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

## ASQ-003 ΓÇö Reconcile portable ledger authority to BlacksmithGuild

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

## ASQ-004 ΓÇö September coordination floor: bootstrap + child bus program

- **Status:** DONE
- **Priority:** P0
- **Work class:** BOUNDED
- **Owner:** Admin Box 1
- **Branch / PR:** main
- **Scope:** create durable September program in `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json` + `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, update `plans/plan-registry.json`, add bounded work items for Panels 02ΓÇô10, record collision ledger for PR #151 Pi mixed, PR #149 path authority, PR #115 stale LSP
- **Forbidden:** product/bootstrap implementation, Pi/OpenCode adapter code, LSP behavior mutation, provider credentials, destructive Git, closing PR #151/#149/#115 before successor containment, committing private OneDrive/Northwell paths or runtime receipts
- **Dependencies:** none
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, `plans/plan-registry.json`, `.ai/WORK_QUEUE.md`, `docs/governance/repository-work-ledger-contract.md`, `scripts/Test-PublicPlanContracts.ps1`, `scripts/Test-RepositoryWorkLedgerContract.ps1`, `AGENTS.md`
- **Acceptance gate:** provider floor refreshed to `main@54cce3b` (parent `2f69049`, LSP runtime-smoke contract intact, `81461e7` lifecycle already beneath main); September plan accurately encodes 10-panel program with waves/dependencies/collision/proof ceilings; plan registry and ledger updated with only public-safe data; no private path committed; PR #151 source material, #149 waiting, #115 stale dispositions recorded; plan/ledger validators pass
- **Gate:** none
- **Last proof:** commit:54cce3b824a982e26595efa8ed5060e555411693 provider floor `main@54cce3b` parent `2f69049`; artifact:plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json artifact:plans/active/ASB-2026-09-agent-bootstrap-child-bus.md artifact:plans/plan-registry.json artifact:.ai/WORK_QUEUE.md
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-005 ΓÇö OpenCode fresh-TUI LSP runtime certification

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 02 OpenCode LSP lane
- **Branch / PR:** main
- **Scope:** resolve final Python LSP runtime proof by fresh TUI vs headless `20260912T194619Z-e3f423df`; write local `opencode-lsp-runtime-smoke.json/.md` beneath `%LOCALAPPDATA%/AgentSwitchboard/opencode-lsp/runs/<run-id>/` with `nonLspSemanticFallbackUsed No` and verbatim errors
- **Forbidden:** tracked harness mutation unless TUI exposes reproducible product defect; non-LSP grep/search semantic fallback; changing `OPENCODE_CONFIG`; free-model confidential data; committing runtime receipts
- **Dependencies:** ASQ-004
- **References:** `docs/harness/opencode-lsp-workstation-setup.md`, `tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json`, `tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md`, `scripts/Test-OpenCodeLspHarness.ps1`
- **Acceptance gate:** fresh TUI launched from canonical Live checkout with `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`, `tests/test_technician_live_cert_surface.py` opened, strict hover/def/refs captured with `nonLspSemanticFallbackUsed No`; comparison with headless `e3f423df` yields `PASS_TUI_HEADLESS_DIFFERENTIAL` or `FAIL_BOTH_MODES` etc.; receipt validated
- **Gate:** none
- **Last proof:** artifact:tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json artifact:tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md
- **Next action:** run fresh TUI smoke: Set-Location "C:\Users\pa_rperez26\OneDrive - Northwell Health\OG Laptop Backup\Desktop\dev\AgentSwitchBoard-Live"; $env:OPENCODE_EXPERIMENTAL_LSP_TOOL="true"; opencode (open tests/test_technician_live_cert_surface.py and capture hover/def/refs verbatim)
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-006 ΓÇö Pi reversible system bootstrap lifecycle

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 03 Pi bootstrap lane
- **Branch / PR:** main
- **Scope:** salvage Pi system-bootstrap portion of PR #151 `8d40604e` onto current main and make Pi a reversible `Inspect/Apply/Remove` adapter via `tooling/harness/system-bootstrap-lifecycle/` with `Bootstrap-Pi-SystemWide.cmd` + `Unbootstrap-Pi-SystemWide.cmd` + `tooling/pi/Install-AgentSwitchboardPiSystem.ps1`
- **Forbidden:** Pi child-agent request/result, generic ASB child-bus contracts, OpenCode LSP harness, provider credentials, PR #149 path-policy semantics, arbitrary npm dependency, destructive Git
- **Dependencies:** ASQ-004
- **References:** `tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json`, `tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1`, `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`, `PR #151 head 8d40604e`
- **Acceptance gate:** Pi registered in `adapters.v1.json` without redesigning shared contract; `Inspect/Apply/Remove` parity via lifecycle module, state under `%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\pi`, preserves credentials/settings/sessions, fails closed on drift, recovers interrupted Remove
- **Gate:** none
- **Last proof:** merge:81461e7 lifecycle reference OpenCode already beneath main; artifact:tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json
- **Next action:** create isolated worktree from origin/main and implement Pi Inspect/Apply/Remove with write-ahead and resumable rollback checkpoints
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-007 ΓÇö Shared ASB child bus v1 contract spine

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 04 shared child-bus lane
- **Branch / PR:** main
- **Scope:** create provider-neutral `tooling/harness/child-agent-bus/` with `child-agent-request.v1`, `child-agent-result.v1`, `child-agent-error.v1`, adapter registry, artifact registry, fixtures, validator, generic `Invoke-AgentSwitchboardChild` front door, docs, CI, capabilities `agent.child.dispatch` etc.
- **Forbidden:** Pi/OpenCode CLI invocation, provider calls, credentials, actual child runtime, Pi fusion product logic, direct agent-to-agent pairwise config, system-bootstrap lifecycle mutation, default-branch child writers
- **Dependencies:** ASQ-004
- **References:** `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/manifest.json`, `docs/governance/harness-doctrine.md`, `tooling/harness/child-agent-bus/`
- **Acceptance gate:** closed schemas with invocationId/lineage/authority/budgets/evidence root, generic dispatcher fails closed when adapter absent, validator + fixture matrix (read-only, isolated writer, dirty/default-branch/base-SHA mismatch, budget exceeded etc.) green, hub-and-spoke `parent ΓåÆ ASB ΓåÆ adapter ΓåÆ child` enforced
- **Gate:** none
- **Last proof:** artifact:.ai/harness/manifest.json
- **Next action:** create isolated branch/worktree `feat/child-agent-bus-v1-20260912` from origin/main and implement shared bus contracts with deterministic fixtures
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-008 ΓÇö Pi child adapter conformance

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 05 Pi adapter lane
- **Branch / PR:** main
- **Scope:** migrate Pi child-execution from PR #151 behind shared bus: Pi adapter registered, launch/event/cancellation translation, read-only and isolated writer paths, `pi-fusion-orchestration` skill rewire
- **Forbidden:** redefining common request/result fields, redefining lifecycle, OpenCode adapter, pairwise PiΓåÆOpenCode calls, persistent RPC, provider fallback, main/default-branch child writer
- **Dependencies:** ASQ-006, ASQ-007
- **References:** `tooling/harness/child-agent-bus/`, `tooling/pi/harness/`, `PR #151 Invoke-AgentSwitchboardPiChild.ps1`
- **Acceptance gate:** Pi is first conforming implementation of shared bus, resolves only ASB-managed Pi runtime, read-only/isolation guards, terminal `agent_end` required, budgets and evidence uniqueness enforced, generic fixtures green
- **Gate:** ASQ-006 and ASQ-007 not yet DONE ΓÇö Pi lifecycle and shared bus must be ancestors of main
- **Last proof:** none
- **Next action:** verify Panel 03 and 04 are ancestors of main, then map PR #151 private fields to common bus in isolated lane
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-009 ΓÇö OpenCode child adapter parity

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 06 OpenCode adapter lane
- **Branch / PR:** main
- **Scope:** add OpenCode as second bus adapter with parity to Pi: managed runtime resolution via ASB state, launch/event translation, same conformance fixtures, registry entry
- **Forbidden:** OpenCode LSP harness redesign, Pi adapter, common schema semantic changes unless defect proved, pairwise Pi/OpenCode config, global OPENCODE_CONFIG mutation, provider fallback
- **Dependencies:** ASQ-007
- **References:** `tooling/harness/child-agent-bus/`, `tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1`
- **Acceptance gate:** OpenCode consumes same request and produces same result/error envelopes as Pi; exact managed runtime, no PATH fallback, conformance matrix green
- **Gate:** ASQ-007 not yet DONE ΓÇö shared bus must be on main
- **Last proof:** none
- **Next action:** verify child bus is ancestor of main, then implement OpenCode adapter reusing managed runtime identity
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-010 ΓÇö Heterogeneous read-only pilot (Pi + OpenCode)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 07 runtime pilot lane
- **Branch / PR:** main
- **Scope:** first real ASB child-bus session with Pi and OpenCode together, zero writers, distinct invocationIds/evidence roots, budgets, repo before/after identity
- **Forbidden:** repository mutation, writer tools, provider/model fallback, credentials in artifacts, direct PiΓåöOpenCode spawning, persistent RPC, nested delegation
- **Dependencies:** ASQ-008, ASQ-009
- **References:** `tooling/harness/child-agent-bus/`, `tooling/pi/harness/`
- **Acceptance gate:** Pi architect + OpenCode validator dispatched via ASB concurrently, terminal completion required, repo unchanged, coordinator rejoin with consensus/divergence
- **Gate:** ASQ-008 and ASQ-009 not yet DONE ΓÇö both adapters must be conforming
- **Last proof:** none
- **Next action:** verify Pi and OpenCode adapters are ancestors, then build two independent read-only packets through ASB front door
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-011 ΓÇö Mediated nested delegation v1 (maxDepth 2)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 08 shared bus lane
- **Branch / PR:** main
- **Scope:** add bounded childΓåÆASBΓåÆgrandchild delegation: lineage, budget inheritance, cancellation cascade, depth 3 child-count limits, one writer globally, fixtures for scope widening/write escalation/depth exceeded
- **Forbidden:** direct PiΓåöOpenCode subprocess, unlimited recursion, multiple concurrent writers, child merge/push, automatic retries, silent fallback, persistent RPC
- **Dependencies:** ASQ-010
- **References:** `tooling/harness/child-agent-bus/`
- **Acceptance gate:** maxDepth=2, maxChildrenPerInvocation=3, maxConcurrentWriters=1, attempts=1, no fallback, childMayMerge false, authority only narrows downward, fixtures green, deterministic state machine proof
- **Gate:** ASQ-010 not yet DONE ΓÇö heterogeneous pilot must PASS
- **Last proof:** none
- **Next action:** verify pilot runtime artifact, then implement nested lineage/budget inheritance with fixtures
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-012 ΓÇö Nested runtime certification (depth-2 chain)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 09 runtime certification lane
- **Branch / PR:** main
- **Scope:** prove one bounded heterogeneous depth-2 chain (coordinator ΓåÆ Pi read-only ΓåÆ ASB-mediated OpenCode read-only or reverse) with lineage, inherited budgets, evidence roots, repo unchanged
- **Forbidden:** writer children, depth>2, >3 children per invocation, direct cross-agent subprocess, automatic retries/fallback, persistent RPC, repository mutation, secrets
- **Dependencies:** ASQ-011
- **References:** `tooling/harness/child-agent-bus/`
- **Acceptance gate:** depth and parent/root lineage proven, grandchild scope <= child <= root, budgets inherited/narrowed, independent evidence roots, terminal propagation, repo before/after unchanged
- **Gate:** ASQ-011 not yet DONE ΓÇö nested delegation contract must be on main
- **Last proof:** none
- **Next action:** verify nested delegation contract is ancestor, then submit one bounded read-only depth-2 request through ASB
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-013 ΓÇö PR/path authority cleanup and final convergence

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 10 convergence lane
- **Branch / PR:** main
- **Scope:** reconcile superseded PR #151 Pi mixed, #115 stale LSP harness, #149 draft path authority; close/supersede with containment proof after successors integrated; close September plan/work-ledger to terminal states
- **Forbidden:** closing unrelated PRs, deleting worktrees without proof, force operations, silently invalidating explicit operator OneDrive path, new feature implementation, lowering proof gates
- **Dependencies:** ASQ-005, ASQ-006, ASQ-007, ASQ-008, ASQ-009, ASQ-010, ASQ-011, ASQ-012
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `.ai/WORK_QUEUE.md`, `PR #151`, `PR #115`, `PR #149`, `tooling/harness/system-bootstrap-lifecycle/`
- **Acceptance gate:** PR #151 Pi lifecycle + Pi child-adapter successor SHAs proved contained in main before superseded close; #115 old LSP harness proved superseded by current main LSP proof; #149 only missing explicit operator path wins extracted via bounded patch otherwise superseded; September plan and work ledger closed to terminal states with ancestor checks
- **Gate:** ASQ-005 through ASQ-012 not yet DONE ΓÇö all implementation/runtime successors must be dispositioned
- **Last proof:** none
- **Next action:** refresh main and all three PRs, prove containment of successor SHAs, then close as superseded with successor references
- **Updated:** 2026-09-12T19:55:00Z

## ASQ-014 — Build optional opinion-ledger tracer (experimental)

- **Status:** READY
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** opinion-ledger lane
- **Branch / PR:** feat/opinion-ledger-tracer-20260909 / #146
- **Scope:** add operational-harness tracer that records/searches local-only candidate opinions with advisory-only semantics
- **Next action:** validate via tests/test_opinion_ledger_tracer.py
- **Updated:** 2026-09-12T22:00:00Z

