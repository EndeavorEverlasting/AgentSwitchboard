# Auggie readiness boundary

Auggie / Augment Code CLI is treated as a separate application and agent surface. AgentSwitchboard does not infer its health from WezTerm, PowerShell, tmux, OpenCode, AGY, or another CLI.

## Why this boundary exists

The terminal-paste incident established that a healthy terminal stack does not prove a particular agent CLI is correctly discovered or invoked. Before AgentSwitchboard adds Auggie to unattended GNHF execution, it needs a bounded fact: does the installed command start, and does its own help surface advertise the current ACP server capability?

The upstream Augment CLI reference documents `--acp` as the ACP server mode and `--print` as noninteractive execution. AgentSwitchboard therefore probes only `auggie --version` and `auggie --help`; it does **not** start `auggie --acp` during readiness classification.

## Run the read-only probe

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Test-AuggieReadiness.ps1
```

The probe writes an untracked local artifact beneath:

```text
%LOCALAPPDATA%\AgentSwitchboard\auggie-readiness\runs\<runId>\auggie-readiness-result.json
```

Use `-FailIfNotReady` when the caller should receive a nonzero result for anything other than `ready`.

## Classifications

- `ready` — command discovery, bounded `--version`, bounded `--help`, and `--acp` advertisement all passed.
- `command-not-found` — no Auggie command was resolved.
- `version-probe-failed` — the command resolved but its bounded version probe failed, timed out, or could not start.
- `help-probe-failed` — version succeeded but the bounded help probe failed, timed out, or could not start.
- `acp-not-advertised` — version/help both succeeded but current help output did not advertise `--acp`.

The artifact may record `acp:auggie --acp` as the **candidate** ACP agent specification when `--acp` is advertised. That is capability discovery, not runtime certification.

## Deliberately not done here

This harness does not install Auggie, run `auggie login`, inspect tokens, authenticate a provider, start the ACP server, prove an ACP handshake, select a model, mutate a repository, or add Auggie to automatic GNHF routing. Those operations require their own authorization and live evidence.

A `ready` result proves only CLI readiness and advertised capabilities. It does not prove authentication, ACP handshake, model/provider readiness, terminal rendering, repository mutation, or unattended GNHF execution.
