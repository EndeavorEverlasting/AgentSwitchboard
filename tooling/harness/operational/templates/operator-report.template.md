# AgentSwitchboard Operational Harness Report

## Repository state

- repository: `{{repository}}`
- branch: `{{branch}}`
- branch source: `{{branchSource}}`
- branch ref: `{{branchRef}}`
- HEAD: `{{head}}`
- expected HEAD: `{{expectedHead}}`
- PR: `{{pullRequest}}`
- dirty: `{{dirty}}`
- generated UTC: `{{generatedUtc}}`

## Harness summary

- working components: `{{workingCount}}`
- missing components: `{{missingCount}}`
- selected workflow: `{{selectedWorkflow}}`
- selected specialized route: `{{specializedRoute}}`
- validation gate complete: `{{validationGateComplete}}`

## Working

{{workingList}}

## Broken or missing

{{missingList}}

## Validation receipts

{{validationReceipts}}

## Validator entrypoints

{{validatorList}}

## Known traps

{{trapList}}

## Proof ceiling

{{proofCeiling}}

## Next action

- owner: `{{nextOwner}}`
- dependency: {{nextDependency}}
- proof produced: {{nextProof}}
- command: `{{nextCommand}}`

This report is generated from tracked harness registries plus read-only local Git observation and explicit caller receipts. It is not runtime, deployment, provider, remote-host, merge-authorization, or operator-acceptance proof.
