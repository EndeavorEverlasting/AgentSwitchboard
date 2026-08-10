---
id: opencode-lsp-workstation-setup
version: 1.0.0
status: canonical
---

# OpenCode LSP Workstation Setup

## Trigger
Use this skill for a Windows request to inspect, enable, verify, or hand off OpenCode LSP configuration when the flow must remain reliable for low-capability or free-model agents.

## Inputs
- exact AgentSwitchboard repository root;
- `tooling/harness/operational/opencode-lsp-setup/manifest.json`;
- current OpenCode command/version;
- requested per-launch model, default `opencode/nemotron-3-ultra-free` for this public-repository use case;
- current Git branch/HEAD and dirty state.

## Procedure
1. Resolve Git identity before machine configuration.
2. Read the focused manifest, map, workflows, and artifact registry.
3. Run `Inspect` first. Never guess the executable, version, config path, provider, or model.
4. Fail closed when OpenCode is missing, the checkout is not AgentSwitchboard, or a v2 OpenCode runtime is detected.
5. Configure only through the AgentSwitchboard-owned `%LOCALAPPDATA%` overlay. Never rewrite existing OpenCode global/project config.
6. Enable `lsp: true`; let OpenCode activate supported built-ins only when matching files and prerequisites exist.
7. Do not invent a PowerShell LSP. Use repository PowerShell validators for PowerShell files.
8. Keep free models per-launch only. Never persist a free trial model as a machine-wide default.
9. Use Nemotron/free endpoints only with public/non-confidential content. Stop before customer data, credentials, private machine evidence, or confidential source.
10. Require receipt/report and one exact next command. Active LSP proof requires opening a supported file and observing runtime behavior.

## Outputs
- `opencode-lsp-setup.json`;
- `opencode-lsp-operator-report.md`;
- `opencode-lsp.overlay.json` after Configure;
- generated OpenCode launch CMD after Configure;
- exact Git/OpenCode identity and proof ceiling.

## Deterministic validation
```powershell
Test-OpenCodeLspHarness.cmd
```

## Forbidden scope
- governance contract or policy changes;
- AgentSwitchboard product/bootstrap/runtime changes;
- secrets or credentials;
- destructive Git;
- existing OpenCode config mutation;
- free trial models as global defaults;
- claiming `lsp: true` proves an active language server.

## Stop and escalate
Stop when installation/repair belongs to another owner, OpenCode V2 is detected, provider authentication is required, privacy is not public, or live runtime failure requires product code changes.

## Proof ceiling
Deterministic configuration and bounded workstation evidence only; no provider-privacy, model-quality, active-diagnostics, deployment, or production proof.
