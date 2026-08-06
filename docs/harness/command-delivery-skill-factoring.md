# Command-Delivery Skill Factoring

## Purpose

This harness prevents operator-facing command guidance from depending on overlapping prose conventions. It assigns each concern one owner and makes interactive PowerShell submission boundaries executable contract checks.

The field defect that motivated this refactor was a PowerShell assignment submitted as an `if` block, then a separate `elseif`, then a separate `else`. PowerShell executed the completed first statement and treated the later continuation keywords as orphan commands. The repository described the rule, but no composed router or candidate validator forced agents to apply it.

## Ownership

| Skill | Disposition | Canonical responsibility |
|---|---|---|
| `powershell-interactive-execution` | **SPLIT** | PowerShell grammar, structural completeness, and physical submission boundaries |
| `operator-command-envelope` | **REWIRE** | Prompt-free, transcript-free, shell-agnostic executable presentation |
| `repo-intake` | **KEEP** | Repository identity and safe branch/worktree boundary |
| `gnhf-prompt-compilation` | **REWIRE** | Bounded GNHF launch artifact |
| `stale-checkout-exact-head-bootstrap` | **REWIRE** | Exact-ref bootstrap and delegated artifact readback |
| `windows-profile-live-certification` | **REWIRE** | Workstation proof chain |
| `end-to-end-runtime-validation` | **REWIRE** | Observed cross-boundary behavior proof |

The machine-readable contracts live in `tooling/skills/harness/command-delivery/skill-factoring.registry.json` and are validated against the complete declared JSON schema. The registry cannot add unknown top-level properties, omit artifact policy, duplicate skill ownership, or declare a primary trigger absent from `TRIGGERS.md`.

## Deterministic routing

Routing produces exactly one primary skill. Required composed skills may be added without becoming competing primary owners.

A PowerShell operator command routes primarily to `powershell-interactive-execution` and requires `operator-command-envelope`. A Bash operator command routes to `operator-command-envelope`. A GNHF PowerShell artifact remains primarily owned by `gnhf-prompt-compilation` and composes both command-delivery owners.

## Interactive PowerShell boundary

### Allowed

- guard clauses with no continuation dependency;
- one physical-line `if/elseif/else` or `try/catch/finally`;
- one outer `& { ... }` script block with every continuation attached to the preceding brace;
- structurally complete multiline compound syntax in a saved `.ps1` file.

### Rejected

- a later snippet beginning with `elseif`, `else`, `catch`, or `finally`;
- a continuation keyword starting on a new physical line in an interactive artifact;
- a multiline interactive compound statement without one outer atomic script block;
- an unclosed brace, parenthesis, bracket, quote, here-string, block comment, or trailing backtick;
- one compound statement divided across multiple code fences or submissions;
- an unterminated Markdown fence.

Relative candidate paths are resolved against the supplied repository root, not the caller's current directory.

## Entrypoints

The Windows front door prefers PowerShell 7 and falls back to Windows PowerShell 5.1:

```cmd
Test-SkillFactoringContracts.cmd
```

Validate a proposed Markdown handoff before sending it:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1 -CandidatePath '.\handoff.md' -CandidateDeliveryMode interactive-copy-paste
```

Generated JSON and Markdown reports are local-only under `%LOCALAPPDATA%\AgentSwitchboard\skill-factoring` by default. Candidate command contents are not copied into the report.

## Validation

```powershell
python -m unittest tests.test_skill_factoring_contracts
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\Test-SkillFactoringContracts.ps1
git --no-pager diff --check
```

## Proof ceiling

A passing result proves tracked ownership, complete registry-schema conformance, canonical trigger registration, unique primary routing, positive and negative fixture classification, and structural syntax-unit safety for validated candidate artifacts. It does not prove the command succeeds on an operator workstation or produces the intended runtime behavior.
