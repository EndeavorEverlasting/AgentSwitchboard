# AgentSwitchboard Codebase Map

Load only the smallest surface required by the selected skill, workflow, or repository-family profile.

## Root coordination

- `AGENTS.md` — universal operating contract and safety floor.
- `CLAUDE.md` — Claude-compatible adapter subordinate to `AGENTS.md`.
- `SKILLS.md` — canonical skill catalog and artifact-type routing.
- `CAPABILITIES.md` — capability verification and authority boundaries.
- `TRIGGERS.md` — deterministic request and evidence routing.
- `.ai/agent-contract.json` — canonical contract version and family registration.

## Repository-family harness

- `.ai/harness/manifest.json` — central harness paths, proof vocabulary, and generated-evidence policy.
- `.ai/harness/repository-family.registry.json` — exact profiles for AgentSwitchboard, BlacksmithGuild, Web Excel Repair Triage, and SysAdminSuite.
- `.ai/harness/artifact-registry.json` — closed artifact-role registry for family intake, status, English reports, and handoff compression.
- `.ai/harness/workflows/repository-family-intake.workflow.json` — read-only local-clone discovery and readiness workflow.
- `.ai/harness/schemas/` — run-context, registry, status, and final-handoff schemas.
- `scripts/Get-RepositoryFamilyHarnessStatus.ps1` — read-only local workspace probe; it does not clone, fetch, run providers, or mutate a repository.
- `scripts/Test-RepositoryFamilyHarness.ps1` — deterministic registry, schema, workflow, parser, and safety validator.
- `.github/workflows/repository-family-harness.yml` — Linux and Windows contract gate.

## Canonical skills

- `.ai/skills/repo-intake/SKILL.md` — recover repository truth and select safe work.
- `.ai/skills/bounded-sprint/SKILL.md` — execute one bounded tracked change.
- `.ai/skills/gnhf-prompt-compilation/SKILL.md` — compile the copy-ready bounded `gnhf` PowerShell artifact.
- `.ai/skills/evidence-validation/SKILL.md` — build honest proof and repair validation gaps.
- `.ai/skills/pr-integration/SKILL.md` — reconcile stacked or parallel branches.
- `.ai/skills/runtime-proof/SKILL.md` — advance from static evidence to observed behavior without proof inflation.

## GNHF control plane

- `tooling/gnhf/` — fleet install, routing, bounded sprint launch, contracts, prompts, schemas, fixtures, and runtime evidence.
- `Setup-AgentSwitchboard.cmd` — one-click Windows setup front door.
- `Run-ChatGPTDesktopGnhfSprint.cmd` — desktop GNHF runtime entrypoint when present on the selected integration branch.
- `%LOCALAPPDATA%\AgentSwitchboard\` — installed runtime state and logs; never treat it as tracked repository authority.

## Workstation and terminal integration

- `tooling/wsl/` — Windows/WSL/tmux workspace provisioning, lifecycle, proof, and repair.
- `docs/workstation/` — operator runbooks and proof ceilings.
- workstation scripts may configure a local environment only when the selected workflow explicitly authorizes mutation.

## Governance and adoption

- `docs/governance/repository-family.md` — root/child authority and reviewable propagation model.
- `docs/governance/repository-family-harness.md` — operational profile, readiness, and child-harness expectations.
- `templates/repository-agent-contract/` — child adoption templates; never bulk overwrite a child repository's local law.

## Validation

- `scripts/Test-AgentDocumentationContract.ps1` — root contract, canonical skills, triggers, and template checks.
- `scripts/Test-RepositoryFamilyHarness.ps1` — family profile and harness checks.
- `tooling/gnhf/Test-GnhfFleetContracts.ps1` and more specific downstream validators — GNHF implementation checks on branches that contain those surfaces.

## Generated evidence and reports

Repository-family status evidence is untracked and defaults to the operating-system temporary directory. It may contain local directory names and Git state, so it must not be committed.

Expected outputs from the family status probe:

- `run-context.json`
- `repository-family-status.json`
- `operator-report.md`
- `final-handoff.json`

## Proof boundary

A valid family profile proves that AgentSwitchboard knows how to enter and inspect a repository. It does not prove that a child checkout is present, current, clean, validated, or safe to mutate. The status probe earns only read-only repository-intake proof; every child validator and runtime authority remains local to that child repository.
