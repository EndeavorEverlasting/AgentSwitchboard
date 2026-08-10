# OpenCode LSP workstation setup harness

This harness gives a Windows operator or low-capability agent one path:

`inspect -> configure immutable local artifacts -> verify -> launch -> observe -> handoff`

It does not edit governance, AgentSwitchboard product launchers, existing OpenCode global/project/custom config, or credentials.

## Canonical routing

A fresh agent reaches this lane through `SKILLS.md`, `TRIGGERS.md`, and `tooling/harness/operational/workflow-registry.json`, then reads the focused manifest and workflows. The procedure is intentionally small: inspect identity first, configure only after the gates pass, preserve failure evidence, and never infer runtime success from configuration alone.

## Effective configuration

OpenCode merges multiple config sources. The Configure run writes an immutable fallback overlay under:

`%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\runs\<run-id>\opencode-lsp.overlay.json`

containing:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": true
}
```

The generated PowerShell launcher preserves an inherited `OPENCODE_CONFIG` path when one already exists. It also parses inherited `OPENCODE_CONFIG_CONTENT` in memory, preserves its keys, forces `lsp=true`, and passes that merged JSON only to the child OpenCode process. Inherited inline configuration is never copied to receipts or reports.

Configure never overwrites a prior run directory. Every receipt therefore points to the exact immutable overlay and launcher pair that it validated.

## Interactive model selection

The launcher starts the OpenCode TUI with the current top-level `--model` option and the repository path. The default requested model is `opencode/nemotron-3-ultra-free`; it is selected per launch and is not persisted as the global model.

Free trial endpoints are for public/non-confidential material only. Do not submit credentials, customer data, private machine evidence, or confidential source.

## Server policy

Current stable OpenCode documentation says LSP is disabled by default and built-in servers start when a matching file is opened and requirements are met. For AgentSwitchboard, Pyright/Python and yaml-ls/YAML are useful low-friction paths. TypeScript remains conditional on a target project satisfying its requirements. The current built-in list has no PowerShell LSP, so PowerShell correctness remains owned by repository validators.

Current OpenCode V2 documentation says LSP config is accepted but has no runtime effect. The runner fails closed on a detected V2 version instead of reporting false success.

## Operator flow

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Inspect -RepoPath .
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath .
```

Inspect and every expected failure write a local receipt/report. Configure additionally writes the immutable overlay and PowerShell/CMD launcher pair and validates their exact contents before returning `configured`.

To re-verify an existing Configure run without rewriting it:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Verify -RepoPath . -ConfigurationDirectory '<configure-run-directory>'
```

## Runtime proof

After Configure, run the generated CMD, open a `.py` or `.yml` file, and observe OpenCode server/diagnostic behavior. Configuration proof is not LSP runtime proof.

## Troubleshooting

- `OPENCODE_NOT_FOUND`: repair/install OpenCode through its owning workflow; the failure receipt remains local.
- `OPENCODE_V2_LSP_UNAVAILABLE`: use repository lint/typecheck/test/PowerShell validators until upstream V2 supplies runtime support.
- `MODEL_NOT_VISIBLE`: connect/refresh the provider and rerun Inspect; never put credentials in repo/evidence.
- `LAUNCHER_MISMATCH`: do not hand-edit a generated run; create a new Configure run.
- `CONFIGURATION_DIRECTORY_ALREADY_OWNED`: use the default new run instead of overwriting old evidence.
- inherited inline config is invalid JSON: the generated launcher stops without changing the environment source.
- no PowerShell diagnostics: expected; current OpenCode built-ins do not include a PowerShell server.
- Pyright does not start: open a Python file and confirm its requirement can be resolved; do not install arbitrary packages merely to satisfy the harness.

## Validation

`Test-OpenCodeLspHarness.cmd` resolves Python 3 using `python.exe` or the Windows `py.exe -3` launcher, runs the focused contract/completeness floor, runs the canonical documentation contract, and checks diff hygiene.
