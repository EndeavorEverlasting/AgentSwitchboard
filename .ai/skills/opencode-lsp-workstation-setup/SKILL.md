---
id: opencode-lsp-workstation-setup
version: 1.2.0
status: canonical
---

# OpenCode LSP Workstation Setup

## Trigger
Use this skill for a Windows request to recover, inspect, enable, verify, or hand off OpenCode LSP configuration when the flow must remain reliable for low-capability or free-model agents. Canonical discovery starts in `SKILLS.md` and `TRIGGERS.md`, then routes through `tooling/harness/operational/workflow-registry.json`.

## Inputs
- supplied AgentSwitchboard path as a hint, not assumed repository proof;
- exact expected harness branch and commit SHA when using unmerged remote work;
- `tooling/harness/operational/opencode-lsp-setup/manifest.json`;
- current OpenCode command/version;
- requested per-launch model, default `opencode/nemotron-3-ultra-free` for public/non-confidential work;
- current Git branch/HEAD and dirty state after canonical checkout resolution;
- for Verify, the immutable Configure run directory.

## Procedure
1. Prove Git identity before machine configuration. A folder name is not repository proof.
2. If the supplied path is not a Git checkout, preserve it untouched and run `Resolve-AgentSwitchboardCheckout.ps1` with the exact expected branch/head. Search only bounded nearby AgentSwitchBoard candidates and AgentSwitchboard-owned LOCALAPPDATA checkouts; otherwise create an isolated LOCALAPPDATA clone.
3. Require an exact canonical GitHub origin, exact expected remote branch/head, and a clean isolated exact-head worktree. Never reset, clean, stash, force-update, or convert the supplied non-Git folder.
4. Read the focused manifest, map, workflows, and artifact registry from that exact-head worktree.
5. Run the harness validator, then `Inspect`. Never guess the executable, version, config path, provider, or model.
6. Fail closed when OpenCode is missing, the checkout is not AgentSwitchboard, or a v2 OpenCode runtime is detected. Preserve local failure receipts/reports.
7. Configure only into a new immutable `%LOCALAPPDATA%` run directory. Never rewrite existing OpenCode global/project/custom/inline config.
8. Enable `lsp: true`. The generated launcher preserves inherited `OPENCODE_CONFIG` when present, merges inherited `OPENCODE_CONFIG_CONTENT` in memory, then forces `lsp=true` in the highest-precedence inline config without persisting inherited contents.
9. Let OpenCode activate supported built-ins only when matching files and prerequisites exist. Do not invent a PowerShell LSP; use repository PowerShell validators.
10. Keep free models per-launch only. Never persist a free trial model as a machine-wide default.
11. Use Nemotron/free endpoints only with public/non-confidential content. Stop before customer data, credentials, private machine evidence, or confidential source.
12. Require exact launcher-content verification, receipt/report, and one exact next command. Active LSP proof requires opening a supported file and observing runtime behavior.

## Outputs
- `opencode-lsp-checkout-resolution.json` and `.md` when repository recovery runs;
- `opencode-lsp-setup.json`;
- `opencode-lsp-operator-report.md`;
- immutable `opencode-lsp.overlay.json` after Configure;
- immutable PowerShell + CMD launcher pair after Configure;
- exact Git/OpenCode identity and proof ceiling.

## Deterministic validation
```powershell
Test-OpenCodeLspHarness.cmd
```

## Forbidden scope
- `AGENTS.md` or P00 governance policy mutation;
- AgentSwitchboard product/bootstrap/runtime changes;
- secrets or credentials;
- destructive Git or force ref movement;
- rewriting/deleting a supplied non-Git folder to manufacture repository proof;
- existing OpenCode config mutation or persistence of inherited inline-config contents;
- free trial models as global defaults;
- claiming `lsp: true` proves an active language server.

## Stop and escalate
Stop when Git itself is unavailable outside owned scope, the exact remote branch/head cannot be fetched without force, installation/repair belongs to another owner, OpenCode V2 is detected, provider authentication is required, privacy is not public/non-confidential for a free model, or live runtime failure requires product code changes.

## Proof ceiling
Deterministic repository recovery/configuration and bounded workstation evidence only; no provider-privacy, model-quality, active-diagnostics, deployment, or production proof.
