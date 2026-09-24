# Machine-profile bootstrap

AgentSwitchboard must not guess a repository path from a remembered username, company, hostname, Desktop layout, or OneDrive folder name.

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
3. verified machine binding when it points at a non-OneDrive/Desktop path;
4. verified existing checkout only when it is the canonical or legacy user-local root;
5. `%USERPROFILE%\dev\AgentSwitchBoard-Live`.

## Path roles (Windows technician profile)

| Role | Canonical location |
| --- | --- |
| Development checkout | `%USERPROFILE%\dev\AgentSwitchBoard-Live` |
| Production / use path | same checkout for repository-owned commands |
| Worktree root | `%LOCALAPPDATA%\AgentSwitchboard\worktrees` |
| Canonical entrypoint | `Pull-And-Run-AgentSwitchboard.cmd` |
| OpenCode bootstrap entrypoint | `Bootstrap-OpenCode-SystemWide.cmd` |

Path relation is **same-path**: editing the technician checkout is production-impacting for repository-owned launchers. Machine-wide OpenCode under Program Files is a separate installed runtime surface, not a second Git checkout.

OneDrive and redirected known folders are evidence used to understand the machine. They are **not** the default location for a new checkout, and an existing Desktop/OneDrive clone is classified `NONCANONICAL_PRESERVE`. Do not invent a second mutable checkout under Desktop, OneDrive, or backup folders.

### PowerShell invocation

PowerShell does not execute bare `.cmd` names from the current directory. From the canonical checkout:

```powershell
Set-Location -LiteralPath "$env:USERPROFILE\dev\AgentSwitchBoard-Live"
.\Bootstrap-OpenCode-SystemWide.cmd
```

If that checkout is missing, acquire it first with `AgentSwitchboard-Technician-Bootstrap.cmd`, then rerun the OpenCode bootstrap from the canonical path.

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

## Bootstrap ordering

The technician bootstrap runs profile detection before repository acquisition using Windows PowerShell, so PowerShell 7 is no longer a prerequisite for cloning the missing repository. PowerShell 7 remains required before WSL repair, workstation setup, and live certification.

Observed usernames, hostnames, tenant names, and paths are never committed. Synthetic fixtures are the only profile identities tracked by the repository.

## Operational role and handoff layer

The detected machine `profileId` and the operator/environment role are different facts. The operational harness preserves four explicit role identities—`personal-windows-laptop`, `desktop-workstation`, `admin-box-1`, and `admin-box-2`—without giving any role its own repository-path policy.

Role selection must be explicit or come from a local machine binding. Every role consumes the current detector's `pathRoles.developmentCheckout`; none may revive the historical `%USERPROFILE%\Desktop\Dev` default or infer a path from a username, hostname, tenant, or OneDrive label.

Repository-only operational status:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-MachineProfileOperationalStatus.ps1
```

Select a role for the local handoff artifact without changing machine state:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-MachineProfileOperationalStatus.ps1 -EnvironmentRoleId admin-box-1
```

Generated status artifacts stay under `%TEMP%\AgentSwitchboard\machine-profile-harness\<run-id>` and are untracked because they may contain a resolved repository path. The tracked role/trap/workflow contracts contain no real machine identity.

Focused validation:

```powershell
python tests/test_machine_profile_operational_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-MachineProfileOperationalHarness.ps1
```

The operational layer does not replace `Get-AgentSwitchboardMachineProfile.ps1`, the current machine-profile registry/schema, the canonical skill, bootstrap launchers, or live-certification owners. PR #64's historical candidate-validator wrappers, pre-commit hook, duplicate skill rewrite, standalone manifest, and Desktop-default role path policy are intentionally retired.
