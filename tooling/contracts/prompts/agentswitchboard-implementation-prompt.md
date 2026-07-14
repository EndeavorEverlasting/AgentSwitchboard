# Implementation Prompt: AgentSwitchboard Ada mechanical profile executor

## Context
Repo: `EndeavorEverlasting/AgentSwitchboard`
Branch: `feat/worker-interoperability-contract` or sibling feature branch
Lane: feature/harness
Target config: `tooling/contracts/ada-mechanical-profile.json`

## Objective
Implement a deterministic execution worker wrapper in AgentSwitchboard that parses and enforces the `ada-mechanical-profile.json` constraints during worker invocation.

## Requirements
1. **Profile Parsing**: Parse `ada-mechanical-profile.json` and validate all required budget and policy fields.
2. **Mandatory Dry Run**: Prior to running any repository mutation, execute a preflight dry run check of all commands and files.
3. **Budget Enforcement**:
   - Limit operations count to 15.
   - Limit changed files to 4.
   - Limit execution time to 300 seconds.
   - Enforce a strict token cap of 500,000.
4. **Safety Policies**:
   - Zero autonomous repair attempts: do not attempt to fix errors, format code, or re-run commands.
   - Stop on first deviation: exit immediately on any command failure or budget breach.
5. **Independent Validation**:
   - Run validation using `pwsh -NoLogo -NoProfile -File tooling/contracts/Test-WorkerRunContracts.ps1`.
   - Verify the exit code is exactly `0`.

## Expected Output
An executor script/class `tooling/gnhf/Start-AdaMechanicalWorker.ps1` wrapping worker execution under these constraints and generating a compliant `worker-run` result packet.
