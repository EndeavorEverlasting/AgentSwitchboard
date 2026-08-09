contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# AgentSwitchboard shared work ledger

This is the canonical coordination ledger for unfinished AgentSwitchboard repository work. It routes work; it does not replace `AGENTS.md`, source code, plans, validators, PRs, CI, or runtime evidence. Read `docs/governance/repository-work-ledger-contract.md` before changing ledger semantics.

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Canonical terminal action: none; no safe actionable work remains

## ASQ-001 — Adopt repository work ledger across the priority repository family

- **Status:** VERIFY
- **Priority:** P1
- **Owner:** chatgpt-cross-repo-ledger-20260809
- **Branch / PR:** feat/repository-work-ledger-20260809 / #105
- **Scope:** factor the portable AxTask queue insight into AgentSwitchboard as canonical family contract, create AgentSwitchboard local ledger/validator/CI, and provide a bounded triage consumer adoption
- **Forbidden:** changing AxTask domain behavior; copying AxTask recovery/deployment tasks; product feature changes; implicit AgentSwitchboard hook installation; claiming runtime proof from ledger metadata
- **Dependencies:** none
- **References:** `AGENTS.md`, `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`
- **Acceptance gate:** AgentSwitchboard contract, local ledger, validator, negative/positive tests, and CI are tracked on one branch; triage has a repository-local adoption pinned to the exact AgentSwitchboard contract commit; both PR heads pass their owned ledger checks or exact CI gaps are recorded
- **Gate:** none
- **Last proof:** commit:caa32133e67ed2fed7ed643e4bb05570a2ef392f created the portable contract slice; artifact:.ai/harness/repository-work-ledger-adoption.json records donor commit and authority boundary
- **Next action:** run `pwsh -NoLogo -NoProfile -File scripts/Test-RepositoryWorkLedgerContract.ps1` and `python tests/test_repository_work_ledger_contract.py`, then inspect PR #105 exact-head checks and repair any owned failure
- **Updated:** 2026-08-09T19:21:00Z
