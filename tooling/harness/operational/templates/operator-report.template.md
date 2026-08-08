# AgentSwitchboard Operational Harness Report

## Repository state

- repository: `{{repository}}`
- branch: `{{branch}}`
- HEAD: `{{head}}`
- dirty: `{{dirty}}`
- generated UTC: `{{generatedUtc}}`

## Harness summary

- working components: `{{workingCount}}`
- missing components: `{{missingCount}}`
- selected workflow: `{{selectedWorkflow}}`
- selected specialized route: `{{specializedRoute}}`

## Working

{{workingList}}

## Broken or missing

{{missingList}}

## Validator entrypoints

{{validatorList}}

## Known traps

{{trapList}}

## Proof ceiling

{{proofCeiling}}

## Next action

`{{nextCommand}}`

This report is generated from tracked harness registries plus read-only local Git observation. It is not runtime, deployment, provider, remote-host, or operator-acceptance proof.
