# AgentSwitchboard Codebase Map

Load only the smallest surface required by the selected skill, workflow, public plan, environment topology, or repository-family profile.

## Root coordination

- `AGENTS.md` — universal operating contract and safety floor.
- `CLAUDE.md` — tool adapter subordinate to `AGENTS.md`.
- `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md` — procedure, capability, and deterministic routing catalogs.
- `.ai/agent-contract.json` — canonical contract version, entrypoints, and proof vocabulary.
- `plans/plan-registry.json` — public machine-readable coordination index.
- `AgentSwitchboard.cmd` — readiness-first Windows startup launcher.

## Environment capability and continuity harness

Use this surface before any cross-platform installer, launcher, auto-configuration, phone-access, SSH, remote-tmux, WSL/Linux/Windows, Termux, or “any environment” claim.

- `docs/governance/environment-capability-contract.md` — five-layer doctrine, role ceilings, status vocabulary, host-scoped tmux identity, remote preflight, and false-proof rejection.
- `.ai/harness/environment-capability.policy.json` — machine-readable invariants and Android capability ceiling.
- `tooling/profiles/harness/environment-capability/codebase-map.json` — focused harness map.
- `tooling/profiles/harness/environment-capability/environment-capability.registry.json` — registered Windows and Android topologies.
- `tooling/profiles/harness/environment-capability/schemas/environment-capability.schema.json` — topology registry schema.
- `tooling/profiles/harness/environment-capability/artifact-registry.json` — local observation, selection, preflight, certification, report, and handoff evidence.
- `tooling/profiles/harness/environment-capability/workflows/` — read-only intake, topology selection, and bounded certification workflows.
- `tooling/profiles/harness/environment-capability/fixtures/` — valid Windows/Android roles and invalid full-runtime, cross-host tmux-name, and unclassified-SSH claims.
- `.ai/skills/environment-capability-routing/SKILL.md` — canonical procedure.
- `scripts/Test-EnvironmentCapabilityHarness.ps1` and `tests/test_environment_capability_harness.py` — deterministic Windows/Linux contracts.
- `docs/harness/environment-capability-harness.md` — operator guide and corrective Android analysis.
- `.github/workflows/environment-capability-harness.yml` — exact-head proof gate.

The required layer chain is:

`frontend -> transport -> workspace host -> orchestration runtime -> agent runtime`

The Android implementation is `terminal-client-implemented`. Phone-local tmux is `local-shell-only` and `device-local-only`; cross-device continuity requires both clients to attach to the same separately classified workspace host and tmux server/session identity. Native Android AgentSwitchboard orchestration is unimplemented and agent/provider runtime is unproved.

## Public plans

- `plans/README.md` — plan-versus-PR boundary and lifecycle.
- `plans/plan-registry.json` — active plan index.
- `plans/schemas/public-plan.schema.json` — closed plan contract.
- `plans/active/` and `plans/archive/` — current and historical coordination.
- `.ai/skills/public-plan-coordination/SKILL.md` — plan procedure.
- `scripts/Test-PublicPlanContracts.ps1` and `tests/test_public_plan_contracts.py` — plan validators.
- `.github/workflows/public-plan-contracts.yml` — Windows and Linux proof gate.

Plans coordinate work; branches and pull requests transport and review implementation. Application behavior remains in deterministic code and domain contracts.

## End-to-end runtime validation

- `.ai/skills/end-to-end-runtime-validation/SKILL.md` — exact operator-path runtime procedure across shell, process, platform, terminal, TUI, and GUI boundaries.
- `scripts/Test-EndToEndRuntimeValidationSkill.ps1` — deterministic skill, routing, contract, and proof-boundary validator.
- `.github/workflows/agent-documentation-contract.yml` — Windows and Linux parser, doctrine, skill, documentation, diff-hygiene, and clean-checkout gate.
- `.ai/agent-contract.json` — canonical entrypoint, generated-evidence policy, and `end-to-end-runtime` proof level.

Environment topology selection precedes end-to-end execution. This skill requires child stdout and stderr, exit identity, effective-state readback, user-visible observation, and idempotence or rollback proof when applicable. Static inspection, passing CI, configuration intent, process creation, SSH acknowledgement, repository presence, or a parent exit code cannot establish end-to-end runtime success.

## Offline app harness observer

- `Test-AppHarness.cmd` — one-command offline proof entrypoint.
- `scripts/Test-AppHarness.ps1` — PASS/SKIP/FAIL observer and safe validator aggregator.
- `.ai/harness/app-composition.graph.json` — registered harness nodes and edges.
- `.ai/harness/schemas/app-composition-graph.schema.json` — graph schema.
- `.ai/harness/schemas/app-harness-validation.schema.json` — result schema.
- `.ai/harness/app-harness-report.template.md` — English matrix renderer.
- `tests/test_app_harness_validator.py` and `.github/workflows/app-harness-validation.yml` — cross-platform contracts.

This layer proves registered static topology and bounded offline validation only.

## App output context engine

- `Contextualize-AppOutput.cmd` — Windows operator entrypoint.
- `tooling/context/Contextualize-AppOutput.py` — deterministic text/JSON/JSONL parser, redactor, signal classifier, prompt-kit ranker, and artifact renderer.
- `.ai/harness/workflows/app-output-contextualization.workflow.json` — inputs, steps, outputs, and guardrails.
- `.ai/harness/schemas/app-output-context.schema.json` — compact packet schema.
- `.ai/skills/app-output-contextualization/SKILL.md` — reusable agent procedure.
- `scripts/Test-AppOutputContextEngine.ps1` and `tests/test_app_output_context_engine.py` — focused completeness and behavior proof.
- `.ai/harness/fixtures/app-output-context/` — public synthetic output and prompt-registry fixture.
- `docs/harness/app-output-context-engine.md` — operator guide.
- `.github/workflows/app-output-context-engine.yml` — Windows and Linux contract gate.

This engine reads supplied output only. It does not launch apps or providers, stores no raw output in its artifacts, and never crosses the regular-AI/GNHF execution-surface boundary.

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

## Device profile launcher contract

- `docs/governance/device-profile-launcher-contract.md` — canonical profile ownership, environment topology, open-or-activate, delegation, certification, and proof doctrine.
- `.ai/harness/device-profile-launcher.policy.json` — machine-readable one-owner, Android role ceiling, remote preflight, and host-scoped idempotence rules.
- `.ai/harness/device-profile-registry.json` — Windows, Linux, and Android profile registry.
- `.ai/harness/schemas/device-profile-registry.schema.json` — capability-aware registry schema.
- `.ai/harness/fixtures/device-profiles/` — valid SysAdminSuite delegation and invalid competing-owner fixtures.
- `scripts/Test-DeviceProfileLauncherContract.ps1` — focused ownership, environment-boundary, and action-commitment validator.
- `tests/test_device_profile_launcher_contract.py` — dependency-free profile and delegation checks.
- `.github/workflows/device-profile-launcher-contract.yml` — Windows and Linux proof gate.

The Windows Profile is WezTerm-backed and contract-only. Its canonical source is `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1`; SysAdminSuite consumes and certifies it through a separate PR.

The Android profile is a Termux terminal client. `Bootstrap-AgentSwitchboard-Termux.sh` installs only the terminal-client floor. `tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh` exposes `status`, `local-shell`, and a preflighted `remote` POSIX/tmux adapter. It does not provide a native Android GNHF, coding-agent, provider, or authentication runtime.

## Windows Profile launch-mode harness

- `tooling/profiles/windows/harness/launch-modes/codebase-map.json` — focused structure, commands, entrypoints, and known traps.
- `tooling/profiles/windows/harness/launch-modes/launch-mode.registry.json` — default `open-or-activate`, explicit named `new-instance`, one-window limits, identity convergence, and duplicate-detection policy.
- `tooling/profiles/windows/harness/launch-modes/composition.graph.json` — request, trigger, skill, workflow, validator, artifact, report, and handoff topology.
- `tooling/profiles/windows/harness/launch-modes/workflows/` — intake, open-or-activate verification, new-instance verification, and duplicate-window diagnosis.
- `tooling/profiles/windows/harness/launch-modes/artifact-registry.json` — local run context, before/after inventories, results, English reports, and handoffs.
- `tooling/profiles/windows/harness/launch-modes/schemas/windows-launch-mode-harness.schema.json` — run-context, state-snapshot, result, and handoff contracts.
- `tooling/profiles/windows/harness/launch-modes/fixtures/` — valid workspace activation, valid named separate instance, and invalid duplicate burst.
- `.ai/skills/windows-profile-launch-mode-validation/SKILL.md` — scoped selection and validation procedure.
- `tooling/profiles/windows/Get-WindowsProfileLaunchModeStatus.ps1` — read-only English and JSON repository readiness report.
- `tooling/profiles/windows/hooks/Invoke-WindowsProfileLaunchModePreCommit.ps1` — opt-in contract, staged-diff, and generated-evidence gate; never installed implicitly.
- `scripts/Test-WindowsProfileLaunchModeHarness.ps1` and `tests/test_windows_profile_launch_mode_harness.py` — cross-platform completeness and behavior contracts.
- `docs/harness/windows-profile-launch-mode-harness.md` — operator-facing working state, gaps, workflows, artifact policy, and proof ceiling.
- `.github/workflows/windows-profile-launch-mode-harness.yml` — Windows and Linux exact-head proof gate.

The default mode converges one workspace identity to one visible window on one workspace host. An explicit named new instance requires exactly one additional top-level WezTerm window, a distinct frontend process, and a unique tmux session; repeating that instance ID must activate it. Two windows attached to the same tmux server/session are duplicate views, not separate instances. This harness does not prove live launcher behavior.

## tmux new-instance desktop shortcut harness

The focused implementation map is `tooling/profiles/windows/harness/tmux-new-instance-shortcut/codebase-map.json`. It indexes the CMD installer, canonical launcher, manifest, workflows, artifact registry, schema, fixtures, skill, validator, status report, hook, operator guide, and Windows/Linux CI. The tracked `new-instance` and `open-or-activate` slices remain unproved on the operator workstation.

## Repository-family harness

- `.ai/harness/manifest.json` — central paths, proof vocabulary, environment topology, and evidence policy.
- `.ai/harness/repository-family.registry.json` — supported repository profiles.
- `.ai/harness/artifact-registry.json` — artifact roles and proof ceilings.
- `.ai/harness/workflows/repository-family-intake.workflow.json` — read-only clone intake.
- `.ai/harness/schemas/` — run context, status, handoff, app, event, device-profile, environment-capability, and app-output schemas.
- `scripts/Get-RepositoryFamilyHarnessStatus.ps1` — read-only local probe.
- `scripts/Test-RepositoryFamilyHarness.ps1` — registry and safety validator.
- `.github/workflows/repository-family-harness.yml` — family proof gate.

## Canonical skills

- `.ai/skills/repo-intake/SKILL.md`
- `.ai/skills/bounded-sprint/SKILL.md`
- `.ai/skills/environment-capability-routing/SKILL.md`
- `.ai/skills/public-plan-coordination/SKILL.md`
- `.ai/skills/gnhf-prompt-compilation/SKILL.md`
- `.ai/skills/powershell-interactive-execution/SKILL.md`
- `.ai/skills/evidence-validation/SKILL.md`
- `.ai/skills/pr-integration/SKILL.md`
- `.ai/skills/runtime-proof/SKILL.md`
- `.ai/skills/end-to-end-runtime-validation/SKILL.md`
- `.ai/skills/windows-profile-launch-mode-validation/SKILL.md`
- `.ai/skills/app-output-contextualization/SKILL.md`

## GNHF control plane

- `tooling/gnhf/` — Windows-first distribution, routing, bounded launch, schemas, fixtures, and evidence.
- `tooling/gnhf/Gnhf.Capability.ps1` — capability matrix.
- `tooling/gnhf/Install-ProviderRoutedGnhf.ps1` — transactional installer.
- `tooling/gnhf/Start-ProviderRoutedGnhfSprint.ps1` — provider-preflight and bounded launch.
- `tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1` — read-only agent inventory.
- `Repair-ProviderRoutedGnhf.cmd`, `Setup-AgentSwitchboard.cmd`, and `AgentSwitchboard.cmd` — Windows operator front doors.
- `%LOCALAPPDATA%\AgentSwitchboard\` — installed Windows state and logs; never tracked authority.

Repository presence on Android, Linux, or a remote host does not imply this control plane has been ported or configured there.

## Workstation, governance, and adoption

- `tooling/wsl/` and `docs/workstation/` — Windows, WSL, tmux, Android terminal-client, and workstation operations.
- `docs/governance/harness-doctrine.md` — commit-required doctrine.
- `docs/governance/runtime-event-contract.md` — runtime event doctrine.
- `docs/governance/environment-capability-contract.md` — cross-environment role and continuity doctrine.
- `docs/governance/device-profile-launcher-contract.md` — device-profile launcher doctrine.
- `docs/governance/repository-family.md` and `docs/governance/repository-family-harness.md` — family governance.
- `templates/repository-agent-contract/` — reviewable child adoption template.

## Pi operational harness

- `tooling/pi/harness/codebase-map.json` — Pi-specific structure, entrypoints, commands, and known traps.
- `tooling/pi/harness/pi-adapter.registry.json` — contract-only routes, upstream verification state, project-local configuration policy, runtime evidence requirements, and privacy gates.
- `tooling/pi/harness/workflows/` — task intake, independent opinion fusion, and architect-owned autovalidation workflows.
- `tooling/pi/harness/artifact-registry.json` — local-only run context, attributed role outputs, fusion results, validation ledgers, reports, and handoffs.
- `tooling/pi/harness/schemas/pi-harness-contracts.schema.json` — run context, execution identity, role-output, fusion-result, and validation-ledger contracts.
- `.ai/skills/pi-fusion-orchestration/SKILL.md` — experimental bounded Pi orchestration procedure.
- `tooling/pi/Get-PiHarnessStatus.ps1` — English and JSON read-only repository status.
- `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1` — opt-in completeness, Python-contract, staged-diff, and generated-evidence check; never installed implicitly.
- `scripts/Test-PiHarnessCompleteness.ps1` and `tests/test_pi_harness_contracts.py` — focused cross-platform harness contracts.
- `docs/harness/pi-operational-harness.md` — operator guide, working state, blockers, gaps, artifact policy, and proof ceiling.
- `.github/workflows/pi-harness-contract.yml` — Windows and Linux proof gate.

This slice makes AgentSwitchboard the policy, routing, evidence, validation, and handoff layer around a future Pi runtime. It does not install Pi, execute an extension, contact a provider, classify a local endpoint as private, or claim fusion or autovalidation success.

## Validation

- `scripts/Test-HarnessDoctrineContract.ps1`
- `scripts/Test-EnvironmentCapabilityHarness.ps1`
- `scripts/Test-EndToEndRuntimeValidationSkill.ps1`
- `scripts/Test-RuntimeEventContract.ps1`
- `scripts/Test-DeviceProfileLauncherContract.ps1`
- `scripts/Test-WindowsProfileLaunchModeHarness.ps1`
- `scripts/Test-TmuxNewInstanceShortcutHarness.ps1`
- `scripts/Test-AppOutputContextEngine.ps1`
- `scripts/Test-PiHarnessCompleteness.ps1`
- `scripts/Test-AgentDocumentationContract.ps1`
- `scripts/Test-RepositoryFamilyHarness.ps1`
- `scripts/Test-PublicPlanContracts.ps1`
- `scripts/Test-AppHarness.ps1`
- `tooling/gnhf/Test-GnhfFleetContracts.ps1` and downstream focused validators.

## Generated evidence and proof boundary

Generated family, startup, app-harness, app-output-context, runtime-event, environment-capability, device-profile, Windows launch-mode, tmux shortcut, and Pi evidence is untracked. End-to-end runtime evidence is also local-operational and untracked unless deliberately minimized and reviewed as a public fixture. Evidence may contain local paths, versions, Git state, minimized operational payloads, remote host classification, or attributed model identities and must remain outside tracked authority unless deliberately reviewed as a public fixture.

Contract validity proves declared shape. Synthetic fixtures prove bounded causality, ownership, topology classification, false-proof rejection, contextualization, launch-mode classification, shortcut allocation, or workflow semantics. Neither proves application runtime, an exact operator path, a phone installation, remote SSH compatibility, tmux attachment, an open-or-activate result, a distinct WezTerm instance on the operator workstation, duplicate prevention, SysAdminSuite certification, Pi installation, extension compatibility, provider delivery, endpoint privacy, model quality, external target behavior, deployment, or operator acceptance.
