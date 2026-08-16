# External Agent Tooling Catalog

This harness surface converts the operator's accumulated agent-tooling research into a **searchable, enforceable intake registry**. It is deliberately not an installer list. A mention can be valuable as architecture evidence, a comparison point, a compatibility target, or an evaluation candidate without becoming AgentSwitchboard runtime code.

## What is cataloged

The initial registry contains **45 named technologies or skill surfaces** across seven provenance buckets:

- prior workflow/tooling discussion;
- one item named directly in the current request;
- DeepSeek harness architecture;
- modular agent skills and spec-driven comparisons;
- reverse prompting;
- recursive/context-as-variable systems;
- graph/vector memory and MCP-oriented agents.

Supporting technologies such as Tree-sitter, GCC, Cypher, MCP, RLMs, and model providers are retained because they materially explain how the primary tools are claimed to work.

## Evidence states

`reported` means the statement is preserved from the supplied source material but has not been independently verified for adoption. `partially-verified` means a public project identity was resolved but the supplied source linkage or full claim set still needs verification. `verified` requires versioned upstream evidence appropriate to the claim. `unresolved` preserves ambiguous identity or claims without guessing.

The registry also preserves the operator spelling **Ader** as an alias while using **Aider** as the resolved public project name. That correction does not verify that the cited video meant the same project.

## Dispositions

- **existing-reference** — AgentSwitchboard already contains a related surface; inspect and extend rather than duplicate.
- **evaluate** — plausible candidate for a bounded research/evaluation sprint.
- **compatibility** — useful as a supported/compared external environment, not owned runtime behavior.
- **supporting** — enabling technology or protocol.
- **comparison** — architecture/process contrast that may inform design without adoption.
- **watchlist** — identity or fit is too unresolved for a stronger route.

## High-value evaluation lanes

The catalog exposes several coherent lanes rather than one giant “install everything” sprint:

1. **Codebase intelligence:** Understand Anything + Tree-sitter; compare graph navigation to the repo's existing maps and search surfaces.
2. **Local inference:** Colibri; verify real model/storage/runtime limits and privacy behavior before considering a local-provider adapter.
3. **Skill-system design:** Matt Pocock's suite; compare composable skill behavior against AgentSwitchboard's existing `.ai/skills` contracts and validators.
4. **Context architecture:** DeepSeek Harness and RLM-style systems; compare append-only event/context strategies and recursive context handling against the existing event/evidence doctrine.
5. **Reverse prompting:** Git Reverse; evaluate whether reconstruction prompts add evidence beyond current codebase maps and architecture docs.
6. **Memory:** Neo4j/GraphRAG, pgvector, and LanceDB; test whether multi-hop graph memory adds value beyond flat/vector retrieval before introducing another persistence layer.
7. **Fine-tuning:** Unsloth; keep separate from runtime-agent integration because model training has different compute, data, and artifact boundaries.

## Adoption gate

Before any tool moves from `evaluate` or `watchlist` into implementation, the owning sprint must verify official upstream identity and a pinned version/commit, supported OS, install scope, expected files, permissions, subprocess/filesystem/network behavior, telemetry/update behavior, credentials, persistence, rollback, repository overlap, and the intended proof ceiling.

The catalog grants **no** install, provider-call, network, secret, global-configuration, deployment, or live-target authority.

## Validation

```text
python3 tests/test_external_agent_tooling_catalog.py
pwsh -NoLogo -NoProfile -File scripts/Test-ExternalAgentToolingCatalog.ps1
git diff --check
```

The portable test also pins the complete initial name set so future cleanup cannot silently drop a tool that was part of this research tranche.
