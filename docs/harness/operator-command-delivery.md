# Operator command-delivery harness

## Purpose

This harness protects the boundary between repository evidence and a command pasted into an operator shell. It exists because a command can be correct in source yet fail before the intended runtime when a ref/file is not independently resolved, punctuation is escaped during transport, prompt text is copied, a top-level `exit` closes the interactive shell, a discovered executable cannot actually start, or a visible terminal glyph is mistaken for proof that clipboard/input text was corrupted.

## Current state

- **Working:** tracked map, artifact registry, verification workflow, failure workflow, fixtures, opt-in pre-push hook, scoped skill, human report template, PowerShell completeness validator, Python contracts, and CI.
- **Working:** the positive fixture uses canonical PowerShell environment syntax and explicit `gh api --method GET` source reads.
- **Working:** the corruption fixture preserves malformed command transport and must be rejected deterministically.
- **Working:** `scripts/Test-OperatorChildExecutableLaunch.ps1` concretely probes the exact child executable with `UseShellExecute=false`, bounded arguments, timeout, stdout/stderr capture, and durable JSON evidence.
- **Working:** `scripts/Inspect-OperatorTerminalPasteBoundary.ps1` reads clipboard text or a supplied file/text value, records only character counts, UTF-8 hash, shell encoding metadata, and terminal hints, and never persists the raw captured text.
- **Working:** clean Unicode and literal-question-mark fixtures prove that captured-input classification is deterministic while presentation correctness remains explicitly unproved.
- **Working:** the access-denied fixture preserves the boundary where files are present but a required child executable cannot start.
- **Missing by design:** this harness does not repair Windows execution policy, change terminal fonts/configuration, install product prerequisites, open WezTerm, attach tmux, authenticate providers, or claim operator acceptance.

## Required operator-command shape

For a Windows PowerShell operator command that needs repository files from GitHub:

1. Resolve the intended source ref to an exact commit.
2. Resolve each required file at that exact commit before execution.
3. Resolve the exact path of every external executable the command must use before downstream runtime work.
4. Concretely launch each exact executable with bounded side-effect-free arguments and persist `child-executable-launch-result.json`. Discovery through `where`, `Get-Command`, file existence, download success, or version metadata without process creation is not launch proof.
5. Use explicit GET semantics for parameterized GitHub API reads.
6. Use `$env:NAME` exactly for environment variables.
7. Run exit-propagating work in a child process so the interactive parent shell stays open.
8. Capture and print the child exit code.
9. Resolve and print the child-launch artifact and downstream canonical artifact after execution.

A safe source-resolution fragment follows this form:

```powershell
$resolved = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/commits/main' --jq '.sha'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) { throw 'Unable to resolve main.' }
$content = gh api --method GET 'repos/EndeavorEverlasting/AgentSwitchboard/contents/Open-AgentSwitchboard-Tmux.ps1' -f "ref=$resolved" --jq '.content'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) { throw 'Unable to resolve launcher file.' }
```

Before a wrapper depends on PowerShell 7, for example, run `scripts/Test-OperatorChildExecutableLaunch.ps1` from a shell that is already known to work and probe the exact `pwsh.exe` with a side-effect-free version command. If process creation returns `Access is denied`, stop there. Do not retry the downstream wrapper and do not call it a tmux failure when no tmux artifact was produced.

## Terminal paste/display boundary

When the operator reports that text pasted correctly but the terminal visibly shows unexpected `?` characters or replacement glyphs, diagnose the captured input before touching terminal settings:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Inspect-OperatorTerminalPasteBoundary.ps1
```

The default mode reads `Get-Clipboard -Raw`. For deterministic fixture or captured-file analysis, use `-InputPath <path>` or `-Text <value>`. The generated `terminal-paste-boundary-result.json` contains no raw captured text. It records a SHA-256 of UTF-8 bytes, UTF-16/UTF-8 lengths, literal U+003F question-mark count, U+FFFD replacement-character count, PowerShell/console encoding metadata, and non-sensitive terminal hints.

Classifications:

- `captured-input-contains-replacement-character` — U+FFFD is already present in the captured input.
- `captured-input-contains-question-mark` — literal U+003F is present in the captured input; it may be legitimate content, so the probe does not call it corruption by itself.
- `captured-input-clean-presentation-unproven` — neither U+003F nor U+FFFD is present in the captured input. This narrows the boundary but does **not** prove the terminal rendered the text correctly.

Do not change fonts, WezTerm configuration, registry values, execution policy, or reinstall software solely from a visible-glyph symptom when captured input has not been classified.

## Known traps

- `$env:NAME` is PowerShell syntax. A backslash inserted before the colon is corruption, not escaping.
- `PS C:\...>` and `>>` are shell UI, not command content.
- A visible `?` glyph is not enough to distinguish corrupted clipboard/input from terminal presentation.
- A clean clipboard/input capture does not prove glyph rendering, PSReadLine behavior, font coverage, WezTerm configuration, or tmux presentation.
- A commit SHA resolving successfully does not prove a named file exists at that commit.
- A PR merge message does not replace an exact file read.
- Query-string interpolation in a copy-paste command is avoidable; prefer explicit GET request parameters.
- `where` and `Get-Command` prove discovery, not process creation.
- `Access is denied` before a downstream artifact exists belongs to `child-executable-launch`, not `downstream-runtime`.
- Static source verification, captured-input evidence, and child-process launch proof do not prove the downstream app is open or usable.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-OperatorCommandDeliveryHarnessCompleteness.ps1
python -m unittest tests.test_operator_command_delivery_harness tests.test_operator_terminal_paste_boundary
```

The optional tracked pre-push adapter is:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/harness/operator-command-delivery/hooks/pre-push.ps1
```

It is never installed implicitly.

## Failure recovery

When a command fails before the intended runtime gate, preserve the failed command and earliest stderr/stdout, classify the boundary, run the terminal-paste boundary probe first when the symptom is visual input corruption, re-resolve source identity and files independently, concretely probe the exact executable at the first failed child boundary, repair the harness if the failure class was unenforced, rerun focused validators, then issue the smallest repaired command. Do not skip directly to a higher runtime claim.

## Proof ceiling

Passing this harness proves command-source resolution rules, bounded launchability of explicitly probed child executables, transport-integrity contracts, captured-input classification when invoked, interactive-shell safety rules, component discoverability, and deterministic regression detection. It does not prove terminal presentation correctness or the downstream runtime until their owning live evidence gates pass.
