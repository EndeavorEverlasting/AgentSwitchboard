# Machine Profile Bootstrap

Use this skill when AgentSwitchboard is being installed, repaired, or relocated on a Windows box whose username, corporate naming, hostname, known-folder redirection, OneDrive convention, or repository path may differ from prior machines.

## Rule

Do not guess a repository path from remembered usernames, company names, hostnames, Desktop conventions, or OneDrive folder labels. Run the canonical detector and consume its deterministic recommendation.

## Canonical workflow

1. When the repository is absent, start with `AgentSwitchboard-Technician-Bootstrap.cmd`. It downloads a SHA-256-pinned detector using Windows PowerShell before repository acquisition.
2. When the repository is present, run `Get-AgentSwitchboard-MachineProfile.cmd` or:

   `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1 -Mode Apply`

3. Read `%LOCALAPPDATA%\AgentSwitchboard\machine-profile\machine-profile.json`.
4. Use `repository.recommendedRoot` unless the operator supplied an explicit path or `AGENT_SWITCHBOARD_REPO`.
5. Preserve the precedence encoded by the registry: explicit path, environment override, verified machine binding, verified existing checkout, stable `%USERPROFILE%\dev\AgentSwitchBoard-Live` default.
6. Report `profileId`, confidence, reasons, selected repository root, detected blockers, and the local evidence path.
7. Continue through repository acquisition, PowerShell 7 gate, WSL repair, workstation setup, and live certification without reordering those gates.

## Safety boundaries

- OneDrive and redirected known folders are evidence, not the default root for a new checkout.
- Never commit real machine-profile output. Usernames, hostnames, tenant names, and paths remain local-only.
- Never treat profile classification as package, authentication, provider, launcher, or live-runtime proof.
- Never silently move an existing checkout.
- Never reset, clean, stash, overwrite, or accept an unexpected Git origin to force acquisition.
- Never replace an explicit operator path with an inferred path.

## Validation

Run:

- `python -m unittest tests.test_machine_profile_bootstrap`
- `powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-MachineProfileBootstrap.ps1`
- the existing technician live-cert surface contracts
- `git diff --check`

The proof ceiling is machine observation, deterministic classification, repository-root recommendation, and bootstrap ordering. Live workstation success still requires the repository-owned certification stages.
