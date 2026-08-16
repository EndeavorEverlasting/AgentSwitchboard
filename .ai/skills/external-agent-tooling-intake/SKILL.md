---
id: external-agent-tooling-intake
status: canonical
owner: AgentSwitchboard operational harness
---

# External Agent Tooling Intake

## Trigger

Use this skill when a conversation, video, repository, article, operator note, or existing adapter introduces an external tool, framework, plugin, provider, protocol, database, agent skill suite, or agent-harness architecture that may matter to AgentSwitchboard.

## Inputs

- literal supplied name and aliases;
- source reference or source bucket;
- reported capability claims;
- intended use or comparison;
- current repository evidence for existing overlap.

## Procedure

1. **Preserve provenance.** Capture what the source actually claimed. Do not silently turn a video/conversation claim into verified technical fact.
2. **Classify.** Record kind, category, mention class, evidence state, and disposition.
3. **Reuse before creation.** Search existing adapters, prompts, skills, manifests, registries, validators, workflows, and docs for the same responsibility.
4. **Verify before adoption.** For any integration candidate, verify the official upstream identity and the pinned version or commit, supported OS, expected files, install scope, permissions, subprocess behavior, filesystem behavior, network/telemetry behavior, credentials, persistence/update mechanism, and rollback path.
5. **Prove privacy claims.** Localhost, open weights, local inference, graph storage, or MCP transport do not prove that data stays local. Resolve effective endpoints, telemetry, fallbacks, and outbound behavior before making a privacy claim.
6. **Separate comparison from implementation.** A useful architectural idea may remain a comparison/reference without installing its tool.
7. **Open a new implementation lane for adoption.** The catalog itself grants no installation, provider-call, network, secret, global-configuration, or live-target authority.
8. **Validate tracked changes.** Run the portable validator, the PowerShell validator where available, and `git diff --check`.

## Outputs

- updated `external-agent-tooling.registry.json`;
- bounded disposition (`existing-reference`, `evaluate`, `compatibility`, `supporting`, `comparison`, or `watchlist`);
- generated evaluation/report artifacts when an evaluation is performed;
- a separately scoped implementation sprint if adoption is approved.

## Deterministic validation

```text
python3 tests/test_external_agent_tooling_catalog.py
pwsh -NoLogo -NoProfile -File scripts/Test-ExternalAgentToolingCatalog.ps1
git diff --check
```

## Forbidden scope

- installing or executing third-party software merely because it appears in the catalog;
- treating supplied performance/cost/benchmark claims as verified without source evidence;
- collecting or committing credentials, private configuration, or machine-local operational evidence;
- bypassing the one-writer rule or existing canonical owners;
- claiming runtime, privacy, security, or provider behavior from static catalog metadata.

## Stop and escalate

Stop the adoption path when upstream identity is ambiguous, official versioned evidence is unavailable, another owner controls the integration surface, security/privacy behavior is unresolved, or the requested action exceeds the declared sprint authority. Preserve the unresolved evidence state and name the smallest verification or implementation gate that can advance it.
