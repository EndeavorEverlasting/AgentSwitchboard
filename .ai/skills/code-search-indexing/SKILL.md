# Code Search Indexing

- **Skill ID:** `code-search-indexing`
- **Version:** `1.0.0`
- **Status:** `experimental`

## Trigger
Select when an agent needs repository or cross-repository code search, symbol/content discovery, indexed search, `gh search code`, Sourcegraph, or Zoekt, or when manual repository scanning is wasting time.

## Inputs
- exact repository/ref or repository set;
- query intent and result limit;
- repository visibility/private-code boundary;
- local resource budget;
- provider capability snapshot.

## Procedure
1. Read `tooling/code-search/harness/manifest.json` and provider registry.
2. Do not assume GitHub hosting means code-search readiness. Probe the intended GitHub search path.
3. Prefer `github-api-code-search` when its bounded probe succeeds because it adds no local index workload and stays inside the existing GitHub service boundary.
4. Remember that `gh search code` is the legacy API-backed search path, not the newer GitHub web Blackbird engine.
5. If GitHub search is unavailable, select an already-installed/indexed local Zoekt only when local indexing/storage is explicitly acceptable.
6. Select Sourcegraph only with explicit opt-in plus current plan/trial, endpoint, executable, and authentication evidence.
7. Run `Search-Codebase.py` with bounded result count/timeout. Keep generated results local and untracked.
8. On failure, preserve stderr/exit identity and use the failure-recovery workflow; do not silently switch privacy boundaries.

## Outputs
- selected provider or exact blocker;
- bounded search result and optional local query artifact;
- provider/readiness proof ceiling;
- next executable action.

## Deterministic validation
- `python tests/test_code_search_harness.py`
- `pwsh -NoLogo -NoProfile -File scripts/Test-CodeSearchHarnessCompleteness.ps1`
- `python tooling/code-search/Get-CodeSearchHarnessStatus.py --no-write`
- `git diff --check`

## Forbidden scope
- no provider installation or authentication;
- no token printing or persistence;
- no private-code export to a new external service without explicit approval;
- no destructive cleanup;
- no claim that empty results prove index completeness;
- no claim that search availability proves AI-training policy.

## Stop and escalate
Stop when the chosen provider needs installation, credentials, a new external code-processing boundary, paid/trial approval, or local indexing resources outside the task authority. Name the exact dependency and preserve the safe fallback choices.
