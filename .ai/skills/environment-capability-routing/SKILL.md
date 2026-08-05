---
id: environment-capability-routing
version: 1.0.0
status: canonical
---

# Environment Capability Routing

## Trigger

Use before installing, configuring, launching, repairing, or certifying AgentSwitchboard across Windows, WSL, Linux, SSH, Android, Termux, tmux, WezTerm, or a new machine/environment whose role is not already proved.

Select this skill when the request says “any environment,” “work from my phone,” “continue from another device,” “auto-configure,” “remote tmux,” or otherwise risks treating a frontend, transport, repository clone, or command presence as a full runtime.

## Inputs

- repository, branch, PR or sprint, lane, owned and forbidden scope;
- exact requested operation and user-visible result;
- current frontend and operating-system environment;
- local or remote transport boundary;
- candidate workspace host;
- candidate orchestration and agent runtimes;
- `.ai/harness/environment-capability.policy.json`;
- `tooling/profiles/harness/environment-capability/environment-capability.registry.json`;
- current device-profile registry and launcher implementation;
- explicit authority for installation, remote mutation, authentication, or runtime execution.

## Procedure

1. Read `tooling/profiles/harness/environment-capability/codebase-map.json` and `docs/governance/environment-capability-contract.md`.
2. Freeze the exact requested user outcome. Do not translate “work from my phone” into “run a local Termux shell” without proving that this satisfies the requested continuity.
3. Run the `environment-intake` workflow without mutation.
4. Identify the five layers separately: frontend, transport, workspace host, orchestration runtime, and agent runtime.
5. Record persistence boundaries and repository identity. Treat tmux identity as host/server/socket scoped, not name scoped.
6. Select exactly one registered topology using `topology-selection.workflow.json`.
7. Calculate the role ceiling. A terminal client cannot become a full runtime host through repository or package presence.
8. Reject unsupported proof promotion before proposing mutation.
9. For SSH, classify the remote OS and shell before constructing remote commands. Do not assume POSIX or Windows semantics from reachability alone.
10. Present blockers and the smallest owned mutation boundary.
11. Install or repair only the selected topology when explicitly authorized.
12. Read back effective state from the actual consumer and workspace host.
13. Use `end-to-end-runtime-validation` for the exact operator command and visible result.
14. Emit the achieved topology, role, proof level, artifact paths, gaps, and one safe next command.

## Outputs

Tracked when implementation changes:

- environment-capability doctrine and policy;
- topology registry, schema, codebase map, artifact registry, workflows, and fixtures;
- platform implementation corrections;
- focused PowerShell and Python validators;
- CI and operator documentation;
- catalog, trigger, capability, manifest, and codebase-map registration.

Generated and untracked when observation is authorized:

- `environment-observation.json`;
- `topology-selection.json`;
- `remote-host-preflight.json`;
- `capability-certification.json`;
- `operator-report.md`;
- `final-handoff.json`.

## Deterministic validation

```powershell
python .\tests\test_environment_capability_harness.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-EnvironmentCapabilityHarness.ps1
python .\tests\test_device_profile_launcher_contract.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-DeviceProfileLauncherContract.ps1
pwsh -NoLogo -NoProfile -File .\scripts\Test-AgentDocumentationContract.ps1
git diff --check
```

## Forbidden scope

- No `repository-implemented` status.
- No claim that cloning AgentSwitchboard establishes its orchestration or agent runtime.
- No claim that local Android tmux resumes a desktop, WSL, or remote tmux session.
- No same-workspace claim from matching session names on different hosts.
- No assumption that Termux is generic Linux or that an SSH target uses a POSIX shell.
- No Android WezTerm assumption.
- No universal installer that mutates before classification.
- No credentials, SSH keys, provider tokens, authentication output, or host-key bypass.
- No remote session creation before the selected topology’s preflight passes, unless the task explicitly owns that repair.
- No runtime proof from static checks, hosted CI, command acknowledgement, or stale evidence.

## Stop and escalate

Stop when the environment, shell, workspace host, repository, tmux server, orchestration runtime, agent runtime, persistence boundary, or authority is unknown and materially affects the requested operation.

Stop when the only available topology has a lower role ceiling than the requested outcome. State that mismatch directly rather than substituting a different experience.

Escalate with the exact observed layers, selected or rejected topology, role ceiling, blockers, evidence paths, preserved state, proof ceiling, and one safe next command.
