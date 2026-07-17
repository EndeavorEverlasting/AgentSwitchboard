# Repository Family Harness

## Supported operational family

AgentSwitchboard must be able to enter and inspect these repositories readily:

1. `EndeavorEverlasting/AgentSwitchboard`
2. `EndeavorEverlasting/BlacksmithGuild`
3. `EndeavorEverlasting/web-excel-repair-triage`
4. `EndeavorEverlasting/SysAdminSuite`

AgentSwitchboard works on itself through the same evidence, scope, isolation, validation, and handoff rules used for child repositories. It receives no exemption from its own contract.

## Harness, not prompts

Prompts are orchestration artifacts inside the harness. A serious repository-local harness includes:

- repo agent rules;
- a codebase map;
- workflow specifications;
- run context;
- an artifact registry;
- deterministic validators;
- local hooks only where proven useful;
- scoped skills and capabilities;
- read-only code and repository intelligence;
- English/operator reports;
- compressed final handoffs.

Application and runtime behavior remains in conventional code, scripts, manifests, schemas, tests, and deployment configuration. Prompt text must not become its sole implementation.

## Authority boundary

AgentSwitchboard owns:

- shared agent policy;
- repository-family profile and discovery contracts;
- GNHF request, compilation, routing, and runtime-control contracts;
- workstation orchestration owned by AgentSwitchboard;
- read-only family intake and status reporting.

Each child repository owns:

- product and domain behavior;
- local skills and workflows;
- local validators and proof promotion;
- generated-output policy;
- runtime, deployment, target, save, workbook, or customer-data boundaries;
- final acceptance.

A family profile says how to enter a repository. It does not transfer authority.

## Default-branch rule

Tracked files on the child repository's current default branch are authority. An open pull request may demonstrate planned adoption, but it is evidence only until merged. The readiness probe therefore checks the local checkout in front of it and reports missing required paths rather than pretending an unmerged harness already exists.

## Read-only intake workflow

Run from the AgentSwitchboard checkout:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1
```

The default workspace root is the parent directory of the AgentSwitchboard checkout. Override it explicitly when the repositories live elsewhere:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Get-RepositoryFamilyHarnessStatus.ps1 `
  -WorkspaceRoot C:\path\to\workspace
```

The workflow does not:

- clone or fetch;
- switch, reset, clean, stash, or modify Git state;
- execute child validators;
- invoke an agent or provider;
- mutate a workstation, target, game, save, workbook, service, or deployment;
- push, merge, or deploy.

## Status meanings

- `ready` — expected local clone, matching origin, attached branch, and every registered required path are present.
- `partial` — the correct local repository exists but one or more required harness paths are missing.
- `blocked` — a directory exists but Git identity, origin, or attached-branch safety is not trustworthy.
- `not_present` — no registered local clone was found under the workspace root.

`ready` is an intake result, not permission to mutate and not proof that child validators pass.

## Generated artifacts

The probe writes four untracked artifacts outside the repositories by default:

- `run-context.json`
- `repository-family-status.json`
- `operator-report.md`
- `final-handoff.json`

These artifacts may describe local Git state and directory names. They are local operational evidence and must not be committed.

## Current family posture

- BlacksmithGuild has a mature `.tbg` harness on its default branch, including codebase mapping, skills, workflows, E2E profiles, artifact roles, English reports, and sprint-capsule handoff.
- SysAdminSuite has a mature harness on its default branch and retains authority for survey, deployment, package, workstation, and target-mutation workflows.
- Web Excel Repair Triage has strong product rules on its default branch and active harness-spine work, but the family readiness contract intentionally requires the complete default-branch harness surface before reporting `ready`.
- AgentSwitchboard's own family harness is defined by this branch and remains stacked on the canonical operating-contract branch until review and integration.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-AgentDocumentationContract.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-RepositoryFamilyHarness.ps1
```

CI runs the family contract and a self-only read-only probe on Linux and Windows. Missing sibling clones are expected in hosted CI and are reported without failing the workflow.

## Proof ceiling

This layer proves machine-readable family registration, local-clone discovery, Git identity, required-path readiness, schema and workflow consistency, English reporting, and handoff compression. It cannot prove child tests, builds, provider responses, runtime behavior, target mutation, workbook acceptance, gameplay, merge safety, or deployment success.
