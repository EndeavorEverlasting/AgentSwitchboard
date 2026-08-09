# ASB Wayfinder Operator Report

## Identity

- Repository: `<owner/repo>`
- Branch/ref: `<branch-or-ref>`
- Exact HEAD: `<40-hex-sha>`
- Run ID: `<run-id>`

## Runtime binding

- Binding source: `<explicit-parameter|ASB_WAYFINDER_PYTHON|VIRTUAL_ENV|repository-.venv|PATH>`
- Python executable: `<canonical sys.executable>`
- Python version: `<version>`
- Requirements: `tooling/harness/operational/contributions/requirements-wayfinder-public-plan.txt`

## Harness state

- Codebase map: `<pass|fail>`
- Workflow registry/spec: `<pass|fail>`
- Artifact registry: `<pass|fail>`
- Validator registry: `<pass|fail>`
- Optional hook: `<pass|fail|not-run>`
- Scoped skills: `<pass|fail>`
- Completeness check: `<pass|fail>`

## Validators

| Validator | Result | Evidence |
|---|---|---|
| Runtime binding static contract | `<result>` | `<command/artifact>` |
| Runtime binding PowerShell | `<result>` | `<command/artifact>` |
| Wayfinder Python | `<result>` | `<command/artifact>` |
| Wayfinder PowerShell | `<result>` | `<command/artifact>` |
| Contribution Python | `<result>` | `<command/artifact>` |
| Contribution PowerShell | `<result>` | `<command/artifact>` |
| Public plan | `<result>` | `<command/artifact>` |
| Agent documentation | `<result>` | `<command/artifact>` |
| Operational harness | `<result>` | `<command/artifact>` |
| git diff --check | `<result>` | `<range>` |

## Working

- `<human-readable list>`

## Broken or missing

- `<human-readable list or none>`

## Proof ceiling

This report proves only the checks actually executed against the exact recorded head. Static/hosted Wayfinder validation does not prove live GitHub tracker permissions/operations, human HITL participation, provider behavior, destination implementation, deployment, or acceptance.

## Next action

- Owner: `<actor>`
- Dependency: `<dependency>`
- Exact command/action: `<executable next step>`
- Expected artifact/proof: `<artifact>`
- Completion gate: `<observable gate>`
