---
id: profile-boundary-routing
version: 1.1.0
status: experimental
---

# Profile boundary routing

## Trigger

Use before giving an operator any executable command when the task mentions or crosses a phone, Android, Termux, Windows laptop, PowerShell, CMD, WSL, Linux shell, tmux host, or profile-specific launcher. Use it especially when a command was copied from another device or prior chat.

## Required inputs

- physical host context: `windows-laptop` or `android-phone`;
- intended target profile: `windows`, `linux`, or `android`;
- execution surface: `windows-powershell`, `windows-cmd`, `wsl-linux`, or `android-termux`;
- exact command text;
- for Windows -> WSL only, fresh bridge proof showing `wsl.exe` can execute `/bin/bash`.

## Procedure

1. Read `AGENTS.md`, `.ai/harness/device-profile-registry.json`, and `tooling/harness/profile-boundary/manifest.json`.
2. Name the physical host. Do not infer it from `$HOME`, a repository clone, a tmux session name, or remembered chat context.
3. Name the execution surface. The presence of `bash` text does not establish Linux, WSL, or Termux.
4. Materialize an `agentswitchboard.command-envelope.v1` record. Keep it local/untracked when it contains operator-specific context.
5. Validate it with `python tooling/harness/profile-boundary/Validate-CommandEnvelope.py --envelope <path>`.
6. If the host is `windows-laptop` and the surface is `wsl-linux`, require a fresh passed probe that explicitly uses `wsl.exe` and `/bin/bash`. A WSL warning or missing `/bin/bash` blocks downstream Linux commands.
7. If the command contains Android-only markers such as `agentswitchboard-android`, `Test-AgentSwitchboard-Android-Herdr.sh`, `tooling/profiles/android/`, `pkg install`, `$PREFIX`, or `/data/data/com.termux`, require `android-phone + android-termux + android`.
8. A bare `bash -lc` pasted into Windows PowerShell is blocked unless it is replaced by an explicit proven WSL route. Do not assume Git Bash, WSL, or another Bash implementation.
9. When a BLOCKED report proves an Android command was aimed at the wrong host, do not reconstruct the command manually. Run `Build-ProfileTransition.py` with the original envelope and BLOCKED report. The builder requires the report's command SHA-256 to match the source command, preserves the exact command, rewrites only the destination routing fields, and re-runs the canonical validator before emitting the corrected Android-phone envelope.
10. Hand off only an envelope that passes deterministic validation. A corrected Android envelope must still be validated in the `android-phone` / `android-termux` context before execution.
11. Preserve only decision-relevant evidence. Do not copy tokens, device codes, passwords, private keys, or credential-file contents into the envelope/report.

## Outputs

- validated command envelope;
- machine-readable PASS/BLOCKED report with stable reason codes and command SHA-256;
- when a cross-profile correction is safe, a local/untracked corrected command envelope plus profile-transition report cryptographically bound to the source command;
- human operator report naming host, execution surface, target profile, proof ceiling, owner, dependency, and exact next action.

## Deterministic validation

```text
python scripts/Test-ProfileBoundaryHarness.py
python tests/test_profile_boundary_harness.py
python tests/test_device_profile_launcher_contract.py
python tests/test_android_termux_harness.py
git diff --check
```

On Windows, `Test-ProfileBoundaryHarness.cmd` is the repository-owned no-Bash front door.

## Forbidden scope

- do not mutate `AGENTS.md` or invent a new governance principle;
- do not treat WSL repair as a substitute for a command that belongs on the Android phone;
- do not retarget Android/Herdr work to the laptop merely because the phone command is inconvenient;
- do not alter the original command while changing only its device/profile/surface routing;
- do not claim that a static profile-boundary or transition PASS proves WSL, Termux, Herdr, tmux, a provider, or repository mutation actually ran;
- do not install this skill's hook automatically.

## Stop condition

Stop the handoff when the physical host or execution surface is unknown, when WSL bridge proof fails, when Android-only content is aimed at a non-Android host and the source report cannot be cryptographically matched to its command, or when another active PR owns the required mutation. Preserve the blocker and produce the smallest command that advances the correct environment gate.
