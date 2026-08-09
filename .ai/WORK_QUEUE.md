contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# AgentSwitchboard shared work ledger

This is the canonical coordination ledger for unfinished AgentSwitchboard repository work. It routes work; it does not replace `AGENTS.md`, source code, plans, validators, PRs, CI, or runtime evidence. Read `docs/governance/repository-work-ledger-contract.md` before changing ledger semantics.

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Canonical terminal action: none; no safe actionable work remains

## ASQ-001 — Adopt repository work ledger across the priority repository family

- **Status:** OPERATOR
- **Priority:** P1
- **Owner:** chatgpt-cross-repo-ledger-20260809
- **Branch / PR:** feat/repository-work-ledger-20260809 / #105
- **Scope:** factor the portable AxTask queue insight into AgentSwitchboard as canonical family contract, create AgentSwitchboard local ledger/validator/CI, and provide a bounded triage consumer adoption
- **Forbidden:** changing AxTask domain behavior; copying AxTask recovery/deployment tasks; product feature changes; implicit AgentSwitchboard hook installation; claiming runtime proof from ledger metadata
- **Dependencies:** triage PR #160 must repin to the resulting AgentSwitchboard `main` commit after this PR merges
- **References:** `AGENTS.md`, `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`
- **Acceptance gate:** AgentSwitchboard contract, local ledger, validator, negative/positive tests, and CI are tracked on one branch; triage has a repository-local adoption pinned to the exact AgentSwitchboard contract commit; both PR heads pass their owned ledger checks or exact CI gaps are recorded
- **Gate:** repository-owner merge authorization for PR #105; triage cannot establish a durable canonical pin until this contract lands on AgentSwitchboard `main`
- **Last proof:** commit:41438d49efa3595a7df64b7fe08d307fce0983fd includes immutable-v1 regression coverage; workflow:31331594284 passed the exact-head repository work ledger contract; workflows 31331594318, 31331594300, 31331594283, and 31331594282 also passed
- **Next action:** operator review PR #105 at exact head `41438d49efa3595a7df64b7fe08d307fce0983fd` and merge it using the repository-approved method; then record the resulting AgentSwitchboard `main` commit in triage PR #160 before triage merge
- **Updated:** 2026-08-09T19:27:00Z
