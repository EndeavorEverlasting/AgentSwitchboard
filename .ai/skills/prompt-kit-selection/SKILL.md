---
id: prompt-kit-selection
version: 1.0.0
status: canonical
---

# AI Harness Prompt Kit Selection and Rendering

## Trigger

Use when the owner asks to browse, search, select, show, generate, or render a prompt from the AI Harness Prompt Kit, or when a deterministic repository workflow needs a V38 prompt ID and variable-complete prompt artifact.

Do not use this skill merely because the word “prompt” appears. Ordinary writing and repository execution remain governed by their direct task contracts.

## Inputs

- prompt-kit version, currently `v38`;
- optional exact prompt ID `P00` through `P44`;
- search text describing the operating moment;
- expected execution surface: `regular_ai_prompt` or `gnhf_launch_artifact`;
- variable values in `xyz_name=value` form;
- whether unresolved variables are intentionally allowed;
- optional output path outside the canonical snapshot directory.

## Procedure

1. Read `.ai/prompt-kits/v38/source.json` and verify the snapshot SHA-256.
2. Use `Select-AgentSwitchboardPrompt.cmd` or `tooling/prompts/Select-AgentSwitchboardPrompt.ps1`; do not scrape the workbook.
3. List or search the registry before selecting when the prompt ID is unknown.
4. Confirm the prompt’s `useThisWhen`, `doNotUseWhen`, `promptClass`, mutation authority, proof ceiling, and required variables.
5. Require the correct execution surface. A GNHF prompt request must resolve to `gnhf_launch_artifact`; a regular chat prompt must resolve to `regular_ai_prompt`.
6. Render only exact placeholder substitutions. Do not paraphrase, merge, or silently rewrite the canonical prompt text.
   Selection does not authorize execution; a selected GNHF launch artifact remains inert until a separate reviewed runtime action invokes it.
7. Reject missing required variables unless the operator explicitly requests an unresolved template.
8. Return or write the rendered prompt together with its prompt ID, source hash, rendered hash, execution surface, and unresolved-variable list.

## Outputs

- selected prompt ID and metadata;
- exact canonical or rendered prompt text;
- execution-surface classification;
- applied and unresolved variable lists;
- source and rendered text SHA-256 values;
- an exact blocker when the registry, hash, prompt ID, variable contract, or execution surface is invalid.

## Deterministic validation

A valid selection or render must:

- load the vendored offline V38 snapshot;
- verify the snapshot and prompt text hashes;
- resolve exactly one prompt ID;
- preserve the registry’s regular-AI versus GNHF boundary;
- reject undefined variables and duplicate assignments;
- require all prompt variables unless unresolved output was explicitly authorized;
- never modify files beneath `.ai/prompt-kits/v38/`;
- make no network, provider, model, Drive, GitHub, or target-runtime call;
- report provenance from `EndeavorEverlasting/web-excel-repair-triage`.

## Forbidden scope

- No workbook scraping during normal AgentSwitchboard operation.
- No network dependency for selection or rendering.
- No silent prompt rewriting, prompt-ID renumbering, or proof-ceiling changes.
- No regular AI prompt substituted for a GNHF launch artifact.
- No GNHF launch artifact executed merely because it was selected or rendered.
- No secrets embedded as variable values or retained in repository files.
- No output written into the canonical snapshot directory.

## Stop and escalate

Stop when the snapshot hash, prompt hash, source provenance, execution surface, required variables, or prompt ID cannot be verified. Name the failing file or field and the exact validator command. Do not fall back to remembered prompt text or fetch a newer kit silently.
