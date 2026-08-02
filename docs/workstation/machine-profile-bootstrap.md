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
3. verified machine binding;
4. verified existing checkout candidate whose origin can be confirmed;
5. `%USERPROFILE%\dev\AgentSwitchBoard-Live`.

OneDrive and redirected known folders are evidence used to understand the machine. They are not the default location for a new checkout. This prevents different corporate naming and redirection conventions from silently changing the canonical repository root.

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
