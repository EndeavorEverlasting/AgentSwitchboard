# AgentSwitchboard Code Search

Use this front door when an agent needs to find implementations, symbols, contracts, errors, filenames, or cross-repository references without manually scanning the repository.

## Start here

1. Read `tooling/code-search/harness/manifest.json`.
2. Read `tooling/code-search/harness/provider-registry.json`.
3. Use `.ai/skills/code-search-indexing/SKILL.md` for provider selection and privacy/resource boundaries.
4. Run `python tooling/code-search/Get-CodeSearchHarnessStatus.py --no-write`.
5. Validate with `python tests/test_code_search_harness.py` and `pwsh -NoLogo -NoProfile -File scripts/Test-CodeSearchHarnessCompleteness.ps1`.
6. Build or run a bounded query with `tooling/code-search/Search-Codebase.py`.

## Provider order

- **GitHub API code search:** preferred when a bounded `gh search code` probe succeeds; no local index workload. The CLI uses GitHub's legacy API-backed code-search engine, not the newer web Blackbird engine.
- **Zoekt local:** fallback only when an existing local index is present or a separate authorized indexing sprint owns creation. It keeps command-based source indexing local but consumes local CPU/storage/memory.
- **Sourcegraph:** explicit opt-in only. Current private Code Search documentation is plan/trial based, so it is not treated as a permanent free default.

## Safety

Never print or track tokens, Authorization headers, customer/private code snippets, or unbounded search output. Do not switch from GitHub/local search to a new external code-processing boundary without explicit approval. An empty search is not index-readiness proof.

## Proof ceiling

This front door and its harness prove repository-owned routing, command construction, evidence policy, and validation. Provider authentication, index freshness/completeness, workstation resource suitability, and useful live query results require runtime evidence.
