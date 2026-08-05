# Machine-profile bootstrap

AgentSwitchboard must not guess a repository path from a remembered username, company, hostname, Desktop layout, OneDrive folder name, or another machine's checkout.

## Supported Windows environment roles

The focused operational harness recognizes `personal-windows-laptop`, `desktop-workstation`, `admin-box-1`, and `admin-box-2`. Role identity is explicit or comes from a local machine binding. It is never inferred from a username, hostname substring, tenant label, or path. The desktop workstation and admin boxes remain distinct roles even when two machines share a checkout-root convention.

The personal-laptop role supports an explicit `%USERPROFILE%\Desktop\Dev` workspace with repository leaf `AgentSwitchBoard-Live`; the resolved username and absolute path remain local-only. Desktop and admin roles require an explicit path, `AGENT_SWITCHBOARD_REPO`, verified machine binding, or verified existing checkout.

## Canonical detector

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1 -Mode Apply
```

It records local-only evidence under `%LOCALAPPDATA%\AgentSwitchboard\machine-profile`:

- `machine-profile.json`
- `machine-profile.env.cmd`
- `machine-profile.env.ps1`

The profile observes Windows username, user profile, hostname, user domain, Azure AD/domain join signals, tenant name, known Desktop/Documents locations, commercial and consumer OneDrive roots, available tools, existing checkout candidates, and the recommended repository root.

Repository selection is deterministic:

1. explicit repo path;
2. `AGENT_SWITCHBOARD_REPO`, including a selected root that has not been cloned yet;
3. verified machine binding;
4. verified existing checkout candidate whose origin can be confirmed;
5. `%USERPROFILE%\dev\AgentSwitchBoard-Live`.

OneDrive and redirected known folders are evidence used to understand the machine. They are not the default location for a new checkout. This prevents different corporate naming and redirection conventions from silently changing the canonical repository root.

## Operational harness

Read these focused files before issuing path-sensitive commands:

- `tooling/profiles/windows/harness/machine-profile/manifest.json`
- `tooling/profiles/windows/harness/machine-profile/codebase-map.json`
- `tooling/profiles/windows/harness/machine-profile/environment-role.registry.json`
- `tooling/profiles/windows/harness/machine-profile/known-traps.registry.json`
- `tooling/profiles/windows/harness/machine-profile/workflows/workflow-specs.json`
- `.ai/skills/machine-profile-bootstrap/SKILL.md`

Generate the operator status artifacts and run completeness validation:

```cmd
Get-MachineProfileHarnessStatus.cmd
Test-MachineProfileHarness.cmd
```

The status reporter writes JSON and Markdown even when registered components are missing or malformed. It then returns failure without terminating a caller's PowerShell host.

The pre-commit hook is opt-in and is never installed implicitly:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\hooks\Invoke-MachineProfileHarnessPreCommit.ps1
```

## Validate an unmerged candidate safely

Use the repository-owned candidate command instead of assembling a long ad hoc Git/CMD snippet:

```cmd
Validate-MachineProfileHarnessCandidate.cmd -SourceRepository "C:\path\to\existing-checkout" -WorktreeRoot "C:\path\to\isolated-worktree" -Branch "feature-branch" -ExpectedHead "40-character-sha" -BaseCommit "40-character-base-sha"
```

It preserves dirty or separately owned source work, fetches without force, verifies origin, ancestry, branch head, detached worktree head, and clean state, runs the PowerShell and Python harness validators plus existing machine-profile contracts, runs `git diff --check`, resolves the status files from the tracked manifest and artifact registry, prints the Markdown report, opens it in Notepad, and emits `machine-profile-harness-candidate-validation.json`. Existing matching clean worktrees may be reused; unrelated existing directories fail closed.

## Chosen workspace directory

When the operator explicitly wants AgentSwitchboard beneath a particular `Dev` directory, use the repository-owned wrapper instead of composing a one-off AI command:

```cmd
Bootstrap-AgentSwitchboard-In-Directory.cmd "C:\path\to\Dev"
```

The default repository leaf is `AgentSwitchBoard-Live`, so the resulting checkout is:

```text
C:\path\to\Dev\AgentSwitchBoard-Live
```

A different leaf may be supplied as the second argument:

```cmd
Bootstrap-AgentSwitchboard-In-Directory.cmd "C:\path\to\Dev" AgentSwitchBoard
```

From a machine that does not yet have the repository, download the immutable reviewed wrapper and invoke it:

```cmd
curl.exe -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/3951cfee26f28d55585fde39719ae3e9863b10eb/Bootstrap-AgentSwitchboard-In-Directory.cmd -o "%TEMP%\Bootstrap-AgentSwitchboard-In-Directory.cmd" && call "%TEMP%\Bootstrap-AgentSwitchboard-In-Directory.cmd" "%USERPROFILE%\Desktop\Dev"
```

The wrapper creates the workspace directory when absent, computes the explicit repository root, downloads the canonical technician bootstrap from an immutable commit, verifies its exact Git blob identity, and only then executes it. It does not duplicate Git, WSL, setup, or live-certification logic.

## Failure ordering and shell discipline

Repository identity and path precede PowerShell, WSL repair, setup, and live certification. A failed prerequisite blocks every downstream stage.

Repository CMD wrappers use `setlocal`, clear any caller-defined `ERRORLEVEL` environment variable, invoke the owned command, and capture the dynamic exit immediately. This prevents both later-command clobbering and pseudo-variable shadowing.

Every operator block must name its shell. Do not patch a candidate checkout with an untracked one-liner and then invoke a pull wrapper over it. Commit and push the repair on an isolated branch, fetch without force, verify the exact SHA, and then execute.

PowerShell 7 NUL removal uses the explicit string overload:

```powershell
.Replace(([char]0).ToString(), [string]::Empty)
```

The ambiguous `.Replace([char]0, '')` call binds to the char/char overload and can fail.

## Bootstrap ordering

The technician bootstrap runs profile detection before repository acquisition using Windows PowerShell, so PowerShell 7 is no longer a prerequisite for cloning the missing repository. PowerShell 7 remains required before WSL repair, workstation setup, and live certification.

Observed usernames, hostnames, tenant names, role assignments, and resolved paths are never committed. Synthetic fixtures, role IDs, and environment-variable patterns are the only tracked identities.

## Proof boundary

Harness validation proves component completeness, explicit role routing, local-only path policy, workflow shape, candidate isolation, operator-report rendering, and deterministic checks. It does not prove WSL health, package installation, launcher behavior, authentication, provider response, or a visible working coding environment.
