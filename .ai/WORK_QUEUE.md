contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# AgentSwitchboard shared work ledger

This is the canonical coordination ledger for unfinished AgentSwitchboard repository work. It routes work; it does not replace `AGENTS.md`, source code, plans, validators, PRs, CI, or runtime evidence. Read `docs/governance/repository-work-ledger-contract.md` before changing ledger semantics.

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Canonical terminal action: none; no safe actionable work remains

## ASQ-001 — Adopt repository work ledger across the priority repository family

- **Status:** MERGE
- **Priority:** P1
- **Owner:** chatgpt-cross-repo-ledger-20260809
- **Branch / PR:** chore/work-ledger-post-merge-state-20260809 / follow-up PR pending
- **Scope:** factor the portable AxTask queue insight into AgentSwitchboard as canonical family contract, create AgentSwitchboard local ledger/validator/CI, and provide a bounded triage consumer adoption
- **Forbidden:** changing AxTask domain behavior; copying AxTask recovery/deployment tasks; product feature changes; implicit AgentSwitchboard hook installation; claiming runtime proof from ledger metadata
- **Dependencies:** AgentSwitchboard PR #105 merged as `62acecf4a590ecadf4a0b1ad1410e659b4e1b650`; triage PR #160 merged as `189be37114ef2eb11015b0d962eb23e5d12f1ccc`
- **References:** `AGENTS.md`, `docs/governance/repository-work-ledger-contract.md`, `.ai/harness/repository-work-ledger.policy.json`, `.ai/harness/repository-work-ledger-adoption.json`
- **Acceptance gate:** portable contract is canonical on AgentSwitchboard main; triage consumer is canonical on triage main and pins the AgentSwitchboard merge commit; both implementations passed their repository-owned contract and harness checks; final AgentSwitchboard ledger state is merged to main
- **Gate:** none
- **Last proof:** merge:62acecf4a590ecadf4a0b1ad1410e659b4e1b650 established the canonical AgentSwitchboard contract; workflow:31331594284 passed its exact-head ledger contract; merge:189be37114ef2eb11015b0d962eb23e5d12f1ccc established the triage consumer; workflows 31331837078, 31331837062, and 31331837072 passed the final triage PR head before merge
- **Next action:** merge the one-file AgentSwitchboard ledger-state follow-up after its repository work ledger contract and repository-family harness checks pass
- **Updated:** 2026-08-09T19:33:00Z
