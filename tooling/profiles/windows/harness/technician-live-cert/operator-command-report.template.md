# Operator Command Envelope Report

- Repository: `{{repository}}`
- Generated: `{{generatedAt}}`
- Status: **{{status}}**
- Registered sources scanned: **{{sourceCount}}**
- Violations: **{{violationCount}}**
- Fixture failures: **{{fixtureFailureCount}}**
- Proof ceiling: {{proofCeiling}}

## Violations

{{violationTable}}

## Fixture contract

{{fixtureTable}}

## Sanitized executable input

```shell
{{sanitizedCommand}}
```

## Owner, dependency, and completion gate

- Owner: {{owner}}
- Dependency: {{dependency}}
- Expected artifact: {{artifact}}
- Completion gate: {{completionGate}}

## Exact next command

```powershell
{{nextCommand}}
```
