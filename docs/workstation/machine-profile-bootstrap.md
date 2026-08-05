# Machine-profile bootstrap

AgentSwitchboard must not guess a repository path from a remembered username, hostname, Desktop layout, OneDrive label, or another machine's checkout.

## Windows environment roles

The focused harness tracks four roles: `personal-windows-laptop`, `desktop-workstation`, `admin-box-1`, and `admin-box-2`. Role identity is explicit or comes from a local binding. It is never inferred from a username, hostname, tenant label, or path. Machines remain distinct roles even when roots match.

The personal-laptop role supports `%USERPROFILE%\Desktop\Dev` with repository leaf `AgentSwitchBoard-Live`; the resolved absolute path stays local-only. Desktop and admin roles require an explicit path, `AGENT_SWITCHBOARD_REPO`, verified binding, or verified checkout.

## Canonical detector

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1 -Mode Apply
```

Local evidence is written beneath `%LOCALAPPDATA%\AgentSwitchboard\machine-profile` as `machine-profile.json`, `machine-profile.env.cmd`, and `machine-profile.env.ps1`.

Resolution precedence is explicit path, `AGENT_SWITCHBOARD_REPO`, verified binding, verified checkout, then detector fallback. Redirected folders and OneDrive are evidence, not authority to invent a root.

## Operational harness

Read `tooling/profiles/windows/harness/machine-profile/manifest.json`, `codebase-map.json`, `environment-role.registry.json`, `known-traps.registry.json`, and `.ai/skills/machine-profile-bootstrap/SKILL.md`.

```cmd
Get-MachineProfileHarnessStatus.cmd
Test-MachineProfileHarness.cmd
```

The pre-commit hook is opt-in and never installed implicitly:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\hooks\Invoke-MachineProfileHarnessPreCommit.ps1
```

## Chosen workspace

```cmd
Bootstrap-AgentSwitchboard-In-Directory.cmd "C:\path\to\Dev"
```

## Failure ordering

Repository identity and path precede PowerShell, WSL repair, setup, and live certification. A failed prerequisite blocks every downstream stage.

In cmd.exe, preserve the owning exit immediately:

```cmd
call ".\Repair-Technician-WSL-Ubuntu.cmd"
set "WSL_RC=%ERRORLEVEL%"
echo WSL_REPAIR_EXIT=%WSL_RC%
```

PowerShell NUL removal must use `.Replace(([char]0).ToString(), [string]::Empty)`, not the ambiguous char/char overload.

## Proof boundary

Harness validation proves component completeness, role routing, local-only path policy, workflows, reports, and deterministic checks. It does not prove WSL health, package installation, launcher behavior, authentication, provider response, or a visible coding environment.
