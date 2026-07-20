# AgentSwitchboard Codebase Map

Load only the smallest surface required by the selected skill, workflow, public plan, or repository-family profile.

## Root coordination

- `AGENTS.md` — universal operating contract and safety floor.
- `CLAUDE.md` — tool adapter subordinate to `AGENTS.md`.
- `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md` — procedure, capability, and deterministic routing catalogs.
- `.ai/agent-contract.json` — canonical contract version, entrypoints, and proof vocabulary.
- `plans/plan-registry.json` — public machine-readable coordination index.
- `AgentSwitchboard.cmd` — readiness-first startup launcher.

## Public plans

- `plans/README.md` — plan-versus-PR boundary and lifecycle.
- `plans/plan-registry.json` — active plan index.
- `plans/schemas/public-plan.schema.json` — closed plan contract.
- `plans/active/` and `plans/archive/` — current and historical coordination.
- `.ai/skills/public-plan-coordination/SKILL.md` — plan procedure.
- `scripts/Test-PublicPlanContracts.ps1` and `tests/test_public_plan_contracts.py` — plan validators.
- `.github/workflows/public-plan-contracts.yml` — Windows and Linux proof gate.

Plans coordinate work; branches and pull requests transport and review implementation. Application behavior remains in deterministic code and domain contracts.

## Offline app harness observer

- `Test-AppHarness.cmd` — one-command offline proof entrypoint.
- `scripts/Test-AppHarness.ps1` — PASS/SKIP/FAIL observer and safe validator aggregator.
- `.ai/harness/app-composition.graph.json` — registered harness nodes and edges.
- `.ai/harness/schemas/app-composition-graph.schema.json` — graph schema.
- `.ai/harness/schemas/app-harness-validation.schema.json` — result schema.
- `.ai/harness/app-harness-report.template.md` — English matrix renderer.
- `tests/test_app_harness_validator.py` and `.github/workflows/app-harness-validation.yml` — cross-platform contracts.

This layer proves registered static topology and bounded offline validation only.

## Runtime event contract

- `docs/governance/runtime-event-contract.md` — event source, typed envelope, observer, handler, successor, and sink doctrine.
- `.ai/harness/runtime-event-contract.policy.json` — machine-readable causality and proof policy.
- `.ai/harness/runtime-event-topology.json` — registered runtime event nodes and directed edges.
- `.ai/harness/schemas/runtime-event-envelope.schema.json` — closed event envelope.
- `.ai/harness/schemas/runtime-event-topology.schema.json` — closed topology registry.
- `.ai/harness/fixtures/runtime-events/` — synthetic root, successor, and broken-chain fixtures.
- `scripts/Test-RuntimeEventContract.ps1` — focused runtime-event-contract validator.
- `tests/test_runtime_event_contract.py` — dependency-free topology and causality checks.
- `.github/workflows/runtime-event-contract.yml` — Windows and Linux proof gate.

The initial topology is contract-only. It does not prove live emission, observation, handling, successor delivery, or sink recording.

## Repository-family harness

- `.ai/harness/manifest.json` — central paths, proof vocabulary, and evidence policy.
- `.ai/harness/repository-family.registry.json` — supported repository profiles.
- `.ai/harness/artifact-registry.json` — artifact roles and proof ceilings.
- `.ai/harness/workflows/repository-family-intake.workflow.json` — read-only clone intake.
- `.ai/harness/schemas/` — run context, status, handoff, app, and event schemas.
- `scripts/Get-RepositoryFamilyHarnessStatus.ps1` — read-only local probe.
- `scripts/Test-RepositoryFamilyHarness.ps1` — registry and safety validator.
- `.github/workflows/repository-family-harness.yml` — family proof gate.

## Canonical skills

- `.ai/skills/repo-intake/SKILL.md`
- `.ai/skills/bounded-sprint/SKILL.md`
- `.ai/skills/public-plan-coordination/SKILL.md`
- `.ai/skills/gnhf-prompt-compilation/SKILL.md`
- `.ai/skills/powershell-interactive-execution/SKILL.md`
- `.ai/skills/evidence-validation/SKILL.md`
- `.ai/skills/pr-integration/SKILL.md`
- `.ai/skills/runtime-proof/SKILL.md`

## GNHF control plane

- `tooling/gnhf/` — distribution, routing, bounded launch, schemas, fixtures, and evidence.
- `tooling/gnhf/Gnhf.Capability.ps1` — capability matrix.
- `tooling/gnhf/Install-ProviderRoutedGnhf.ps1` — transactional installer.
- `tooling/gnhf/Start-ProviderRoutedGnhfSprint.ps1` — provider-preflight and bounded launch.
- `tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1` — read-only agent inventory.
- `Repair-ProviderRoutedGnhf.cmd`, `Setup-AgentSwitchboard.cmd`, and `AgentSwitchboard.cmd` — operator front doors.
- `%LOCALAPPDATA%\AgentSwitchboard\` — installed state and logs; never tracked authority.

## Workstation, governance, and adoption

- `tooling/wsl/` and `docs/workstation/` — Windows, WSL, tmux, and workstation operations.
- `docs/governance/harness-doctrine.md` — commit-required doctrine.
- `docs/governance/runtime-event-contract.md` — runtime event doctrine.
- `docs/governance/repository-family.md` and `docs/governance/repository-family-harness.md` — family governance.
- `templates/repository-agent-contract/` — reviewable child adoption template.

## Validation

- `scripts/Test-HarnessDoctrineContract.ps1`
- `scripts/Test-RuntimeEventContract.ps1`
- `scripts/Test-AgentDocumentationContract.ps1`
- `scripts/Test-RepositoryFamilyHarness.ps1`
- `scripts/Test-PublicPlanContracts.ps1`
- `scripts/Test-AppHarness.ps1`
- `tooling/gnhf/Test-GnhfFleetContracts.ps1` and downstream focused validators.

## Generated evidence and proof boundary

Generated family, startup, app-harness, and runtime-event evidence is untracked. It may contain local paths, versions, Git state, or minimized operational payloads and must remain outside tracked authority unless deliberately reviewed as a public fixture.

Contract validity proves declared shape. Synthetic fixtures prove bounded causality. Neither proves application runtime, provider delivery, external target behavior, deployment, or operator acceptance.
