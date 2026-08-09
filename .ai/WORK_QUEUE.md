# AgentSwitchboard shared agent work queue

Contract: `RepoLedgerInteroperability.v1` pinned by `.ai/repo-ledger-adoption.json`.

This file is the repo-local coordination ledger for unfinished AgentSwitchboard work. It coordinates claims and continuation only. `AGENTS.md`, repository governance/contracts, source, validators, current Git/PR/CI state, and runtime evidence remain authoritative for behavior and proof.

At intake, read this ledger before selecting unfinished work. Claim before substantial mutation. `READY`, `CLAIMED`, `VERIFY`, `REVIEW`, and `MERGE` are continuation states when safe authorized work remains. Stop only at `DONE`, `BLOCKED`, or `OPERATOR`. `BLOCKED` and `OPERATOR` require an exact gate and executable next action. `DONE` requires durable proof, `Gate: none`, and `Next action: none; no safe actionable work remains`.

Task headings use `## ASQ-### — Title`. Required fields are Status, Priority, Owner, Branch / PR, Scope, Forbidden, Dependencies, References, Acceptance gate, Gate, Last proof, Next action, and Updated. Priorities are `P0` through `P3`.

---

## ASQ-001 — Adopt the repo-local shared work ledger

- **Status:** DONE
- **Priority:** P1
- **Owner:** shared-ledger-adoption
- **Branch / PR:** feat/repo-ledger-adoption-20260809
- **Scope:** add the AgentSwitchboard-local ledger, exact BlacksmithGuild contract pin, intake pointer, and consumer-owned validator
- **Forbidden:** changing repository-family governance, product/runtime behavior, deployment behavior, secrets, proof promotion, or importing AxTask task bodies/AXQ identifiers
- **Dependencies:** none
- **References:** `.ai/repo-ledger-adoption.json`, `.ai/README.md`, `scripts/ai-harness/validate-repo-ledger.py`
- **Acceptance gate:** the local queue and compatibility manifest are tracked and the consumer-owned validator enforces v1 continuation/DONE and stale-ref rules
- **Gate:** none
- **Last proof:** artifact:.ai/repo-ledger-adoption.json artifact:.ai/README.md artifact:scripts/ai-harness/validate-repo-ledger.py
- **Next action:** none; no safe actionable work remains
- **Updated:** 2026-08-09
