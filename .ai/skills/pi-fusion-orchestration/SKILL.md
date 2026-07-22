---
id: pi-fusion-orchestration
version: 1.0.0
status: experimental
---

# Pi Fusion Orchestration

## Trigger

Use when a task explicitly requests Pi-backed multi-agent opinions, fusion, architect/builder separation, or bounded autovalidation. Do not select this skill merely because Pi is installed or mentioned.

## Inputs

- repository and isolated branch or worktree;
- lane, mission, owned scope, and forbidden scope;
- expected artifacts and validation commands;
- selected workflow: `opinion-fusion` or `autovalidate`;
- architect, builder, validator or adjudicator, and designated-writer identities;
- exact provider, model, endpoint class, and extension source when runtime execution is authorized;
- maximum attempts, wall-clock limit, token limit, no-progress threshold, and cancellation method;
- local artifact root outside tracked authority;
- proof ceiling.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/manifest.json`, and `tooling/pi/harness/pi-adapter.registry.json`.
2. Run `scripts/Test-PiHarnessCompleteness.ps1` before selecting a runtime route.
3. Verify the exact Pi version and upstream API contract. Treat extensions as executable code with the invoking process's permissions.
4. Create a schema-valid run context with one designated writer and explicit bounds.
5. For opinion fusion, hash one minimized input packet, run architect and builder independently, attribute both outputs, and preserve consensus, divergence, unresolved risks, rejected alternatives, and source artifacts.
6. For autovalidation, have the architect define and hash deterministic acceptance gates before builder mutation. The builder may not weaken, replace, or skip the frozen gate.
7. Keep parallel roles read-only unless they are the designated writer. Never share uncommitted branch state between agents.
8. Stop on scope drift, changed assumptions, identity mismatch, unsafe artifact paths, exhausted bounds, no progress, contradictory evidence, or incomplete attribution.
9. Emit minimized local artifacts and an English operator report. Name exact validation, commit, push or PR state, proof ceiling, and one next command.

## Outputs

- `pi-run-context.json`;
- attributed architect and builder role outputs when fusion is selected;
- `pi-fusion-result.json` or `pi-validation-ledger.json`;
- `pi-operator-report.md`;
- `pi-final-handoff.json`;
- tracked implementation only from the designated writer.

## Deterministic validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
python tests/test_pi_harness_contracts.py
Test-AppHarness.cmd
git diff --check
```

## Forbidden scope

- installing Pi, Node, a provider, model server, or extension without explicit setup scope;
- global Pi configuration mutation by default;
- credentials, raw prompts, raw model transcripts, or private runtime evidence in Git;
- more than one writer on a branch;
- claiming independence when outputs share hidden context or identity;
- claiming privacy from `localhost` or configuration intent alone;
- unbounded retries, self-modifying gates, silent fallback, automatic merge, deployment, or live-target mutation.

## Stop and escalate

Stop when Pi or model identity is unverified, the official API differs from the planned adapter, the branch is dirty or shared, the acceptance gate changes, validation cannot be bounded, privacy evidence is missing, outputs cannot be attributed, or a forbidden capability is required.

This skill proves a reviewed orchestration procedure and deterministic artifact contracts only. It does not prove Pi installation, extension compatibility, provider availability, local privacy, model quality, repository delivery, or runtime success.
