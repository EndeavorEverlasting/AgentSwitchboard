# Command-Delivery Skill Factoring

## Purpose

This harness prevents operator-facing command guidance from depending on overlapping prose conventions. It gives each concern one owner and makes interactive PowerShell submission boundaries executable contract checks.

The field defect that motivated this refactor was a PowerShell assignment expressed as an interactive multiline `if` followed by separately submitted `elseif` and `else` blocks. PowerShell executed the completed first statement, then treated each later continuation keyword as an orphaned command. The repository already described the rule, but no composed router or candidate validator forced agents to apply it.

## Disposition table

| Skill | Disposition | Canonical responsibility | Delegated responsibility |
|---|---|---|---|
| `powershell-interactive-execution` | **SPLIT** | PowerShell grammar, physical submission boundaries, atomic compound statements | envelope presentation → `operator-command-envelope`; repo state → `repo-intake`/`bounded-sprint` |
| `operator-command-envelope` | **REWIRE** | prompt-free, transcript-free, shell-agnostic executable presentation | PowerShell grammar → `powershell-interactive-execution` |
| `repo-intake` | **KEEP** | repository identity, current state, safe branch/worktree boundary | none |
| `gnhf-prompt-compilation` | **REWIRE** | bounded GNHF launch artifact | PowerShell interactive delivery and generic envelope |
| `stale-checkout-exact-head-bootstrap` | **REWIRE** | exact-ref fetch, deterministic bootstrap, delegated artifact readback | PowerShell interactive delivery and generic envelope |
| `windows-profile-live-certification` | **REWIRE** | workstation proof chain | command presentation and PowerShell syntax |
| `end-to-end-runtime-validation` | **REWIRE** | observed cross-boundary behavior proof | command presentation and PowerShell syntax |

The complete machine-readable contracts, inputs, outputs, preconditions, forbidden conditions, guardrails, owning files, and proof ceilings are in `tooling/skills/harness/command-delivery/skill-factoring.registry.json`.

## Deterministic routing

Routing produces exactly one primary skill. Required composed skills may be added without creating competing primary owners.

Priority:

1. explicit GNHF launch artifact;
2. stale-checkout exact-head bootstrap;
3. end-to-end runtime request;
4. workstation certification;
5. repository intake;
6. interactive PowerShell command;
7. generic operator command.

A PowerShell operator command therefore routes primarily to `powershell-interactive-execution` and requires `operator-command-envelope`. A Bash operator command routes only to `operator-command-envelope`. A GNHF PowerShell artifact remains primarily owned by `gnhf-prompt-compilation` and composes both command-delivery owners.

## Interactive PowerShell boundary

### Allowed

- guard clauses with no continuation dependency;
- one physical-line `if/elseif/else` or `try/catch/finally`;
- one outer `& { ... }` script block with every continuation attached to the preceding brace;
- normal multiline compound syntax in a saved `.ps1` file.

### Rejected

- a later snippet beginning with `elseif`, `else`, `catch`, or `finally`;
- a continuation keyword starting on a new physical line in an interactive artifact;
- a multiline interactive compound statement without one outer atomic script block;
- one compound statement divided across multiple code fences or submissions.

The exact historical failure is preserved as a synthetic negative fixture without private paths or identities.

## Operator validation

Validate repository contracts:

```powershell
& '.\Test-SkillFactoringContracts.cmd'
```

Validate a proposed Markdown handoff before sending it:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SkillFactoringContracts.ps1 -CandidatePath '.\handoff.md' -CandidateDeliveryMode interactive-copy-paste
```

Generated JSON and Markdown reports are local-only under `%LOCALAPPDATA%\AgentSwitchboard\skill-factoring` by default.

## Proof ceiling

A passing result proves tracked ownership, unique primary triggers, positive and negative fixture classification, and syntax-unit safety for validated candidate artifacts. It does not prove the command succeeds on an operator workstation or produces the intended runtime behavior.
