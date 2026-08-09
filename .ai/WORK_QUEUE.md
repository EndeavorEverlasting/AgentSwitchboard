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
