# App Output Context Engine

`Contextualize-AppOutput.cmd` converts output already captured from an application, validator, agent, or tool into a compact instruction packet for another agent.

## Boundary

The engine is an offline harness component. It does not launch or attach to applications, call providers, execute selected prompts, mutate repositories, or prove runtime success. It hashes the original input, parses text/JSON/JSONL, redacts common secrets and private identifiers, extracts signals, ranks prompt-kit entries within one exact execution surface, and writes minimized local evidence.

## Inputs

- `--input`: UTF-8 text, JSON, or JSONL;
- `--prompt-registry`: `ai-harness-prompt-registry/v1` JSON or `.gz.b64`;
- `--source-app`: public application or adapter label;
- `--execution-surface`: `regular_ai_prompt` or `gnhf_launch_artifact`;
- `--output-root`: directory outside the repository.

## Example

```powershell
Set-Location -LiteralPath $env:USERPROFILE\Documents\GitHub\AgentSwitchboard

$OutputRoot = Join-Path $env:TEMP 'AgentSwitchboard\app-output-context'
.\Contextualize-AppOutput.cmd `
  --input .\sample-output.log `
  --prompt-registry .\.ai\prompt-kits\v38\prompt-registry.v1.json.gz.b64 `
  --source-app opencode `
  --execution-surface regular_ai_prompt `
  --output-root $OutputRoot
```

The prompt-kit snapshot path above is available only after the prompt-registry consumer branch is integrated. The engine itself is validated against a small public fixture and does not duplicate the full prompt kit.

## Outputs

- `app-output-context.json` — schema-backed compact packet;
- `app-output-context.md` — English summary.

Raw output is not copied into either artifact. The packet records the source hash, redacted excerpts, signal classification, candidate prompt IDs, required variables, and proof ceiling.

## Validation

```powershell
python .\tests\test_app_output_context_engine.py
pwsh -NoLogo -NoProfile -File .\scripts\Test-AppOutputContextEngine.ps1
.\Test-AppHarness.cmd
```

Contract proof does not establish prompt quality, live application behavior, hosted-model availability, repository delivery, or operator acceptance.
