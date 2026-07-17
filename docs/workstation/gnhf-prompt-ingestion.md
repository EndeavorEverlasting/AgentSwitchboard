# GNHF Prompt Ingestion and Cursor Orchestration

AgentSwitchboard can convert a filled copy-ready GNHF command or a sectioned bounded sprint prompt into the existing versioned request and compiled-prompt contracts. Conversion is deterministic and does not start an agent, provider, GNHF process, push, merge, deployment, or target-repository mutation.

## Supported source forms

1. A canonical PowerShell command beginning with `gnhf` and containing `--agent`, exactly one Git mode, iteration and token caps, `--prevent-sleep on`, `--stop-when`, and one quoted objective block.
2. A sectioned bounded prompt with concrete `Owned scope`, `Forbidden scope`, `Objective` or `Sprint`, `Expected artifacts`, and `Validation` sections.
3. One `regular-sprint-request` v1 JSON document that still needs deterministic compilation.

Templates with unresolved `xyz_*`, `__PLACEHOLDER__`, or `<PLACEHOLDER>` values fail closed. At least one exact repository-relative artifact file must be present or supplied through `-ExpectedArtifactPath`; AgentSwitchboard does not invent a tracked deliverable.

## Compile without running

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Convert-GnhfPromptToContracts.ps1 `
  -PromptPath C:\Prompts\bounded-sprint.txt `
  -TargetRepo C:\Repos\Target `
  -Agent opencode `
  -MaxIterations 4 `
  -MaxTokens 250000
```

The command writes an untracked local packet containing:

- `regular-request.json`
- `compiled-gnhf-prompt.json`
- `ingestion-result.json`

The default root is `%LOCALAPPDATA%\AgentSwitchboard\GnhfCursor\compiled-inputs`.

## Populate and orchestrate through Cursor

Plan and visibly print the generated prompt:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Invoke-CursorGnhfSprint.ps1 `
  -PromptPath C:\Prompts\bounded-sprint.txt `
  -TargetRepo C:\Repos\Target `
  -Agent opencode `
  -MaxIterations 4 `
  -MaxTokens 250000 `
  -PlanOnly
```

Run only after the generated contracts, clean-target gate, workstation Plan, exact artifact paths, and selected route are acceptable:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\gnhf\Invoke-CursorGnhfSprint.ps1 `
  -PromptPath C:\Prompts\bounded-sprint.txt `
  -TargetRepo C:\Repos\Target `
  -Agent opencode `
  -MaxIterations 4 `
  -MaxTokens 250000 `
  -Run
```

The existing `-RequestPath` plus `-CompiledPromptPath` form remains supported. The two input modes are mutually exclusive.

## Proof boundary

Prompt ingestion proves source classification, deterministic field population, contract validation, atomic local artifact creation, and no target-repository mutation. It does not prove provider health, model quality, GNHF spawn, commit creation, product correctness, push, merge, deployment, or workstation acceptance. Those claims remain owned by the downstream runtime evidence chain.
