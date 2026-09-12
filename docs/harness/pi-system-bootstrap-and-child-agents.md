# Pi system bootstrap and child-agent execution

AgentSwitchboard owns Pi in two deliberately separate layers:

1. **Machine runtime ownership** — the Pi executable and ASB launchers are installed under `Program Files` from the exact tracked standalone upstream release.
2. **User/project execution state** — provider authentication, subscriptions, Pi settings, project trust, model preferences, sessions, packages, extensions, and project resources remain user/project scoped.

This split is intentional. A bootstrapper should make the tool reliably available to every shell without stealing the user's credentials or converting project-local trust into machine policy.

## System-wide bootstrap

The operator front door is:

```cmd
Bootstrap-Pi-SystemWide.cmd
```

It routes through the existing `Pull-And-Run-AgentSwitchboard.cmd bootstrap-pi` dispatcher and executes `tooling/pi/Install-AgentSwitchboardPiSystem.ps1` as one complete PowerShell script. Do not paste individual control-flow fragments into an interactive PowerShell prompt.

The current tracked Pi release is `@earendil-works/pi-coding-agent@0.85.1` / upstream tag `v0.85.1`. Windows uses the official standalone release ZIP rather than a user-global npm installation. The x64 and ARM64 asset names and SHA-256 digests are recorded in `tooling/pi/harness/upstream-verification.json`; `Apply` downloads only the tracked architecture asset, verifies SHA-256, validates the staged `pi.exe --version`, then installs the **whole release archive** under:

```text
%ProgramFiles%\AgentSwitchboard\agents\pi\0.85.1\
```

The whole archive matters because Pi's Windows build includes adjacent docs/assets/native/runtime dependencies in addition to `pi.exe`.

AgentSwitchboard creates these machine launch surfaces:

```text
%ProgramFiles%\AgentSwitchboard\bin\pi.cmd
%ProgramFiles%\AgentSwitchboard\bin\asb-pi.cmd
```

`%ProgramFiles%\AgentSwitchboard\bin` is placed in Machine PATH so the ASB-managed runtime wins over stale user-level Pi shims in newly opened shells. The installer records existing Pi command paths before and after convergence rather than silently assuming PATH identity.

The bootstrap requires PowerShell 7, 64-bit Windows, administrator elevation for `Apply`, the tracked release identity/digest, and Git Bash. Git Bash remains a Pi runtime prerequisite on Windows for the model-facing bash tool. The bootstrap itself does **not** require npm or Node.js.

It fails closed when an unowned install directory or unmanaged ASB launcher occupies the intended path. It does not mutate provider authentication, global Pi settings, project trust, sessions, models, extensions, packages, or Git history.

Non-mutating inspection:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPiSystem.ps1 -Mode Inspect -RootPath .
```

Runtime receipts stay outside the repository under `%LOCALAPPDATA%\AgentSwitchboard\PiHarness\system-bootstrap\runs\...`.

## Why agents should not be configured pair-by-pair

Configuring every agent directly to every other agent creates an N×N integration problem: each agent needs knowledge of every child executable, argument syntax, provider behavior, context format, timeouts, branch policy, and result format. It also makes token control and write authority inconsistent.

The ASB plan is a **hub-and-spoke execution seam**:

```text
parent agent
    |
    | bounded role packet
    v
AgentSwitchboard child invocation contract
    |
    +--> exact managed Pi runtime
    +--> later: OpenCode / AGY / Hermes adapters using the same request/result contract
    |
    v
isolated child context
    |
    | bounded result envelope + evidence
    v
coordinator validates and rejoins
```

The parent does not dump its entire conversation into the child. It writes a minimal packet containing the child role, owned scope, forbidden scope, base identity, expected artifacts, validation responsibility, and exact return contract. This is the primary token-saving mechanism: children receive only what they need, then return a bounded result rather than their full hidden reasoning/transcript.

## Pi child adapter — v1

`tooling/pi/Invoke-AgentSwitchboardPiChild.ps1` implements the first concrete child-agent adapter. It uses only the exact ASB-managed Pi runtime; it never falls back to an arbitrary `pi` found on PATH.

The first transport is one-shot Pi JSON mode rather than a persistent RPC session:

```text
pi --mode json --no-session ... <bounded packet>
```

That already gives the child a separate process/context and JSON events while keeping lifecycle isolation straightforward. Upstream Pi RPC is recorded and intentionally reserved for the next transport version. Persistent RPC should be enabled only after strict LF-delimited JSONL framing, cancellation, session isolation, correlation, crash recovery, and result-envelope behavior have dedicated executable tests.

A read-only child gets only:

```text
read, grep, find, ls
```

A writer child gets:

```text
read, grep, find, ls, write, edit, bash
```

but a writer child is rejected **before provider invocation** unless all of these are true:

- it is on an attached non-default branch;
- the worktree is clean;
- the checkout is a linked isolated Git worktree;
- only one child owns that mutation surface.

Children never merge the default branch. The coordinator owns rejoin, validation, and integration.

Example read-only packet execution:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Invoke-AgentSwitchboardPiChild.ps1 `
  -PromptPath .\packet.txt `
  -RepositoryPath C:\path\to\repo `
  -Role architect `
  -WriteMode read-only
```

Provider/model identifiers may be supplied, but provider secrets are not parameters. Pi uses the operator's existing user-scoped credentials/subscription state.

The adapter writes local evidence under `%LOCALAPPDATA%\AgentSwitchboard\PiHarness\child-runs\...`. `child-result.json` contains a bounded final result and repository/runtime evidence. The raw Pi JSON event stream is also local-only and can contain prompt/model transcript content; it must not be committed.

A zero process exit is not enough. The adapter requires an `agent_end` event and marks the successful transport result `completed-unvalidated`. Task-specific completion remains a coordinator claim only after artifact, diff, test, commit, and integration evidence is checked independently.

## Where Continuum fits

Continuum remains the higher-level workflow/prompt-packet owner. AgentSwitchboard owns executable discovery, machine bootstrap, child-process launch semantics, isolation, timeouts, and bounded evidence. This avoids turning ASB into a second workflow engine while still giving every orchestrator one deterministic way to invoke coding agents.

## Route status

The repository's broader Pi routes — single-agent, opinion fusion, and autovalidate — remain `contract-only`. This sprint implements the runtime and child-process primitives underneath them; it does not claim that fusion/autovalidation quality or parallel provider execution is already field-proven.

## Validation

```powershell
python -m unittest tests.test_pi_system_bootstrap -v
python tests/test_pi_harness_contracts.py
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPiSystem.ps1 -Mode Inspect -RootPath .
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1 -NoWrite
```

Windows CI additionally parses the touched PowerShell surfaces and exercises non-mutating system inspection. CI does not perform `Apply`, provider login, or a paid/model-backed child run.

## Proof ceiling

Repository validation proves the tracked Pi release identity, installer/launcher contract, digest enforcement, machine/user ownership boundary, child request/result contract, writer isolation guards, bounded child process behavior, and deterministic validators. A physical workstation still must run `Bootstrap-Pi-SystemWide.cmd` to prove machine mutation and fresh-shell PATH behavior. Provider authentication and at least one real delegated child run are separate runtime gates before nested-agent execution can be called field-proven.
