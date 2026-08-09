# Profile Boundary Operational Harness

## Purpose

This harness prevents AgentSwitchboard from conflating the operator's physical device, outer shell, execution surface, and target profile when generating commands. It was added after an Android/Herdr proof command was handed to a Windows PowerShell session as `bash -lc`, where WSL reported configuration trouble and `/bin/bash` did not exist.

The failure is classified as a routing defect first. The harness does not assume that repairing WSL is the right answer when the intended command belongs on the Android phone. When the destination is known, it can also build a corrected handoff envelope that preserves the original command and changes only the validated device/profile/surface declaration.

## Canonical distinction

| Physical host | Canonical device profile | Normal outer shell | Valid execution surface |
| --- | --- | --- | --- |
| Windows laptop (`windows-laptop`) | `windows` | PowerShell | `windows-powershell`, `windows-cmd`, or explicitly proven `wsl-linux` |
| Android phone (`android-phone`) | `android` | Termux Bash | `android-termux` |

A repository clone, `$HOME` path, tmux session name, or prior-chat command does not change the physical host.

## Windows laptop rule

Use the Windows-native harness front door:

```powershell
.\Test-ProfileBoundaryHarness.cmd
```

Do not paste a bare `bash -lc ...` command into PowerShell and assume it means WSL. Before a Windows-laptop command targets `wsl-linux`, prove the bridge with an explicit `wsl.exe` invocation that reaches `/bin/bash`, then record that PASS in the command envelope.

If WSL emits a configuration warning or cannot execute `/bin/bash`, classify `wsl-bridge-unproved`. Stop downstream Linux commands. Repair WSL only when Linux/WSL is actually the intended execution surface.

## Android phone rule

Android-specific commands belong to the Android phone/Termux context. Indicators include:

- `agentswitchboard-android`;
- `Start-AgentSwitchboard-Android.sh`;
- `Test-AgentSwitchboard-Android-Herdr.sh`;
- `tooling/profiles/android/`;
- `pkg install`;
- `$PREFIX`;
- `/data/data/com.termux`.

If one of those appears in a command envelope whose host is `windows-laptop`, validation blocks it. The recovery is to move the handoff to the phone, not to make the laptop impersonate the phone.

## Command envelope

Before a cross-profile operator handoff, create a local JSON file like:

```json
{
  "schema": "agentswitchboard.command-envelope.v1",
  "hostContext": "windows-laptop",
  "targetProfile": "linux",
  "executionSurface": "wsl-linux",
  "command": "python3 tests/test_operational_harness.py",
  "bridgeProof": {
    "status": "passed",
    "probe": "wsl.exe --exec /bin/bash -lc 'printf WSL_BASH_READY=1'",
    "evidence": "WSL_BASH_READY=1"
  }
}
```

Validate it with:

```powershell
python tooling/harness/profile-boundary/Validate-CommandEnvelope.py --envelope <path>
```

The report prints stable reason codes and a command SHA-256. It does not echo the raw command into persisted evidence.

## Correct a blocked Android transition without rewriting the command

When a BLOCKED report says the command belongs to Android but the source host is the Windows laptop, keep the original command envelope and its matching report together. Build the next-device envelope with:

```powershell
python tooling/harness/profile-boundary/Build-ProfileTransition.py `
  --envelope <source-envelope> `
  --report <blocked-report> `
  --output <android-phone-envelope> `
  --transition-report <transition-report>
```

The builder fails closed unless:

1. the source report is `agentswitchboard.profile-boundary-report.v1`;
2. the source report status is `BLOCKED`;
3. `commandSha256` matches the exact command in the source envelope;
4. the report host/profile/surface matches the source envelope;
5. the blocker is an Android transition;
6. the original target profile is `android`;
7. the rewritten `android-phone + android-termux + android` envelope passes `Validate-CommandEnvelope.py`.

The exact command text is preserved. Only `hostContext`, `targetProfile`, and `executionSurface` are rewritten. The emitted command envelope is still local operator material: keep it untracked, do not use it for secrets, and validate it on the Android phone before execution.

A successful transition report proves routing continuity, not phone execution.

## Failure recovery

When a command fails before its intended repository validator runs:

1. preserve the first failure text;
2. identify the actual physical host and outer shell;
3. reclassify the intended execution surface;
4. do not carry Android commands into WSL or laptop repair;
5. do not carry Windows paths/launchers into Termux;
6. regenerate and revalidate a command envelope after correcting the boundary;
7. if the source command must move to a known Android destination, use `Build-ProfileTransition.py` rather than manually recreating it;
8. continue only after PASS or report the exact external dependency.

For the observed failure `execvpe(/bin/bash) failed: No such file or directory`, the WSL bridge is unproved. If the intended work is Android Herdr evidence, the correct next surface is the Android phone/Termux lane.

## Artifacts

Generated evidence is local and untracked. See `tooling/harness/profile-boundary/artifact-registry.json` for the source command envelope, machine-readable boundary report, corrected profile-transition envelope, transition report, and operator report conventions.

The corrected envelope contains the original raw command because the destination operator needs the same command. Do not use the envelope or transition builder for a command containing credentials or other forbidden evidence.

## Validation

```text
python scripts/Test-ProfileBoundaryHarness.py
python tests/test_profile_boundary_harness.py
python tests/test_device_profile_launcher_contract.py
python tests/test_android_termux_harness.py
git diff --check
```

Hosted CI runs the focused and existing portable contracts on Windows and Ubuntu.

## Hooks

`tooling/harness/profile-boundary/hooks/Invoke-ProfileBoundaryPreCommit.py` is opt-in. It is not installed automatically. It runs the focused completeness/contracts and staged diff hygiene before a commit when an operator chooses to wire it locally.

## Rollback

All implementation in this sprint is additive and isolated under new paths. Removing the profile-boundary files and CI lane restores the previous repository state; no product launcher, device-profile registry, Android harness, Windows harness, credential, or live target is mutated by this harness.

## Proof ceiling

A green profile-boundary harness proves that tracked command-routing contracts reject the tested laptop/phone/shell conflations and that a corrected Android transition envelope remains bound to the exact blocked source command while passing the canonical validator. It does not prove WSL health, Termux installation, tmux continuity, Herdr behavior, provider output, repository mutation, or operator acceptance.
