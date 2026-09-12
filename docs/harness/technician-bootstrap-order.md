# Technician bootstrap dependency order

The Windows workstation path has one required dependency chain:

```text
WezTerm → WSL/Ubuntu → tmux → AgentSwitchboard readiness engine
```

The repository-owned front door runs a bounded prerequisite gate before the existing readiness engine. The prerequisite gate installs or resolves WezTerm, reads back its version, resolves the selected WSL/Ubuntu distribution, installs tmux when needed, and requires a successful `tmux -V` readback. Only then may the front door invoke the AgentSwitchboard readiness engine, where agent CLIs, the GNHF fleet, and the Windows Profile launcher are owned.

## Canonical owners

- Front door: `Technician-AgentSwitchboard-Ready.cmd`
- Prerequisite gate: `tooling/profiles/windows/Invoke-TechnicianBootstrapPrerequisites.ps1`
- Higher runtime: `tooling/profiles/windows/Invoke-TechnicianAgentSwitchboardReady.ps1`
- Contract: `tooling/profiles/windows/harness/technician-ready/bootstrap-order.contract.json`

## Validation

```powershell
python -m unittest tests.test_technician_bootstrap_order -v
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrder.ps1 -RootPath .
```

The validators fail when bootstrap gates are missing, duplicated, or reordered; when the front door can invoke the runtime engine before the prerequisite command succeeds; or when higher runtime setup leaks into the prerequisite gate.

## Failure boundary

A WezTerm failure stops before WSL/tmux setup. A WSL or tmux failure stops at the prerequisite gate. The front door propagates that nonzero exit and does not invoke the AgentSwitchboard readiness engine.

## Proof ceiling

Passing validation proves static front-door ordering, prerequisite ownership, token uniqueness, and PowerShell parseability. It does not prove WezTerm installation, WSL mutation, tmux session creation, agent authentication, provider response, visible windows, or operator acceptance.
