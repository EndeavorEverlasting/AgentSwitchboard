# Agent Fleet Readiness Boundary

This leaf preserves the still-unique compatibility-boundary semantics from historical PR #79 without restoring its old fleet lifecycle.

## Canonical ownership

- Fleet setup and state: `tooling/gnhf/Setup-AgentSwitchboard.ps1`
- Installed PowerShell operator: `tooling/gnhf/Start-AgentSwitchboard.ps1`
- Adapter/provider startup readiness: `tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1`
- Hermes optional/deferred behavior: current GNHF/Hermes contracts
- Repository/path and shell traps: current machine-profile operational contracts

The leaf owns only the question: **is the installed authority present, and is the optional CMD shim unavailable or blocked?**

## Classification

- `not-bootstrapped`: neither `state.json` nor `Start-AgentSwitchboard.ps1` exists.
- `partial-or-inconsistent`: exactly one installed-authority file exists.
- `cmd-shim-blocked`: both authority files exist, but `agent-switchboard.cmd` is missing or an observed invocation returned `Access is denied` / exit 5.
- `installed-unclassified`: both authority files exist and no blocked-shim evidence is supplied.

`cmd-shim-blocked` is **not** a fleet failure. It routes to the installed PowerShell implementation:

```powershell
pwsh -NoLogo -NoProfile -File "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboard.ps1" -ListAgents
```

Then generate/consume the current canonical startup report:

```powershell
pwsh -NoLogo -NoProfile -File tooling/gnhf/Get-AgentSwitchboardStartupReport.ps1
```

Do not retry the CMD shim after `Access is denied` / exit 5, and do not rerun setup solely to restore the compatibility shim when the installed authority is healthy.

## Read-only classifier

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-AgentFleetReadinessBoundary.ps1
```

To classify an already-observed shim failure without executing the shim again:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Get-AgentFleetReadinessBoundary.ps1 -CmdShimExitCode 5 -CmdShimEvidence 'Access is denied.'
```

The classifier writes local untracked JSON/Markdown under `%TEMP%\AgentSwitchboard\agent-fleet-readiness\<run-id>`.

## Salvage disposition

**Preserved from PR #79:** installed authority pair, `cmd-shim-blocked`, PowerShell `-ListAgents` recovery route, synthetic boundary fixtures.

**Retired/superseded:** old experimental skill, pre-push hook, root `CODEBASE_MAP` edit, Hermes lifecycle, stale-path/shell lifecycle, task pickup/handoff launch lifecycle, and adapter/provider readiness duplication. Current owners remain authoritative.

Source: PR #79 / `feat/harness-agent-fleet-readiness-20260807@b3560cd56e98f7b91dfff2e060c8a27d1c76e76a`. Integration floor: `main@9992f4305021a33dd5ca9916a8f33cf45d8581ff`.

## Validation

```powershell
python tests/test_agent_fleet_readiness_boundary.py
pwsh -NoLogo -NoProfile -File scripts/Test-AgentFleetReadinessBoundary.ps1
pwsh -NoLogo -NoProfile -File tooling/gnhf/Test-GnhfFleetContracts.ps1
pwsh -NoLogo -NoProfile -File tooling/gnhf/Test-HermesSetupContracts.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-MachineProfileOperationalHarness.ps1
git diff --check
```

## Proof ceiling

Repository/CI proof establishes the tracked classifier, synthetic boundary behavior, and ownership separation. It does not prove a workstation is ready, the PowerShell route executed on a policy-restricted workstation, provider authentication, hosted response, or task completion.
