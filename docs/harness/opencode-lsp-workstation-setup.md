# OpenCode LSP workstation setup harness

This harness gives a Windows operator or low-capability agent one path:

`inspect -> configure owned overlay -> verify -> launch -> observe -> handoff`

It does not edit governance, product launchers, existing OpenCode global/project config, or credentials.

## Owned configuration

OpenCode merges config sources. The harness uses `OPENCODE_CONFIG` and writes only:

`%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\opencode-lsp.overlay.json`

with:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": true
}
```

The generated launcher sets that overlay only for its OpenCode process and selects the requested model with `-m`; it does not make a free model the global default.

## Server policy

Current stable OpenCode documentation says LSP is disabled by default and built-in servers start when a matching file is opened and requirements are met. For AgentSwitchboard, Pyright/Python and yaml-ls/YAML are useful low-friction paths. TypeScript is left conditional on a target project satisfying its requirements. The current built-in list has no PowerShell LSP, so PowerShell correctness remains owned by repository validators.

Current OpenCode V2 documentation says LSP config is accepted but has no runtime effect. The runner fails closed on a detected v2 command/version instead of reporting false success.

## Free-model boundary

The default launch model for this public AgentSwitchboard use case is `opencode/nemotron-3-ultra-free`. Free trial endpoints must not receive confidential, customer, credential, private-machine, or private-source data. Select an approved model/provider for non-public work.

## Operator flow

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Inspect -RepoPath .
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath .
```

Configure writes only the AgentSwitchboard-owned LOCALAPPDATA state plus run evidence. It prints the generated launcher.

## Runtime proof

After Configure, run the generated CMD, open a `.py` or `.yml` file, and observe OpenCode server/diagnostic behavior. Configuration proof is not LSP runtime proof.

## Troubleshooting

- `OPENCODE_NOT_FOUND`: repair/install OpenCode through its owning workflow; do not hardcode an npm profile path.
- `OPENCODE_V2_LSP_UNAVAILABLE`: use repository lint/typecheck/test/PowerShell validators until upstream V2 supplies runtime support.
- `MODEL_NOT_VISIBLE`: connect/refresh OpenCode Zen and rerun; never put credentials in repo/evidence.
- no PowerShell diagnostics: expected; current OpenCode built-ins do not include a PowerShell server.
- Pyright does not start: open a Python file and confirm requirements can be resolved; do not install arbitrary packages merely to satisfy the harness.

## Validation

`Test-OpenCodeLspHarness.cmd`
