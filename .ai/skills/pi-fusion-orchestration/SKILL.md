---
id: pi-fusion-orchestration
version: 1.1.0
status: experimental
---

# Pi Fusion Orchestration

## Trigger

Use when a task explicitly requests Pi-backed multi-agent opinions, fusion, architect/builder separation, or bounded autovalidation. Do not select this skill merely because Pi is installed, launched for one agent, or mentioned.

## Inputs

- repository and isolated branch or worktree;
- lane, mission, owned scope, and forbidden scope;
- expected artifacts and validation commands;
- selected workflow: `opinion-fusion` or `autovalidate`;
- architect, builder, validator or adjudicator, and designated-writer identities;
- exact pinned Pi executable path and version;
- explicit Pi project-trust state;
- exact provider, model, endpoint class, and reviewed extension or package source when runtime execution is authorized;
- maximum attempts, wall-clock limit, token limit, no-progress threshold, and cancellation method;
- local artifact and session roots outside tracked authority;
- proof ceiling.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/manifest.json`, `tooling/pi/harness/upstream-verification.json`, and `tooling/pi/harness/pi-adapter.registry.json`.
2. Run `scripts/Test-PiHarnessCompleteness.ps1`, both dependency-free Pi tests, and `tooling/pi/Get-PiHarnessStatus.ps1 -NoWrite` before selecting a runtime route.
3. Require status `runtime-ready-provider-unproved` before runtime work. When Pi is merely `installable`, use the tracked exact-version installer under explicit setup authority, then rerun readiness. Do not substitute a floating npm command.
4. Verify project trust without passing `--approve` or changing `defaultProjectTrust`. Verify actual provider, model, endpoint, and authentication separately from Pi CLI readiness.
5. Treat extensions, packages, executable skills, and custom providers as code with the invoking process's permissions. Require exact source and integrity, filesystem/subprocess/network review, update and rollback paths, and focused tests before enabling them.
6. Create a schema-valid run context with one designated writer and explicit bounds. Record actual executor, provider, model, endpoint class, role, branch, and validation result.
7. For opinion fusion, hash one minimized input packet, run architect and builder independently, attribute both outputs, and preserve consensus, divergence, unresolved risks, rejected alternatives, and source artifacts.
8. For autovalidation, have the architect define and hash deterministic acceptance gates before builder mutation. The builder may not weaken, replace, skip, or reinterpret the frozen gate.
9. Keep parallel roles read-only unless they are the designated writer. Never share uncommitted branch state between agents or present aliases of one underlying execution as independent review.
10. Stop on scope drift, changed assumptions, identity mismatch, unsafe artifact paths, exhausted bounds, no progress, contradictory evidence, provider fallback, or incomplete attribution.
11. Emit minimized local artifacts and an English operator report. Name exact validation, commit, push or PR state, proof ceiling, and one next command.

## Outputs

- `pi-run-context.json`;
- attributed architect and builder role outputs when fusion is selected;
- `pi-fusion-result.json` or `pi-validation-ledger.json`;
- `pi-operator-report.md`;
- `pi-final-handoff.json`;
- tracked implementation only from the designated writer.

All generated Pi role, fusion, validation, session, and launch evidence remains outside the repository unless deliberately minimized and reviewed as a public fixture.

## Deterministic validation

```powershell
python tests/test_pi_harness_contracts.py
python tests/test_pi_runtime_support.py
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1 -NoWrite
Test-AppHarness.cmd
git diff --check
```

Runtime selection additionally requires exact-version Pi readback, project trust, provider/model identity, bounded execution, separate attributed role outputs, and final delivery evidence. Static checks and a single-agent launcher do not prove fusion or autovalidation.

## Forbidden scope

- installing Pi, Node, a provider, model server, package, or extension without explicit setup scope;
- using an unverified package name, floating version, remembered API, or lifecycle-script-enabled install;
- bypassing Pi project trust or silently changing global Pi configuration;
- describing all Pi model access as free merely because the CLI is free;
- credentials, raw prompts, raw model transcripts, sessions, or private runtime evidence in Git;
- more than one writer on a branch;
- claiming independence when outputs share hidden context, provider/model identity, or one underlying execution;
- claiming privacy from `localhost`, offline intent, or configuration alone;
- unbounded retries, self-modifying gates, silent fallback, automatic merge, deployment, or live-target mutation.

## Stop and escalate

Stop when the pinned Pi version is missing or mismatched, project trust is absent or would be bypassed, provider/model identity is unverified, the official API differs from the planned adapter, an extension or package is unreviewed, the branch is dirty or shared, the acceptance gate changes, validation cannot be bounded, privacy evidence is missing, outputs cannot be attributed, or a forbidden capability is required.

This skill proves a reviewed orchestration procedure and deterministic artifact contracts only. The repository now supports exact-version Pi installation and a single-agent launcher, but this skill does not prove extension compatibility, provider availability, endpoint privacy, model quality, independent role execution, opinion-fusion delivery, autovalidation delivery, or runtime success.
