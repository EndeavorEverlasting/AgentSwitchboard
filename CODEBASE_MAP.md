# AgentSwitchboard Codebase Map

Load only the smallest surface required by the selected skill, workflow, public plan, or repository-family profile.

## Root coordination

- `AGENTS.md` — universal operating contract and safety floor.
- `CLAUDE.md` — Claude-compatible adapter subordinate to `AGENTS.md`.
- `SKILLS.md` — canonical skill catalog and artifact-type routing.
- `CAPABILITIES.md` — capability verification and authority boundaries.
- `TRIGGERS.md` — deterministic request and evidence routing.
- `.ai/agent-contract.json` — canonical contract version and family registration.
- `plans/plan-registry.json` — public machine-readable coordination index.
- `AgentSwitchboard.cmd` — readiness-first repository startup launcher.

## Public plans

- `plans/README.md` — plan-versus-PR boundary, lifecycle, and agent procedure.
- `plans/plan-registry.json` — active public plan index.
- `plans/schemas/public-plan.schema.json` — closed coordination contract.
- `plans/active/` — proposed, active, or blocked tracked plans.
- `plans/archive/` — optional completed, superseded, rejected, or retired plans.
- `.ai/skills/public-plan-coordination/SKILL.md` — reusable selection, update, validation, and handoff procedure.
- `scripts/Test-PublicPlanContracts.ps1` — deterministic public plan and startup readiness validator.
- `tests/test_public_plan_contracts.py` — dependency-free cross-platform structural validation.
- `.github/workflows/public-plan-contracts.yml` — Windows and Linux proof gate.

Plans coordinate work; branches and pull requests transport and review implementation. Application behavior remains in deterministic code and domain contracts.

## Repository-family harness

- `.ai/harness/manifest.json` — central harness paths, proof vocabulary, and generated-evidence policy.
- `.ai/harness/repository-family.registry.json` — exact profiles for AgentSwitchboard, BlacksmithGuild, Web Excel Repair Triage, and SysAdminSuite.
- `.ai/harness/artifact-registry.json` — closed artifact-role registry for family intake, public plans, status, English reports, startup readiness, and handoff compression.
- `.ai/harness/workflows/repository-family-intake.workflow.json` — read-only local-clone discovery and readiness workflow.
- `.ai/harness/schemas/` — run-context, registry, status, and final-handoff schemas.
- `scripts/Get-RepositoryFamilyHarnessStatus.ps1` — read-only local workspace probe; it does not clone, fetch, run providers, or mutate a repository.
- `scripts/Test-RepositoryFamilyHarness.ps1` — deterministic registry, schema, workflow, parser, and safety validator.
- `.github/workflows/repository-family-harness.yml` — Linux and Windows contract gate.

## Canonical skills

- `.ai/skills/repo-intake/SKILL.md` — recover repository truth and select safe work.
- `.ai/skills/bounded-sprint/SKILL.md` — execute one bounded tracked change.
- `.ai/skills/public-plan-coordination/SKILL.md` — coordinate machine-readable work across agents, sessions, waves, branches, and PRs.
- `.ai/skills/gnhf-prompt-compilation/SKILL.md` — compile the copy-ready bounded `gnhf` PowerShell artifact.
- `.ai/skills/powershell-interactive-execution/SKILL.md` — produce directory-first PowerShell safe for interactive submission.
- `.ai/skills/evidence-validation/SKILL.md` — build honest proof and repair validation gaps.
- `.ai/skills/pr-integration/SKILL.md` — reconcile stacked or parallel branches.
- `.ai/skills/runtime-proof/SKILL.md` — advance from static evidence to observed behavior without proof inflation.

## GNHF control plane

- `tooling/gnhf/` — fleet install, routing, bounded sprint launch, contracts, prompts, schemas, fixtures, and runtime evidence.
- `tooling/gnhf/Gnhf.Capability.ps1` — distribution discovery and provider-route capability matrix.
- `tooling/gnhf/Install-ProviderRoutedGnhf.ps1` — transactional capability-driven installer.
- `tooling/gnhf/Start-ProviderRoutedGnhfSprint.ps1` — provider-preflight + bounded GNHF launcher.
- `tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1` — read-only local agent inventory and configuration guidance.
- `tooling/gnhf/schemas/agent-startup-readiness.schema.json` — startup readiness report contract.
- `Repair-ProviderRoutedGnhf.cmd` — operator front door for provider-route repair.
- `.ai/harness/schemas/gnhf-runtime-capability.schema.json` — versioned installed capability contract.
- `Setup-AgentSwitchboard.cmd` — one-click Windows setup front door.
- `AgentSwitchboard.cmd` — startup orientation followed by optional bounded sprint delegation.
- `Run-ChatGPTDesktopGnhfSprint.cmd` — desktop GNHF runtime entrypoint when present on the selected integration branch.
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\gnhf-runtime-capability.json` — installed machine-readable capability document for child repos.
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports\startup` — local startup reports; never tracked repository authority.
- `%LOCALAPPDATA%\AgentSwitchboard\` — installed runtime state and logs; never treat it as tracked repository authority.

## Workstation and terminal integration

- `tooling/wsl/` — Windows/WSL/tmux workspace provisioning, lifecycle, proof, and repair.
- `docs/workstation/` — operator runbooks and proof ceilings.
- workstation scripts may configure a local environment only when the selected workflow explicitly authorizes mutation.

## Governance and adoption

- `docs/governance/repository-family.md` — root/child authority and reviewable propagation model.
- `docs/governance/repository-family-harness.md` — operational profile, readiness, and child-harness expectations.
- `templates/repository-agent-contract/` — child adoption templates; never bulk overwrite a child repository's local law.
- `templates/repository-agent-contract/plans/` — reusable public plan registry, schema, and guidance for child-repository PR adoption.

## Validation

- `scripts/Test-AgentDocumentationContract.ps1` — root contract, canonical skills, triggers, and template checks.
- `scripts/Test-RepositoryFamilyHarness.ps1` — family profile and harness checks.
- `scripts/Test-PublicPlanContracts.ps1` — public plan and startup readiness checks.
- `tooling/gnhf/Test-GnhfFleetContracts.ps1` and more specific downstream validators — GNHF implementation checks on branches that contain those surfaces.

## Generated evidence and reports

Repository-family and startup readiness evidence is untracked. It may contain local directory names, command paths, versions, and Git state, so it must not be committed.

Expected outputs from the family status probe:

- `run-context.json`
- `repository-family-status.json`
- `operator-report.md`
- `final-handoff.json`

Expected outputs from startup readiness:

- `agent-startup-readiness-<timestamp>.json`
- `agent-startup-readiness-<timestamp>.md`

## Proof boundary

A valid family profile proves that AgentSwitchboard knows how to enter and inspect a repository. A valid public plan proves only coordination-contract shape. A startup report proves only local fleet-state and adapter readiness. None of these proves that a child checkout is safe to mutate, a provider is authenticated, a hosted model responded, work was committed, deployment completed, or an operator accepted the result.
