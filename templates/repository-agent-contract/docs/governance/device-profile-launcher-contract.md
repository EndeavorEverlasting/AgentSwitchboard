# Device Profile Launcher Contract

Canonical source: `EndeavorEverlasting/AgentSwitchboard`
Pinned contract version: `REPLACE_CONTRACT_VERSION`
Policy: `.ai/harness/device-profile-launcher.policy.json`

AgentSwitchboard owns one canonical launcher per platform profile. The Windows Profile is WezTerm-backed and uses idempotent `open-or-activate`. Consumer repositories delegate to the exact canonical launcher and may certify it, but they do not own discovery, activation, duplicate prevention, or raw frontend fallback.

Desktop shortcuts are presentation only and target the canonical launcher. A missing or uncertified launcher is blocked.

Windows, Linux, and Android are separate profile implementations. Android configuration may differ; one profile does not prove another profile works.

A request claiming installation, build, configuration, repair, certification, or deployment requires tracked implementation, focused validation, commit or GitHub evidence, and an honest proof ceiling. Contract-only doctrine does not prove a launcher exists or that a workspace opened or activated.

Validate with `scripts/Test-DeviceProfileLauncherContract.ps1`. Local rules may strengthen this doctrine. They may not weaken it.
