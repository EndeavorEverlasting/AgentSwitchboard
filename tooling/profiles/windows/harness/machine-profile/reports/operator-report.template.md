# Windows Machine-Profile Harness Operator Report

## Identity

- Repository: `{{repository}}`
- Branch: `{{branch}}`
- HEAD: `{{head}}`
- Environment role: `{{environmentRoleId}}`
- Repository-root source: `{{repositoryRootSource}}`
- Generated: `{{generatedAt}}`

## Harness state

- Overall: **{{status}}**
- Required components: `{{presentCount}}/{{requiredCount}}`
- Missing components: `{{missingComponents}}`
- Tracked-file check: `{{trackedStatus}}`

## Working

{{workingSummary}}

## Broken or blocked

{{blockedSummary}}

## Missing

{{missingSummary}}

## Validation

{{validationSummary}}

## Proof ceiling

{{proofCeiling}}

## Exact next command

```cmd
{{nextCommand}}
```
