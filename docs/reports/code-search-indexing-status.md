# Code Search Indexing Harness Status

**State:** contract implementation in progress; runtime provider probe unproved.

## Working
- Provider registry distinguishes GitHub API search, local Zoekt, and Sourcegraph.
- Selection is free-first but readiness-driven, not vendor-assumed.
- GitHub hosting does not count as search readiness.
- GitHub CLI legacy-search limitation is recorded.
- Sourcegraph is not represented as a permanent free private-code tier.
- Zoekt local resource cost and unverified Termux support are explicit.
- Query construction uses argument arrays rather than shell interpolation.
- Generated search evidence is local and untracked.

## Broken / missing
- No workstation provider has been authenticated/probed through this harness yet.
- No Zoekt index has been created by this harness.
- No Sourcegraph endpoint or plan is assumed.
- No live query result or index-freshness proof exists yet.

## Next gate
Run the exact-head harness on the operator workstation, generate readiness artifacts, then perform one bounded GitHub code-search probe if `gh` is available/authenticated. If that fails, the resulting artifact determines whether an existing Zoekt index is usable or whether installation/resource approval is the real blocker.

## Proof ceiling
Repository contract and hosted validation only until a provider query is observed on the intended workstation.
