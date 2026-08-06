# Technician bootstrap dependency order

The Windows workstation path has one required dependency chain:

```text
WezTerm → WSL/Ubuntu → tmux → agent CLIs → GNHF fleet → Windows Profile launcher
```

WezTerm is the Windows terminal frontend. tmux is installed and executed inside the selected WSL/Ubuntu distribution. The readiness engine must finish the WezTerm version readback and the tmux install/version gate before it may install AGY or OpenCode, build the GNHF fleet, or invoke the Windows Profile launcher.

## Canonical owner

`tooling/profiles/windows/Invoke-TechnicianAgentSwitchboardReady.ps1`

The machine-readable ordering contract is:

`tooling/profiles/windows/harness/technician-ready/bootstrap-order.contract.json`

## Validation

```powershell
python -m unittest tests.test_technician_bootstrap_order -v
pwsh -NoLogo -NoProfile -File scripts/Test-TechnicianBootstrapOrder.ps1 -RootPath .
```

The validators fail when a required gate is missing, duplicated, or reordered. The contract deliberately validates tracked source order without installing packages or launching the workstation.

## Failure boundary

A WezTerm failure stops before WSL/tmux setup. A WSL or tmux failure stops before agent CLIs. Agent CLI failure cannot erase the earlier tmux gate, and no GNHF or launcher step may run before tmux has a successful version readback.

## Proof ceiling

Passing validation proves static repository ordering, unique gate tokens, the owner path, and PowerShell parseability. It does not prove WezTerm installation, WSL mutation, tmux session creation, agent authentication, provider response, visible windows, or operator acceptance.
