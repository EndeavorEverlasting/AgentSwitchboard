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

Configure never overwrites a prior non-empty output directory. If a caller points Configure at prior evidence, that directory remains untouched and the failure receipt/report are written to a fresh run instead. Every successful receipt therefore points to the exact immutable overlay and launcher pair that it validated.

## Interactive model selection

The launcher starts the OpenCode TUI with the current top-level `--model` option and the repository path. The default requested model is `opencode/nemotron-3-ultra-free`; it is selected per launch and is not persisted as the global model. Model visibility is checked against the provider prefix parsed from `provider/model`, so the bounded query matches the requested model namespace.

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

## Missing or unhealthy runtime recovery

`OPENCODE_NOT_FOUND` is owned by `Recover-OpenCodeRuntime.ps1`. The recovery is deliberately narrower than technician workstation setup:

- require Windows `LOCALAPPDATA` so runtime recovery and Inspect share exactly one AgentSwitchboard state/shim root; do not invent a temporary canonical-shim location that Inspect cannot consume;
- probe only the requested WSL distribution for the OpenCode command;
- put `$HOME/.opencode/bin` first in the recovery PATH so a repaired managed runtime takes precedence over an older broken user command;
- validate a discovered command by its exact safe path rather than by a second name lookup;
- treat a command that exits nonzero, returns no version, or times out as an unhealthy runtime rather than as success;
- when OpenCode is absent or unhealthy, require existing `curl` and GNU `timeout`, export `OPENCODE_INSTALL_DIR=$HOME/.opencode/bin`, then run the official OpenCode installer once even when an older/broken command is already discoverable;
- bound the network-backed install in Linux and again from the Windows parent process;
- independently rediscover the command after install and validate that exact safe path with `--version` before writing `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd`;
- after the recovery run directory is initialized, write `%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\runs\<run-id>\opencode-runtime-recovery.json` and `.md` for every terminal runtime stage, including failures before Inspect;
- persist stage, exit code, timeout state, and whether stdout/stderr existed, but not raw command output, environment dumps, credentials, or inherited OpenCode configuration;
- automatically re-enter Inspect through a bounded parent process after runtime recovery;
- do not install or repair unrelated agents such as AGY, Hermes, tmux, or WezTerm.

The default install timeout is 180 seconds. A timeout, missing prerequisite, failed official installer, or still-unhealthy post-install version probe is a named blocker, not a reason to fall back to broad technician setup.

## Runtime proof

After Configure, run the generated CMD, open a `.py` or `.yml` file, and observe OpenCode server/diagnostic behavior. Configuration proof is not LSP runtime proof.

## Troubleshooting

- `WRONG_REPOSITORY`: the origin must be an exact supported GitHub URL/SCP form for `EndeavorEverlasting/AgentSwitchboard`; similarly named owners are rejected.
- `OPENCODE_NOT_FOUND`: run the registered runtime recovery router. It repairs OpenCode only and must not delegate to broad command-shim/technician setup.
- missing `LOCALAPPDATA`: stop before recovery; the router will not create a shim under a different state root than Inspect uses.
- existing `opencode` command but version exit nonzero/empty: the runtime router treats it as `existing-runtime-version-failed`, performs one bounded official reinstall into `$HOME/.opencode/bin`, gives that path precedence, and then independently verifies the exact rediscovered path.
- `OPENCODE_INSTALL_FAILED`: inspect the runtime-recovery stage/exit evidence and console installer detail; do not route through unrelated tool installers.
- `OPENCODE_POST_INSTALL_VERSION_FAILED`: the official installer completed but the exact recovered runtime is still unhealthy; preserve the runtime-recovery receipt/report as the external-runtime blocker.
- OpenCode recovery timeout: preserve the recovery receipt/report and treat network/upstream runtime access as the blocker; do not retry through unrelated tool installers.
- OpenCode recovery missing `curl` or GNU `timeout`: repair that prerequisite explicitly or use an already healthy OpenCode runtime; the focused router will not install unrelated technician tooling as a side effect.
- `OPENCODE_V2_LSP_UNAVAILABLE`: use repository lint/typecheck/test/PowerShell validators until upstream V2 supplies runtime support.
- `MODEL_ID_INVALID`: use `provider/model` format.
- `MODEL_NOT_VISIBLE`: connect/refresh the requested provider and rerun Inspect; never put credentials in repo/evidence.
- `LAUNCHER_MISMATCH`: do not hand-edit a generated run; create a new Configure run.
- `CONFIGURATION_DIRECTORY_ALREADY_OWNED`: use the default new run or an empty directory instead of overwriting old evidence.
- inherited inline config is invalid JSON: the generated launcher stops without changing the environment source.
- no PowerShell diagnostics: expected; current OpenCode built-ins do not include a PowerShell server.
- Pyright does not start: open a Python file and confirm its requirement can be resolved; do not install arbitrary packages merely to satisfy the harness.

## Validation

`Test-OpenCodeLspHarness.cmd` first proves a usable Python 3 runtime. It tries `python.exe`, then falls back to `py.exe -3` if the first executable is missing or unusable. It then runs the focused contract/completeness floor, the bounded runtime-recovery contract, the canonical documentation contract, and diff hygiene.
