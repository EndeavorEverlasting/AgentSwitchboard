# Technician Clickable Live-Cert Operator Guide

This guide provides a clickable surface for operators performing live certification of a Windows technician workstation.

---

## 🚀 Bootstrap & Full Run Entrypoints

- [AgentSwitchboard-Technician-Bootstrap.cmd](../../AgentSwitchboard-Technician-Bootstrap.cmd) — First entrypoint to pull/clone repo and bootstrap setup.
- [Run-Technician-LiveCert.cmd](../../Run-Technician-LiveCert.cmd) — Full-run orchestrator running P00 through P08.

---

## 📋 Clickable Core Stages (P00 – P08) & Optional Stage (P09)

1. [Technician-LiveCert-P00-Preflight.cmd](../../Technician-LiveCert-P00-Preflight.cmd) — Stage P00: Preflight environment check.
2. [Technician-LiveCert-P01-Network.cmd](../../Technician-LiveCert-P01-Network.cmd) — Stage P01: Network reachability check.
3. [Technician-LiveCert-P02-Pull-And-Setup.cmd](../../Technician-LiveCert-P02-Pull-And-Setup.cmd) — Stage P02: Pull and setup workstation dependencies.
4. [Technician-LiveCert-P03-Verify-Commands.cmd](../../Technician-LiveCert-P03-Verify-Commands.cmd) — Stage P03: Verify CLI commands and shims.
5. [Technician-LiveCert-P04-Launch-Shell.cmd](../../Technician-LiveCert-P04-Launch-Shell.cmd) — Stage P04: Launch WezTerm + tmux terminal shell.
6. [Technician-LiveCert-P05-Launch-AGY.cmd](../../Technician-LiveCert-P05-Launch-AGY.cmd) — Stage P05: Launch AGY (Antigravity) environment.
7. [Technician-LiveCert-P06-Launch-OpenCode.cmd](../../Technician-LiveCert-P06-Launch-OpenCode.cmd) — Stage P06: Launch OpenCode environment.
8. [Technician-LiveCert-P07-Repeatability.cmd](../../Technician-LiveCert-P07-Repeatability.cmd) — Stage P07: Verify repeatability without state duplication.
9. [Technician-LiveCert-P08-Finalize.cmd](../../Technician-LiveCert-P08-Finalize.cmd) — Stage P08: Finalize evidence and compile Markdown report.
10. [Technician-LiveCert-P09-Hermes-Optional.cmd](../../Technician-LiveCert-P09-Hermes-Optional.cmd) — Stage P09: Optional Hermes agent launcher.

---

## 🛠️ Clickable Repair Launchers

- [Repair-Technician-WSL-Ubuntu.cmd](../../Repair-Technician-WSL-Ubuntu.cmd) — Repair WSL Ubuntu installation.
- [Repair-Technician-WezTerm.cmd](../../Repair-Technician-WezTerm.cmd) — Repair WezTerm via WinGet.
- [Repair-Technician-AGY.cmd](../../Repair-Technician-AGY.cmd) — Re-run AGY installer script.
- [Repair-Technician-OpenCode.cmd](../../Repair-Technician-OpenCode.cmd) — Re-run OpenCode installer script.
- [Repair-Technician-Command-Shims.cmd](../../Repair-Technician-Command-Shims.cmd) — Recreate executable shims in `%LOCALAPPDATA%\AgentSwitchboard\bin`.

---

## 📁 Evidence & Shortcut Utility Launchers

- [Open-TechnicianLiveCertEvidence.cmd](../../Open-TechnicianLiveCertEvidence.cmd) — Opens latest run evidence folder in Windows Explorer.
- [Install-TechnicianLiveCertShortcuts.cmd](../../Install-TechnicianLiveCertShortcuts.cmd) — Creates desktop shortcuts pointing to root CMDs.

---

## 📄 Manifest & Internal Implementation Code

- [technician-live-cert.manifest.json](../../tooling/profiles/windows/technician-live-cert/technician-live-cert.manifest.json) — Manifest definition.
- [TechnicianLiveCert.Common.psm1](../../tooling/profiles/windows/technician-live-cert/TechnicianLiveCert.Common.psm1) — Shared PowerShell module.
- [Invoke-TechnicianLiveCertStage.ps1](../../tooling/profiles/windows/technician-live-cert/Invoke-TechnicianLiveCertStage.ps1) — Stage dispatcher.
- [Invoke-TechnicianLiveCert.ps1](../../tooling/profiles/windows/technician-live-cert/Invoke-TechnicianLiveCert.ps1) — Full-run orchestrator.
- [Invoke-TechnicianRepair.ps1](../../tooling/profiles/windows/technician-live-cert/Invoke-TechnicianRepair.ps1) — Repair dispatcher.
