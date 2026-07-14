# WSL Agent Workstation Environment

This document describes the AgentSwitchboard WSL workstation bootstrap system: what it installs, how it reports state, and what constraints it respects.

## Overview

The WSL bootstrap enables AgentSwitchboard to establish a Linux developer environment inside Windows Subsystem for Linux. It installs WSL features, Ubuntu distributions, Linux packages, coding-agent CLIs, tmux, and repository clones while preserving existing user configuration and emitting structured evidence of every action.

## Architecture

```text
Windows Side                          Linux Side (WSL)
+-----------------------------+      +---------------------------+
| Install-AgentSwitchboardWsl |----->| bootstrap-agent-workstation|
| (PowerShell 7)              |      | (bash)                    |
+-----------------------------+      +---------------------------+
| - Feature detection         |      | - Package installation    |
| - Distribution management   |      | - Agent installation      |
| - Template deployment       |      | - Repository cloning      |
| - State discovery           |      | - Probe verification      |
| - Manifest validation       |      | - Dotfile backup          |
+-----------------------------+      +---------------------------+
| Get-WslWorkstationState     |      |                           |
| (read-only discovery)       |      |                           |
+-----------------------------+      +---------------------------+
```

## Components

### Manifest: `wsl-workstation.example.json`

Defines the desired workstation state:

- **distribution**: target WSL distribution name and preferred version
- **linuxDevRoot**: Linux filesystem path for development repositories (default `~/dev`)
- **packages**: apt packages to install
- **agents**: coding-agent CLIs with install and probe commands
- **repositories**: repos to clone into the dev root
- **dotfilePolicy**: backup rules for managed configuration files
- **wezterm**: WezTerm WSL integration settings
- **tmux**: tmux configuration settings
- **rebootPolicy**: reboot handling rules
- **pathMapping**: Windows-to-WSL path mapping preferences

### Discovery: `Get-WslWorkstationState.ps1`

Read-only script that reports:

- WSL feature availability
- Distribution list with state and version
- Default distribution identification
- Docker Desktop detection (excluded from developer distributions)
- Per-distribution tool probes: git, tmux, node, npm, agy, opencode, goose
- systemd state detection
- Structured JSON output with `schemaVersion: 1`

### Installer: `Install-AgentSwitchboardWsl.ps1`

Bounded installer that:

- Validates manifest schema version
- Supports `-WhatIf` and `-PlanOnly` for dry-run mode
- Enables WSL features when missing (requires elevation)
- Installs distributions when missing
- Reports reboot requirements instead of pretending completion
- Copies and executes the Linux bootstrap script inside WSL
- Clones enabled repositories with remote verification
- Deploys configuration templates with dotfile backup
- Writes transcript, setup-summary.json, command-results.json, and repo-results.json

### Linux Bootstrap: `scripts/bootstrap-agent-workstation.sh`

Executed inside WSL by the installer:

- Strict error handling (`set -euo pipefail`)
- Detects and uses apt for package management
- Creates the configured development root
- Installs declared packages
- Installs declared agents (opencode, agy, goose) only when missing
- Probes every installed command
- Clones enabled repositories, reusing existing correct clones
- Reports path collisions and wrong remotes without deleting
- Never stores credentials

### Templates

- **`templates/tmux.conf`**: managed tmux defaults with TPM plugin support
- **`templates/wezterm.lua`**: WezTerm config launching the selected WSL distribution

Both templates are deployed with backup of existing user configuration.

### Validator: `Test-WslBootstrapContracts.ps1`

Deterministic contract validator that checks:

- Required file presence
- PowerShell parse validity
- JSON parse validity
- Manifest schema structure
- Bootstrap script conventions
- Installer safety properties
- State discovery properties
- Fixture correctness for all defined scenarios

## Fixture Scenarios

| Fixture | Scenario |
|---------|----------|
| `wsl-state.absent.json` | WSL not installed |
| `wsl-state.installed-no-ubuntu.json` | WSL present but no distributions |
| `wsl-state.ubuntu-stopped.json` | Ubuntu installed but stopped |
| `wsl-state.ubuntu-configured.json` | Ubuntu running with tools installed |
| `wsl-state.docker-desktop-only.json` | Only docker-desktop present |
| `setup-summary.valid-completed.json` | Successful setup |
| `setup-summary.reboot-required.json` | Setup blocked by reboot |
| `setup-summary.plan-only.json` | Dry-run / plan mode |
| `setup-summary.invalid-failed-probe.json` | Setup with failed probes |
| `repo-result.correct-remote.json` | Repository already exists correctly |
| `repo-result.wrong-remote.json` | Repository exists with wrong remote |
| `wsl-manifest.valid.json` | Valid manifest |
| `wsl-manifest.invalid-schema-version.json` | Manifest with wrong schema version |
| `wsl-state.missing-schema-version.json` | State missing schema version |

## Safety Properties

- No embedded API keys, provider tokens, or credentials
- No automatic provider login
- No WSL unregister or reset
- No deletion of existing distributions, home directories, or dotfiles
- Existing dotfiles backed up before overwriting
- Repository cloning reports collisions without deletion
- Reboot requirements reported honestly
- Plan mode makes no changes
- docker-desktop never mistaken for a developer distribution

## Path Mapping

The preferred development root is inside the Linux filesystem (`~/dev`), not under `/mnt/c`. Repositories under `/mnt/c` may perform differently due to filesystem translation. The manifest includes an explicit `pathMapping.linuxFsPreferred` flag.

## Proof Level

| Level | State |
|-------|-------|
| Contract proof | **REACHED** (schema, fixtures, validator) |
| Harness proof | Not reached (no execution harness test) |
| Static test proof | **REACHED** (Test-WslBootstrapContracts.ps1) |
| Build proof | Not reached |
| Command ACK proof | Achievable by running Get-WslWorkstationState.ps1 |
| Behavior observed proof | Requires running installer against live WSL |
| Live runtime proof | Requires full Ubuntu installation with tool verification |
