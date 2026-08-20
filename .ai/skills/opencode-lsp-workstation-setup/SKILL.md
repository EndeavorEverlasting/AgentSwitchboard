---
id: opencode-lsp-workstation-setup
version: 2.0.0
status: canonical
---

# OpenCode LSP Workstation Setup

## Trigger
Use for Windows OpenCode LSP inspection/configuration, checkout recovery for that setup, or per-launch free-model routing. Start at the 30k `opencode-lsp` domain in `tooling/harness/context/context.routes.json`; do not preload implementation or operator docs.

## Inputs
- selected workflow spec from `tooling/harness/operational/opencode-lsp-setup/workflows/`;
- exact checkout or path hint;
- requested `provider/model`;
- latest receipt when recovering or verifying.

## Procedure
1. Run the selected workflow's identity/prerequisite gate before mutation.
2. Treat a supplied path as a hint until canonical Git origin and exact head are proven; preserve non-Git/dirty operator state.
3. Never rewrite existing OpenCode global/project/custom/inline config. Configure only into a new immutable AgentSwitchboard-owned run.
4. Keep free models launch-only and use them only for public/non-confidential work.
5. On failure, preserve the receipt and repair the first owned deterministic boundary; do not weaken gates.
6. Hand off exact repo/head, receipt/artifacts, proof ceiling, owner/dependency, and one executable next action.

Deterministic file names, model queries, launcher contents, config precedence, and failure codes belong to the runner, workflow specs, and artifact registry—not this skill.

## Outputs
The selected workflow's registered receipt/report/artifacts plus an exact next action.

## Deterministic validation
```powershell
Test-OpenCodeLspHarness.cmd
```

## Forbidden scope
Product/bootstrap code changes, secrets, destructive Git, existing OpenCode config mutation, confidential/private data on free endpoints, global free-model defaults, or claiming configuration proves live LSP diagnostics.

## Stop and escalate
Stop when the selected workflow names an external owner: missing/unsupported OpenCode runtime, provider authentication, privacy mismatch, product repair, or another writer's state.

## Proof ceiling
Only the selected workflow's proof ceiling. Live language-server behavior requires runtime observation.
