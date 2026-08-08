---
id: environment-capability-routing
version: 0.1.0
status: experimental
---

# Environment Capability Routing

## Trigger

Use when a task crosses platform, host, shell, frontend, SSH, tmux, WSL/Linux/Windows, Android/Termux, orchestration-runtime, or agent-runtime boundaries and the repository needs a safe routing decision before mutation.

This is a harness routing adapter for the current `main` branch. It does not create or modify governance doctrine and does not claim that an unmerged environment-capability implementation exists on `main`.

## Inputs

- requested operator workflow and target environment;
- current repository/branch identity;
- applicable device profile from `.ai/harness/device-profile-registry.json`;
- exact runtime boundary chain when known;
- required proof level and any current operator/runtime evidence.

## Procedure

1. Read `AGENTS.md` and preserve its proof and device-profile boundaries.
2. Resolve the relevant registered device/platform profile before assuming launcher ownership or runtime support.
3. Write the requested chain explicitly: frontend -> transport -> workspace host -> orchestration runtime -> agent runtime, marking any unknown layer unresolved rather than inventing support.
4. If success crosses shell, process, platform, terminal, TUI, GUI, browser, or remote-host boundaries, delegate execution proof to `.ai/skills/end-to-end-runtime-validation/SKILL.md`.
5. If the task is specifically Windows profile launch behavior, also load `.ai/skills/windows-profile-launch-mode-validation/SKILL.md`.
6. Do not treat repository presence, SSH acknowledgement, a same-named tmux session, process presence, package installation, or CI success as proof of end-to-end runtime continuity.
7. Return the selected owner, unresolved layers, required validator(s), proof ceiling, and the exact next executable gate.

## Outputs

- environment boundary chain with known/unresolved layers;
- selected existing canonical skill/validator;
- explicit blockers;
- proof ceiling;
- exact next executable gate.

## Deterministic validation

Use current-main owners only:

```text
pwsh -NoLogo -NoProfile -File scripts/Test-DeviceProfileLauncherContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-EndToEndRuntimeValidationSkill.ps1
```

Add the selected profile/domain validator when the task narrows to one owned surface.

## Forbidden scope

- editing `AGENTS.md` or governance policy;
- claiming an unmerged environment-capability implementation is present on `main`;
- provider authentication, secrets, deployment, live-target mutation, or destructive Git;
- inventing cross-host tmux continuity or native platform runtime support from configuration intent.

## Stop and escalate

Stop the dependent mutation when the target profile, workspace host, transport, runtime owner, credentials, or proof boundary cannot be resolved from current tracked authority. Hand off the exact unresolved layer and the command or operator action that can prove it.
