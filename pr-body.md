## Summary

Publish the stable, versioned external invocation and result contract that SysAdminSuite needs to request agent detection, install-missing behavior, repair eligibility, and smoke tests.

## Scope

- Versioned request schema (`agentswitchboard-invocation/v2`)
- Versioned result schema (`agentswitchboard-result/v2`)
- Contract validation and rejection logic
- Fixture-mode execution (no network, no real installers)
- CLI entrypoint for Windows and Linux
- Contract tests with rejection, validation, and fixture proof
- Documentation and routing

## Forbidden scope

- SysAdminSuite files
- Automatic authentication (OAuth, API key, browser, account)
- Secrets in arguments or artifacts
- Silent upgrades or replacement of healthy tools
- macOS support
- Real paid-provider calls
- Broad installer rewrites

## Proof ceiling

- Executable fixture contract proof: ✅
- CLI argument and normalized-result proof: ✅
- Schema validation and rejection proof: ✅
- No real agent installation proof (requires platform runtime)
- No authentication proof
- No hosted-model response proof
- No SysAdminSuite integration proof

## Safety

- Never invokes a hosted model or paid provider during fixture validation
- Never authenticates automatically
- Never emits token values, browser cookies, environment secrets, or full user paths
- Preserves healthy existing tools and configuration
