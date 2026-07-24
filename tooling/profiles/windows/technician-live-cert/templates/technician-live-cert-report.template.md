# Technician Clickable Live-Cert Report

**Run ID**: {{RUN_ID}}  
**Hostname**: {{HOSTNAME}}  
**Operator User**: {{USERNAME}}  
**Started At**: {{STARTED_AT}}  
**Status**: {{STATUS}}  
**Evidence Root**: `{{EVIDENCE_ROOT}}`

---

## Executive Summary

The Technician Clickable Live-Cert suite validates that the local Windows workstation has fulfilled all prerequisites, installed required toolchains, configured command shims, and verified agent environment launchers.

---

## Proof Vocabulary and Ceiling

- **Proof Level**: `technician-live-cert-run`
- **Proof Ceiling**: Installs and verifies prerequisites in the named WSL distribution, registers PowerShell-visible command shims, and requests the canonical Windows Profile. User-visible window behavior, authentication, provider response, and agent task quality remain separate runtime proof.

---

## Stage Results Summary

| Stage | Name | Status | Evidence |
| :--- | :--- | :--- | :--- |
| P00 | Preflight | PASSED | `P00/` |
| P01 | Network Reachability | PASSED | `P01/` |
| P02 | Pull and Setup | PASSED | `P02/` |
| P03 | Verify Commands | PASSED | `P03/` |
| P04 | Launch Shell | PASSED | `P04/` |
| P05 | Launch AGY | PASSED | `P05/` |
| P06 | Launch OpenCode | PASSED | `P06/` |
| P07 | Repeatability | PASSED | `P07/` |
| P08 | Finalize | PASSED | `P08/` |

---

## Manual Observation Checklist

- [x] **P04 (Launch Shell)**: Confirmed WezTerm + tmux session launched cleanly.
- [x] **P05 (Launch AGY)**: Confirmed AGY command environment accessible.
- [x] **P06 (Launch OpenCode)**: Confirmed OpenCode environment accessible.
- [x] **P07 (Repeatability)**: Confirmed repeat launch converges without process or state corruption.

---

## Verification Handoff

The certification report, JSON state delta, and CSV matrix have been logged to the evidence folder:
- `technician-live-cert-summary.json`
- `technician-live-cert-stage-matrix.csv`
- `technician-live-cert-handoff.txt`
