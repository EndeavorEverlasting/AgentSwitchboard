# Code Search Indexing Harness Status

**State:** hosted contract validated on Windows and Linux; physical provider probe unproved.

## Working
- Provider registry distinguishes GitHub API search, local Zoekt, and Sourcegraph.
- Selection is free-first but readiness-driven, not vendor-assumed.
- GitHub hosting does not count as search readiness.
- GitHub CLI legacy-search limitation is recorded.
- Sourcegraph is not represented as a permanent free private-code tier.
- Zoekt local resource cost and unverified Termux support are explicit.
- Query construction uses argument arrays rather than shell interpolation.
- Generated search evidence is local and untracked.
- Dedicated code-search harness run `31340863590` passed on Windows and Linux: dependency-free contracts, tracked completeness, status generation, documentation compatibility, PowerShell parsing on Windows, PR-range diff hygiene, and clean checkout.
- Agent documentation contract run `31340863579` passed on Windows and Linux: governance doctrine, harness doctrine, end-to-end runtime skill contract, documentation contract, and repository hygiene.

## Broken / missing
- No workstation provider has been authenticated/probed through this harness yet.
- No successful live GitHub code-search result has been observed through the tracked query wrapper.
- No Zoekt index has been created by this harness.
- No Sourcegraph endpoint or plan is assumed.
- No live index-freshness or query-quality proof exists yet.

## Next gate
Run the exact-head harness on the operator workstation, generate readiness artifacts, then perform one bounded GitHub code-search query for a known tracked marker if `gh` is available and authenticated. A successful non-empty result proves that provider path for that workstation at that moment. If it fails or returns no known marker, preserve the query artifact and classify the exact blocker before considering an already-existing Zoekt index or an explicitly approved Sourcegraph boundary.

## Proof ceiling
Hosted repository contract, routing, command construction, completeness, and cross-platform compatibility are proved. Provider authentication, index freshness/completeness, workstation resource suitability, and useful live query behavior remain unproved until observed on the intended workstation.
