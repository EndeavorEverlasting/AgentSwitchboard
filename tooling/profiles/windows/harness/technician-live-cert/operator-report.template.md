# Technician Live-Cert Harness Status

- Repository: `{{repository}}`
- Branch: `{{branch}}`
- HEAD: `{{head}}`
- Generated: `{{generatedAt}}`
- Status: **{{status}}**
- Proof ceiling: {{proofCeiling}}

## Components

{{componentTable}}

## Runtime-compatibility guards

{{guardTable}}

## Operator-command envelope

- Status: **{{operatorCommandStatus}}**
- Registered sources scanned: **{{operatorCommandSourceCount}}**
- Violations: **{{operatorCommandViolationCount}}**
- Fixture failures: **{{operatorCommandFixtureFailureCount}}**

{{operatorCommandViolationTable}}

## Validator results

{{validatorTable}}

## Working

{{working}}

## Broken or blocked

{{blocked}}

## Missing

{{missing}}

## Owner, dependency, artifact, and completion gate

- Owner: {{nextOwner}}
- Dependency: {{nextDependency}}
- Expected artifact: {{nextArtifact}}
- Completion gate: {{nextCompletionGate}}

## Exact next command

```powershell
{{nextCommand}}
```
