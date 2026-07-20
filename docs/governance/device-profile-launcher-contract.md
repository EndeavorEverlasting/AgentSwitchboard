# Device Profile Launcher Contract

Machine-readable authority: `.ai/harness/device-profile-launcher.policy.json`.

This contract governs platform-specific workstation launch surfaces. It extends the commit-required harness doctrine and runtime-event contract; it does not grant installation, runtime, target-mutation, deployment, or release authority.

## Profile model

AgentSwitchboard owns separate platform profiles:

- **Windows Profile** — the first concrete profile. Its terminal frontend is WezTerm and its canonical lifecycle operation is `open-or-activate`.
- **Linux Profile** — a separate profile with its own future implementation and certification. Windows implementation details may not be copied into it by assumption.
- **Android Profile** — a separate profile whose client, lifecycle, and configuration may differ. A Windows or Linux launcher may not be relabeled as Android support.

The family goal is a consistent managed terminal/workspace experience across devices. Platform profiles preserve one ownership model while allowing platform-specific implementation.

## Canonical ownership

For each profile, exactly one repository owns lifecycle decision logic. For the Windows Profile:

- canonical owner: `EndeavorEverlasting/AgentSwitchboard`;
- canonical operation: `open-or-activate`;
- canonical source contract: `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1`;
- installed contract path: `%LOCALAPPDATA%\AgentSwitchboard\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1`;
- consumer and certifier: `EndeavorEverlasting/SysAdminSuite`.

The source and installed paths are contract targets. Until deterministic implementation and runtime evidence land, the profile remains `contract-only`.

## Idempotent open-or-activate behavior

Repeated calls with the same profile and workspace identity converge on one logical workspace.

1. Resolve the selected profile and canonical launcher version.
2. Discover the exact owned workspace identity.
3. When an owned workspace already exists, activate it.
4. Otherwise, open it once.
5. Return one explicit outcome: `opened`, `activated`, `blocked`, or `failed`.
6. Record enough evidence to distinguish activation from a new launch.

The launcher may not create duplicate logical workspaces merely because a raw process or window was not found by a weak heuristic. Process exit code alone is not proof of open-or-activate behavior.

## Delegation-only consumers

Desktop shortcuts, repository wrappers, SysAdminSuite, and other consumers may:

- locate the certified AgentSwitchboard launcher;
- validate the expected profile ID, contract version, and launcher identity;
- pass reviewed profile/workspace arguments;
- preserve the canonical exit code and result artifact;
- report a clear blocker when the canonical launcher is absent or uncertified.

They may not:

- call `wezterm`, `wezterm.exe`, or `wezterm-gui.exe` as an independent fallback;
- recreate session discovery, window detection, tmux attachment, process ownership, activation, or duplicate-prevention logic;
- generate a shortcut that targets consumer-owned lifecycle code;
- silently substitute a different profile or platform implementation;
- claim certification from file presence or process exit alone.

A shortcut is presentation only. It points to the installed canonical profile launcher and contains no competing lifecycle decision logic.

## SysAdminSuite certification

SysAdminSuite consumes and certifies the Windows Profile; it does not own it. Certification must verify:

- the expected AgentSwitchboard profile ID and contract version;
- the canonical launcher path and identity;
- exact delegate-only invocation;
- no raw WezTerm fallback;
- no consumer-owned open, activate, session, or duplicate-prevention branch;
- valid `opened`, `activated`, `blocked`, and `failed` fixtures;
- idempotence across repeated equivalent invocations;
- honest proof level and proof ceiling.

A missing or uncertified AgentSwitchboard launcher is `blocked`, not permission for SysAdminSuite to launch WezTerm itself.

## Runtime-event composition

A delivered launcher must register and observe the event chain:

`profile request -> canonical launcher resolved -> workspace discovered -> opened or activated -> terminal result -> evidence sink`

The runtime event contract supplies correlation, causation, immutable envelopes, successor rules, and sink requirements. Static profile doctrine proves ownership and contract shape only. Synthetic fixtures prove idempotence contracts only. Runtime proof requires observed correlated evidence for both the `opened` and `activated` paths.

## Action-commitment rule

A prompt, title, mission, or expected output that claims it will install, build, configure, repair, certify, or deploy a platform profile or launcher must require corresponding tracked implementation and proof.

A valid execution contract names:

- profile ID and canonical owner;
- canonical entrypoint and installed path;
- consumer/certifier;
- owned and forbidden launch surfaces;
- open-or-activate identity and outcomes;
- topology and artifacts;
- validators and runtime evidence required;
- commit or GitHub evidence;
- achieved proof level and ceiling.

A rewritten prompt, architecture note, plan, or handoff is not a substitute for requested implementation.

## Validation

Run:

```powershell
pwsh -NoLogo -NoProfile -File .\scripts\Test-DeviceProfileLauncherContract.ps1
python .\tests\test_device_profile_launcher_contract.py
```

Then run the wider doctrine and aggregate harness validators. These checks never launch WezTerm, WSL, tmux, AgentSwitchboard, SysAdminSuite, a browser, or a provider.