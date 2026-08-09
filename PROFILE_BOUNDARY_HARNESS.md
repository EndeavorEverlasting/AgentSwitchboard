# AgentSwitchboard Profile Boundary Harness

Use this front door when a task could confuse the **device you are on** with the **shell/runtime the command requires**.

This harness exists to keep these identities separate:

- `windows-laptop` -> Windows PowerShell/CMD, or WSL only after an explicit `wsl.exe` + `/bin/bash` proof;
- `android-phone` -> Android/Termux commands such as `agentswitchboard-android`, `Test-AgentSwitchboard-Android-Herdr.sh`, `$PREFIX`, and `pkg install`.

A cloned repository or copied command does not change the device profile.

## Windows entry

```powershell
.\Test-ProfileBoundaryHarness.cmd
```

## Portable entry

```text
python scripts/Test-ProfileBoundaryHarness.py
python tests/test_profile_boundary_harness.py
```

## Before handing off a cross-profile command

Create an `agentswitchboard.command-envelope.v1` file and validate it:

```text
python tooling/harness/profile-boundary/Validate-CommandEnvelope.py --envelope <path>
```

Only a `PASS` may be handed off as executable operator guidance. A `BLOCKED` result owns the next action.

## Canonical files

- `tooling/harness/profile-boundary/manifest.json`
- `tooling/harness/profile-boundary/profile-boundary.registry.json`
- `tooling/harness/profile-boundary/workflow-specs.json`
- `.ai/skills/profile-boundary-routing/SKILL.md`
- `docs/harness/profile-boundary-operational-harness.md`

This additive harness does not replace the device-profile launcher contract, Android Termux harness, active Android Herdr PR, active Windows machine-profile PR, or future environment-capability convergence.
