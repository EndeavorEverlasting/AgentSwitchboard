# External Agent Tooling Catalog

This leaf preserves the useful evidence-intake behavior from closed PR #118 without reviving its stale shared registrations. It is a **source-only catalog**, not an installer list, capability registry, trust registry, privacy registry, or execution adapter.

## Source-only semantics

The catalog retains 45 named technologies/skill surfaces across the original seven provenance buckets. Each entry carries the historical evidence state and disposition plus four explicit proof-boundary fields:

- `capabilityState: unknown`
- `runtimeProof: unproved`
- `trustProof: unproved`
- `privacyProof: unproved`

`reported`, `partially-verified`, `verified`, and `unresolved` describe the **source evidence/identity state** only. They do not promote live capability. Current capability truth belongs to `CAPABILITIES.md`; execution proof belongs to runtime-specific owners such as the execution-adapter contract.

## Proof-promotion guard

Catalog presence never proves a tool is installed, executable, trusted, private, network-safe, provider-ready, or runtime-ready. `valid-source-only.fixture.json` is the positive control. `invalid-proof-promotion.fixture.json` attempts unsupported capability/runtime/trust/privacy promotion and must be rejected by the focused contracts.

## Dispositions

- **existing-reference** — an AgentSwitchboard surface may already overlap; inspect current owners before extending.
- **evaluate** — candidate for a separately authorized research/evaluation sprint.
- **compatibility** — external environment to understand or support, not owned runtime behavior.
- **supporting** — enabling technology or protocol.
- **comparison** — architecture/process contrast without adoption.
- **watchlist** — identity or fit remains too unresolved for a stronger route.

## Adoption gate

Before adoption, the owning sprint must verify official upstream identity and a pinned version/commit, supported OS, install scope, expected files, permissions, subprocess/filesystem/network behavior, telemetry/update behavior, credentials, persistence, rollback, repository overlap, and the intended proof ceiling. A live capability claim must be recorded by its actual capability/runtime owner rather than this catalog.

## Shared registration is deferred

The historical PR edited the shared operational manifest, validator registry, workflow registry, and created an intake skill. This leaf intentionally does none of those things. `manifest.json` and `codebase-map.json` carry the exact manifest/validator delta for ASQ-030. Shared workflow routing is a deliberate no-op until convergence chooses a canonical skill/routing owner.

## Validation

```text
python3 tests/test_external_agent_tooling_catalog.py
pwsh -NoLogo -NoProfile -File scripts/Test-ExternalAgentToolingCatalog.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

The portable validator pins the complete donor name set, closed entry shape, source-only proof states, workflow order, fixtures, provenance, and deferred registration contract.

## Proof ceiling

Tracked source-evidence catalog/intake behavior and offline/static validation only. No third-party installation, execution, trust, privacy, provider, deployment, or runtime claim is proven.
