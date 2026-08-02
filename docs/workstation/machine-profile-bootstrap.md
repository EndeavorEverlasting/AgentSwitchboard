# Machine-profile bootstrap

AgentSwitchboard must not guess a repository path from a remembered username, company, hostname, Desktop layout, or OneDrive folder name.

The canonical detector is:

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
2. `AGENT_SWITCHBOARD_REPO`;
3. verified machine binding;
4. verified existing checkout candidate;
5. `%USERPROFILE%\dev\AgentSwitchBoard-Live`.

OneDrive and redirected known folders are evidence used to understand the machine. They are not the default location for a new checkout. This prevents different corporate naming and redirection conventions from silently changing the canonical repository root.

The technician bootstrap runs profile detection before repository acquisition using Windows PowerShell, so PowerShell 7 is no longer a prerequisite for cloning the missing repository. PowerShell 7 remains required before workstation setup and live certification.

Observed usernames, hostnames, tenant names, and paths are never committed. Synthetic fixtures are the only profile identities tracked by the repository.
