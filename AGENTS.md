# Agent Instructions for AgentSwitchboard

## Repository

This repository publishes the AgentSwitchboard invocation and result contract used by SysAdminSuite for workstation-agent operations.

## Contract structure

- `schemas/agentswitchboard-invocation/v2.json` — execution-domain request schema
- `schemas/agentswitchboard-result/v2.json` — native/bridge result schema
- `agentswitchboard/` — Python module with CLI entrypoint, request validation, fixture execution, and result builder
- `fixtures/` — sampled request and expected result files
- `tests/` — contract tests

## Supported agents

- opencode
- agy
- goose

## Supported execution domains

- windows-native
- windows-wsl
- linux-native

macOS is explicitly unsupported.

## Operations

- inventory (detect and report state)
- install-missing (detect and install missing agents only)
- repair-check (assess repair need)
- smoke (per-agent smoke tests)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Action required |
| 2 | Invalid request |
| 3 | Unsupported profile |
| 4 | Internal failure |

## Safety

- Never authenticates accounts automatically
- Never contacts hosted models or providers during fixture mode
- Never emits token values, secrets, or machine-local paths
- Preserves existing configuration

## Proof ceiling

Fixture mode returns synthetic data with observation fields set to `false`. Real agent installation, authentication, hosted-model responses, and SysAdminSuite integration are not proven by this contract.

Canonical wrappers prefer a healthy native command. Explicit `<agent>_native`
and `<agent>_win` wrappers remain available for diagnosis; bridge use requires
the invoking contract to allow it. Alias-only discovery is never the automation
contract.

## Entrypoints

```console
python -m agentswitchboard request.json [--pretty]
python -m agentswitchboard --validate < request.json
python -m agentswitchboard --supported-profiles
python -m agentswitchboard --supported-operations
python -m agentswitchboard --supported-agents
python -m agentswitchboard --version
```
