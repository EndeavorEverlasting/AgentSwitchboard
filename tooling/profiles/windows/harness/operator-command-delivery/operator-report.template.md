# Operator Command Delivery Report

Status: {{STATUS}}
Repository: {{REPOSITORY}}
Requested ref: {{REQUESTED_REF}}
Resolved commit: {{RESOLVED_COMMIT}}
Shell: {{SHELL}}

## Source resolution

- Required files: {{FILES}}
- Resolution result: {{SOURCE_RESULT}}
- Read semantics: explicit GET; no assumed remote content path

## Child executable launch

- Exact executable: {{CHILD_EXECUTABLE}}
- Bounded probe: {{CHILD_LAUNCH_PROBE}}
- Launch result: {{CHILD_LAUNCH_RESULT}}
- Start error: {{CHILD_START_ERROR}}
- Launch artifact: {{CHILD_LAUNCH_ARTIFACT}}

## Transport integrity

- PowerShell environment tokens: {{ENV_TOKEN_RESULT}}
- Prompt/transcript contamination: {{PROMPT_RESULT}}
- URL/query escaping: {{URL_RESULT}}
- Parent-shell exit safety: {{SHELL_EXIT_RESULT}}

## Execution

- Child command: {{CHILD_COMMAND}}
- Child exit code: {{CHILD_EXIT_CODE}}
- Canonical downstream artifact: {{DOWNSTREAM_ARTIFACT}}

## State

- Working: {{WORKING}}
- Broken: {{BROKEN}}
- Missing: {{MISSING}}
- Risk: {{RISK}}

## Proof ceiling

{{PROOF_CEILING}}

## Next executable action

{{NEXT_COMMAND}}
