contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# AgentSwitchboard shared work ledger

This is the canonical coordination ledger for unfinished AgentSwitchboard repository work. It routes work; it does not replace `AGENTS.md`, source code, plans, validators, PRs, CI, or runtime evidence. Read `docs/governance/repository-work-ledger-contract.md` before changing ledger semantics.

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Work class is required by the AgentSwitchboard local execution profile.
Use `pwsh -NoLogo -NoProfile -File scripts/Get-RepositoryWorkLedgerFrontier.ps1 -Json` to select the compact actionable frontier instead of rereading the full ledger.
Canonical terminal action: none; no safe actionable work remains

## ASQ-001 — Adopt repository work ledger across the priority repository family

- **Status:** BLOCKED
- **Priority:** P1
- **Work class:** UNBOUNDED
- **Owner:** chatgpt-cross-repo-ledger-20260809
- **Branch / PR:** feat/repository-work-ledger-20260809 / #105
- **Scope:** factor the portable AxTask queue insight into AgentSwitchboard as canonical family contract, create AgentSwitchboard local ledger/validator/CI, and provide a bounded triage consumer adoption
- **Forbidden:** changing AxTask domain behavior; copying AxTask recovery/deployment tasks; product feature changes; implicit AgentSwitchboard hook installation; claiming runtime proof from ledger metadata
- **Dependencies:** external consumer-repository adoption proof
- **References:** `AGENTS.md`, `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`
- **Acceptance gate:** AgentSwitchboard contract, local ledger, validator, negative/positive tests, and CI are tracked on one branch; triage has a repository-local adoption pinned to the exact AgentSwitchboard contract commit; both PR heads pass their owned ledger checks or exact CI gaps are recorded
- **Gate:** AgentSwitchboard PR #105 is merged and its ledger workflow passed, but the external triage consumer adoption proof is not represented by a durable reference in this repository ledger
- **Last proof:** merge:62acecf4a590ecadf4a0b1ad1410e659b4e1b650 merged PR #105; workflow:31331594284 passed the AgentSwitchboard ledger contract; artifact:.ai/harness/repository-work-ledger-adoption.json records donor commit and authority boundary
- **Next action:** verify the triage consumer adoption and record its durable PR, commit, workflow, or artifact reference before marking this cross-repository parent DONE
- **Updated:** 2026-08-09T19:31:00Z

## ASQ-002 — Add bounded execution classes and compact frontier routing

- **Status:** VERIFY
- **Priority:** P1
- **Work class:** BOUNDED
- **Owner:** chatgpt-ledger-execution-frontier-20260809
- **Branch / PR:** feat/repository-ledger-execution-frontier-20260809 / pending
- **Scope:** strengthen the AgentSwitchboard ledger with BOUNDED versus UNBOUNDED classification, derive EXECUTE versus DECOMPOSE routes, add a compact highest-priority frontier reader, and enforce anti-rumination semantics with tests and CI
- **Forbidden:** changing the immutable portable v1 required-field set; forcing the local execution profile onto existing consumer repositories; product behavior changes; Wayfinder implementation changes; implicit hooks; claiming runtime task completion from ledger metadata
- **Dependencies:** ASQ-001 portable v1 contract merged on main
- **References:** `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`, `scripts/Test-RepositoryWorkLedgerContract.ps1`, `scripts/Get-RepositoryWorkLedgerFrontier.ps1`, `tests/test_repository_work_ledger_contract.py`, `tests/test_repository_work_ledger_frontier.py`
- **Acceptance gate:** the local validator rejects missing/invalid work classes and monolithic UNBOUNDED implementation states; READY UNBOUNDED work must create bounded children; the frontier deterministically selects the highest-priority actionable task and derives EXECUTE or DECOMPOSE; Windows and Ubuntu CI pass
- **Gate:** none
- **Last proof:** artifact:scripts/Get-RepositoryWorkLedgerFrontier.ps1 and artifact:.ai/harness/repository-work-ledger.policy.json are tracked on the sprint branch
- **Next action:** run the ledger validator plus both focused Python suites, inspect the exact-head Windows and Ubuntu workflow, and repair any owned failure before review
- **Updated:** 2026-08-09T19:31:00Z
