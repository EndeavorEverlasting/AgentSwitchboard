# Entire CLI provider / continuity boundary

| Field | Value |
|---|---|
| Decision | `ASB-ENTIRE-CLI-PROVIDER-CONTINUITY` |
| Operator decision date | 2026-09-24 |
| Status | accepted / contract floor |
| Canonical owner | AgentSwitchboard |
| Live crew runtime | FirstMate |
| Proof ceiling | static contract only |

## Decision

Entire CLI is a **provider-neutral Git, provenance, checkpoint, and agent-session transport adapter** in the AgentSwitchboard architecture.

It is not an LLM, not an inference provider, not a replacement coding model, and not a second live crew orchestrator.

The durable composition is:

```text
AgentSwitchboard     -> routing, authority ceilings, capability/readiness policy, evidence normalization
FirstMate            -> canonical live crew/session runtime when crew orchestration is used
Entire CLI           -> Git/provider transport, mirrors/clones, checkpoint refs, session/provenance capture and recovery
OpenCode/other agent -> actual coding-agent execution
model/provider       -> inference
```

A failure or rate limit in one executor/model must not erase the repository state or force the operator to reconstruct the mission from chat.

## Capability discovery before syntax assumptions

Do not invent Entire command syntax from memory. Resolve the installed CLI first.

Canonical first probe:

```text
entire agent-help --json
```

Use that machine-readable output to confirm the installed version's supported commands and flags before provider mutation.

Useful read-only follow-up when the repository is already Entire-enabled:

```text
entire status --json
```

A successful capability/status probe proves only that the local Entire CLI and repository integration are observable. It does not prove authentication, remote Git transport, checkpoint push, agent execution, model availability, or repository validation.

## Session continuity

Entire is the preferred durability layer for agent-session continuity where supported.

OpenCode integration is enabled through the Entire agent hook:

```text
entire enable --agent opencode --telemetry=false
```

Existing history import is an explicit migration choice, not an ambient side effect.

For a checkpointed branch, the portable resume surface is:

```text
entire session resume <branch>
```

Entire checkpoint/session data is separate from the active branch history. A resume operation restores session metadata and prints the continuation command; the resumed executor still must refresh repository truth and obey AgentSwitchboard/repository authority.

## Git/provider transport

Entire may be preferred over direct GitHub/GitHub Actions transport when the installed capability surface and operator authorization support it.

Current intended provider-neutral examples include:

```text
entire repo clone /gh/OWNER/REPO <target> --nearest
entire repo mirror add /gh/OWNER/REPO
```

These are adapter examples, not unconditional commands. Confirm them against `entire agent-help --json` for the installed version before execution.

GitHub and GitHub Actions remain optional provider adapters. They are not the architectural default merely because a repository is mirrored on GitHub or because a hosted workflow exists.

## Validation boundary

Entire transport does not replace repository-owned validation.

The repository's deterministic validators, tests, manifests, receipts, and proof ceilings remain canonical regardless of whether transport is:

- Entire-native;
- an Entire GitHub mirror;
- native Git;
- GitHub connector/API/CLI;
- local-only.

Hosted GitHub Actions may independently re-run the same repository-owned gates, but Actions availability or minutes must not become the sole definition of correctness when equivalent local proof is defined.

## FirstMate boundary

Entire does not supersede the accepted FirstMate crew-runtime decision.

- FirstMate owns live crew orchestration, supervision, worktree lifecycle, and crew relaunch where that architecture is active.
- Entire owns durable Git/provenance/session transport and checkpoint context where enabled.
- AgentSwitchboard owns the policy and adapter boundary between them.
- An Entire session resume is not evidence that a FirstMate crew task was resumed, and a FirstMate relaunch is not evidence that Entire checkpoint data was written.

## Cost and provider independence

Entire is used to reduce coupling to one hosted coding-agent or forge workflow. It does not make inference free by itself.

AgentSwitchboard may route an affordable or free executor/model separately. No silent paid fallback is authorized by this contract.

## Security and privacy

Entire checkpoints can contain prompts, transcripts, metadata, and working-tree context in repository checkpoint storage. Preserve repository visibility and redaction rules. Never treat checkpoint transport as permission to publish credentials, private customer evidence, or machine-local secrets.

## Proof ceiling

This contract plus its static test proves the intended architectural boundary and canonical command vocabulary only. It does not prove that Entire is installed on a particular workstation, authenticated, able to reach a remote, able to push checkpoint refs, or able to resume a specific live session.
