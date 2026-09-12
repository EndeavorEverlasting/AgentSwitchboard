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
- **Owner:** coordination lane
- **Branch / PR:** main
- **Scope:** maintain the durable September program in `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json` + `.md`, `plans/plan-registry.json`, and `.ai/WORK_QUEUE.md`; keep current collision/disposition evidence for merged PR #151, merged PR #149, and stale PR #115
- **Forbidden:** product/bootstrap implementation, Pi/OpenCode adapter code, LSP behavior mutation, provider credentials, destructive Git, rewriting merged history, closing PR #115 before supersession proof, committing private local/tenant paths or runtime receipts
- **Dependencies:** none
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `plans/active/ASB-2026-09-agent-bootstrap-child-bus.md`, `plans/plan-registry.json`, `.ai/WORK_QUEUE.md`, `docs/governance/repository-work-ledger-contract.md`, `scripts/Test-PublicPlanContracts.ps1`, `scripts/Test-RepositoryWorkLedgerContract.ps1`
- **Acceptance gate:** coordination floor commit `38fd434ed7496413a33e1143d9cbb381849d81de` remains contained on current main; plan/ledger encode current waves/dependencies/collision/proof ceilings and current PR states; tracked public coordination is free of private absolute Windows user paths and tenant-labelled sync paths; plan/ledger/privacy validators pass
- **Gate:** none
- **Last proof:** commit:38fd434ed7496413a33e1143d9cbb381849d81de coordination-floor integration from provider floor 54cce3b824a982e26595efa8ed5060e555411693; merge:1f20499d5771456c9ce88da67eced345899928fa PR #151; merge:3b47a9129730bc8fc3c988f8cbc6ec2fbfa515d8 PR #149; reconciliation-floor:main@d5a1bb4ee46135060e4fbfed467665d2c84f5412
- **Next action:** none; no safe actionable work remains for the coordination-floor item itself
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-005 — OpenCode fresh-TUI LSP runtime certification

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 02 OpenCode LSP lane
- **Branch / PR:** main
- **Scope:** resolve final Python LSP runtime proof by fresh TUI vs headless `20260912T194619Z-e3f423df`; write local `opencode-lsp-runtime-smoke.json/.md` beneath the registered local evidence root with `nonLspSemanticFallbackUsed No` and verbatim errors
- **Forbidden:** tracked harness mutation unless TUI exposes a reproducible product defect; non-LSP grep/search semantic fallback; changing existing operator config; confidential data on free endpoints; committing runtime receipts
- **Dependencies:** ASQ-004
- **References:** `docs/harness/opencode-lsp-workstation-setup.md`, `tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json`, `tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md`, `scripts/Test-OpenCodeLspHarness.ps1`
- **Acceptance gate:** fresh TUI launched from the current canonical checkout with `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`, `tests/test_technician_live_cert_surface.py` opened, strict hover/definition/references captured with `nonLspSemanticFallbackUsed No`; compare with headless e3f423df; validate the local receipt
- **Gate:** none
- **Last proof:** artifact:tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json artifact:tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md; headless runtime receipt e3f423df remains a FAIL ceiling, not a TUI result
- **Next action:** resolve the current canonical checkout through `AGENT_SWITCHBOARD_REPO` or the machine-profile default, launch a fresh OpenCode TUI with `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`, open `tests/test_technician_live_cert_surface.py`, and capture hover/definition/references verbatim with no semantic fallback
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-006 — Pi reversible system bootstrap lifecycle

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 03 Pi bootstrap lane
- **Branch / PR:** main
- **Scope:** refactor the Pi system bootstrap now merged from PR #151 into the shared reversible `Inspect/Apply/Remove` lifecycle; add `Unbootstrap-Pi-SystemWide.cmd`; register Pi in the shared lifecycle adapter registry
- **Forbidden:** generic child-bus contract work, OpenCode LSP harness, provider credentials/settings/sessions, merged path-authority redesign, arbitrary package-manager dependency, destructive Git
- **Dependencies:** ASQ-004
- **References:** `tooling/pi/Install-AgentSwitchboardPiSystem.ps1`, `Bootstrap-Pi-SystemWide.cmd`, `tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json`, `tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1`, `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`, `merge:1f20499d5771456c9ce88da67eced345899928fa`
- **Acceptance gate:** Pi registered in `adapters.v1.json`; Inspect/Apply/Remove use durable ownership, write-ahead intent, drift fail-closed semantics and resumable Remove checkpoints; credentials/settings/sessions/project trust remain user-owned
- **Gate:** none
- **Last proof:** merge:1f20499d5771456c9ce88da67eced345899928fa placed Pi bootstrap on main, but current lifecycle registry still contains only the OpenCode reference adapter, so Pi lifecycle parity is not yet proven
- **Next action:** implement Pi lifecycle parity from current main in an isolated worktree and validate against the shared lifecycle contract
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-007 — Shared ASB child bus v1 contract spine

- **Status:** READY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 04 shared child-bus lane
- **Branch / PR:** main
- **Scope:** create provider-neutral `tooling/harness/child-agent-bus/` with request/result/error schemas, adapter registry, artifact registry, fixtures, validator, generic dispatcher, docs, CI and canonical capability/trigger routing
- **Forbidden:** Pi/OpenCode CLI invocation details, provider calls, credentials, actual child runtime, Pi fusion product logic, direct pairwise agent config, system-bootstrap lifecycle mutation, default-branch child writers
- **Dependencies:** ASQ-004
- **References:** `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/manifest.json`, `docs/governance/harness-doctrine.md`, `tooling/pi/harness/child-agent-invocation.contract.json`
- **Acceptance gate:** provider-neutral closed schemas define invocation lineage/authority/budgets/evidence root; generic dispatcher fails closed when adapter absent; common fixture matrix covers read-only, isolated writer, dirty/default branch/base-SHA mismatch, budget exhaustion, timeout and missing terminal event
- **Gate:** none
- **Last proof:** current main contains the merged Pi-private child contract, but `tooling/harness/child-agent-bus/` is absent; the common bus remains unimplemented
- **Next action:** create an isolated current-main worktree for `feat/child-agent-bus-v1-20260912` and implement the shared bus contracts with deterministic fixtures
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-008 — Pi child adapter conformance

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 05 Pi adapter lane
- **Branch / PR:** main
- **Scope:** migrate the current merged Pi-private child execution behind the provider-neutral shared bus: register Pi adapter, retain launch/event/cancellation translation, read-only and isolated writer paths, and rewire Pi orchestration guidance
- **Forbidden:** redefining common request/result fields, redefining lifecycle, OpenCode adapter, direct pairwise agent calls, persistent RPC, provider fallback, main/default-branch child writer
- **Dependencies:** ASQ-006, ASQ-007
- **References:** `tooling/pi/Invoke-AgentSwitchboardPiChild.ps1`, `tooling/pi/harness/child-agent-invocation.contract.json`, `tooling/pi/harness/`, `tooling/harness/child-agent-bus/`
- **Acceptance gate:** Pi conforms to the shared bus, resolves only the ASB-managed runtime, preserves read-only/isolation guards, requires terminal `agent_end`, and obeys common budgets/evidence uniqueness
- **Gate:** ASQ-006 and ASQ-007 are not yet DONE — Pi lifecycle and shared bus must be ancestors of main
- **Last proof:** merge:1f20499d5771456c9ce88da67eced345899928fa supplies the current private Pi child seam only
- **Next action:** after ASQ-006/007 complete, map the merged Pi-private fields to the common bus in an isolated lane
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-009 — OpenCode child adapter parity

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 06 OpenCode adapter lane
- **Branch / PR:** main
- **Scope:** add OpenCode as the second shared-bus adapter using the managed OpenCode runtime and the same common conformance fixtures
- **Forbidden:** OpenCode LSP harness redesign, Pi adapter, common schema semantic changes unless a provider-neutral defect is proven, pairwise agent config, global config mutation, provider fallback
- **Dependencies:** ASQ-007
- **References:** `tooling/harness/child-agent-bus/`, `tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1`
- **Acceptance gate:** OpenCode consumes the same request and produces the same result/error envelopes as Pi; exact managed runtime identity; no arbitrary PATH fallback
- **Gate:** ASQ-007 is not yet DONE — shared bus must be on main
- **Last proof:** none
- **Next action:** after ASQ-007 completes, implement OpenCode adapter parity against the shared conformance suite
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-010 — Heterogeneous read-only pilot (Pi + OpenCode)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 07 runtime pilot lane
- **Branch / PR:** main
- **Scope:** first real shared-bus session with Pi and OpenCode together, zero writers, distinct invocation IDs/evidence roots, budgets, and repository before/after identity
- **Forbidden:** repository mutation, writer tools, provider/model fallback, credentials in artifacts, direct cross-agent spawning, persistent RPC, nested delegation
- **Dependencies:** ASQ-008, ASQ-009
- **References:** `tooling/harness/child-agent-bus/`, `tooling/pi/harness/`
- **Acceptance gate:** Pi architect + OpenCode validator dispatched through ASB, terminal completion required, repository unchanged, coordinator rejoin records consensus/divergence
- **Gate:** ASQ-008 and ASQ-009 are not yet DONE — both adapters must conform
- **Last proof:** none
- **Next action:** after both adapters complete, build two independent read-only packets through the common ASB front door
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-011 — Mediated nested delegation v1 (maxDepth 2)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 08 shared bus lane
- **Branch / PR:** main
- **Scope:** add bounded child→ASB→grandchild delegation with lineage, budget inheritance, cancellation cascade, maxDepth=2, maxChildrenPerInvocation=3 and one writer globally
- **Forbidden:** direct cross-agent subprocesses, unlimited recursion, multiple concurrent writers, child merge/push, automatic retries, silent fallback, persistent RPC
- **Dependencies:** ASQ-010
- **References:** `tooling/harness/child-agent-bus/`
- **Acceptance gate:** authority only narrows downward; maxDepth=2; maxChildrenPerInvocation=3; maxConcurrentWriters=1; attempts=1; no fallback; deterministic scope/budget/cancellation fixtures green
- **Gate:** ASQ-010 is not yet DONE — heterogeneous pilot must PASS
- **Last proof:** none
- **Next action:** after the pilot passes, implement nested lineage/budget inheritance with deterministic fixtures
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-012 — Nested runtime certification (depth-2 chain)

- **Status:** BLOCKED
- **Priority:** P2
- **Work class:** BOUNDED
- **Owner:** Panel 09 runtime certification lane
- **Branch / PR:** main
- **Scope:** prove one bounded heterogeneous depth-2 chain with lineage, inherited budgets, independent evidence roots, terminal propagation and unchanged repository state
- **Forbidden:** writer children, depth>2, more than 3 children per invocation, direct cross-agent subprocess, automatic retries/fallback, persistent RPC, repository mutation, secrets
- **Dependencies:** ASQ-011
- **References:** `tooling/harness/child-agent-bus/`
- **Acceptance gate:** parent/root lineage proven; grandchild scope <= child <= root; budgets narrowed; independent evidence roots; terminal propagation; repository unchanged
- **Gate:** ASQ-011 is not yet DONE — nested delegation contract must be on main
- **Last proof:** none
- **Next action:** after ASQ-011 completes, submit one bounded read-only depth-2 request through ASB
- **Updated:** 2026-09-12T22:39:32Z

## ASQ-013 — PR/path authority cleanup and final convergence

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** Panel 10 convergence lane
- **Branch / PR:** main
- **Scope:** reconcile merged PR #151 behavior into the reversible lifecycle/shared-bus successors, reconcile merged PR #149 path authority with the current operator workflow without history rewrite, prove PR #115 superseded before closing it, then close the September plan/work ledger to terminal states
- **Forbidden:** closing unrelated PRs, deleting preserved worktrees without proof, force operations, rewriting merged history, deleting preserved noncanonical checkouts, new feature implementation, lowering proof gates
- **Dependencies:** ASQ-005, ASQ-006, ASQ-007, ASQ-008, ASQ-009, ASQ-010, ASQ-011, ASQ-012
- **References:** `plans/active/ASB-2026-09-agent-bootstrap-child-bus.plan.json`, `.ai/WORK_QUEUE.md`, `merge:1f20499d5771456c9ce88da67eced345899928fa`, `merge:3b47a9129730bc8fc3c988f8cbc6ec2fbfa515d8`, `PR #115`, `tooling/harness/system-bootstrap-lifecycle/`
- **Acceptance gate:** Pi lifecycle + shared-bus successors cover the intended merged #151 behavior; #149 path-authority behavior is reconciled without destructive path changes; #115 old LSP owner is closed only after current-main containment proof; September plan/ledger terminal states have ancestor checks
- **Gate:** ASQ-005 through ASQ-012 are not all DONE — implementation/runtime successors remain
- **Last proof:** merge:1f20499d5771456c9ce88da67eced345899928fa PR #151; merge:3b47a9129730bc8fc3c988f8cbc6ec2fbfa515d8 PR #149; PR #115 remains open at 39fd59df15857127ace8814ef03eabbd7b4d53c7
- **Next action:** after ASQ-005 through ASQ-012 are dispositioned, prove successor containment and PR #115 supersession, then close the September coordination program
- **Updated:** 2026-09-12T22:39:32Z
