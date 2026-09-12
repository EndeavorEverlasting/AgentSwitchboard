# Code Search Indexing Harness

This harness gives AgentSwitchboard agents one deterministic path to indexed code search while keeping provider cost, privacy, and workstation resource use explicit.

## Current provider posture

### GitHub API code search — preferred after probe
For GitHub-hosted repositories, this is the first route because it requires no separate local index. The terminal surface is `gh search code`. Current GitHub CLI documentation explicitly says this command is powered by the legacy GitHub code-search engine, so it must not be described as the newer web Blackbird engine. Search readiness is probed; GitHub hosting alone is not proof.

### Zoekt — local fallback
Zoekt is an open-source trigram code-search engine. Its command-based path can index a local Git repository with `zoekt-git-index` and query it with `zoekt`. This keeps source local, but indexing consumes local CPU, storage, and memory. This harness does not install Zoekt and does not claim Termux support without runtime proof.

### Sourcegraph — explicit external adapter
The `src` CLI can search a configured Sourcegraph instance. Current Sourcegraph documentation lists Code Search on Enterprise Starter/Enterprise plans and offers a 30-day Cloud trial. Treat it as optional rather than a permanent free private-code default. Private-code use crosses into the selected Sourcegraph instance and requires explicit approval.

## Fast entry

```powershell
python tooling/code-search/Get-CodeSearchHarnessStatus.py --no-write
python tests/test_code_search_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-CodeSearchHarnessCompleteness.ps1
python tooling/code-search/Search-Codebase.py --provider github-api-code-search --repo EndeavorEverlasting/AgentSwitchboard --query manifest --dry-run
```

## Evidence policy
Readiness and query artifacts are generated outside the repository and are untracked. Never track access tokens, Authorization headers, private/customer snippets, or unbounded search output.

## Failure handling
A missing executable, failed auth, unavailable GitHub index, stale/missing Zoekt index, Sourcegraph plan/endpoint gap, timeout, or query syntax error is a distinct blocker. Preserve its exit identity and do not silently cross to a provider with a different privacy boundary.

## Known gaps
No provider is installed or authenticated by this harness. No physical-workstation search has been observed. GitHub enhanced index availability may differ by repository/account. Sourcegraph cost/plan facts can change and must be reverified before adoption. Zoekt resource consumption must be measured on the intended machine before calling it lightweight enough.

## Proof ceiling
Passing contracts prove repository-owned selection/routing, safe command construction, artifact policy, and documentation. They do not prove index freshness, complete results, authentication, local resource suitability, provider privacy beyond documented boundaries, or operator acceptance.
