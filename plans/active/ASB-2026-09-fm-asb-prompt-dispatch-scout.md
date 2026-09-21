# FirstMate prompt-dispatch scout (remote-safe RRB-03 seam)

Remote-safe durable-inbox prompt-dispatch scout that uses `build_prompt_dispatch` (RRB-03) to demonstrate routing-decision → prompt-dispatch translation without claiming live crew delivery or dual-path vision complete.

## Mission

Implement a contract-only translation demonstration from `prompt-kit.routing-decision/v1` to `asb.prompt-dispatch/v1` using the RRB-03 builder, with fail-closed host blocking on Linux/cloud and no live FirstMate invocation.

## Delivery

- **Branch:** `cursor/fm-asb-prompt-dispatch-scout-8400`
- **Pull Request:** [#334](https://github.com/EndeavorEverlasting/AgentSwitchboard/pull/334)
- **Base:** `main`
- **Status:** Ready for review

## Implementation

**Scout entrypoints:**
- `tooling/firstmate/harness/dispatch/scout_prompt_dispatch.py` — Python scout with dry-run and live-delivery modes
- `tooling/firstmate/harness/dispatch/Invoke-PromptDispatchScout.ps1` — PowerShell wrapper

**Default mode: dry-run (contract-only translation)**
- Loads a `prompt-kit.routing-decision/v1` fixture
- Calls `build_prompt_dispatch(...)` from RRB-03
- Writes `asb.prompt-dispatch/v1` artifact to local untracked evidence
- Does NOT invoke fm-send, tmux, or FirstMate lifecycle

**Live-delivery mode:**
- Fails-closed on Linux with `BLOCKED_LINUX_WSL_REQUIRED` (cloud agent environment)
- Returns `UNIMPLEMENTED` on Windows (future work: Admin Box detection + fm-send)

## Tests

- **12 new scout tests** — all pass (dry-run PASS, live-delivery blocked, variables, authority, determinism, proof ceiling)
- **Existing protocol and builder tests** — unchanged, all pass

## Validation

```bash
python3 tests/test_fm_asb_prompt_dispatch_scout.py
python3 tests/test_fm_asb_promptkit_protocol_contract.py
python3 tests/test_fm_asb_prompt_dispatch_builder.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-PublicPlanContracts.ps1
git diff --check origin/main...HEAD
```

## Proof Ceiling

**`SCOUT_CONTRACT_STATIC`** — proves contract-only translation from routing-decision to prompt-dispatch with fail-closed host blocking.

**Does NOT prove:**
- Live FirstMate delivery or fm-send invocation
- Admin Box runtime success
- Crew execution or dual-path vision complete
- FM-CREW-13 completion

## Next Executable Owners

1. Prompt Kit routing adapter implementation (separate lane)
2. Admin Box live-delivery implementation (fm-send invocation)
3. Context-pressure observation and crew-task rollover

## Related

- **Plan ID:** ASB-2026-09-FM-ASB-PROMPT-DISPATCH-SCOUT
- **Dependencies:** ASB-2026-09-FM-ASB-PROMPTKIT-PROTOCOL-V1 (RRB-03 @ ee4b746)
- **Architecture:** docs/architecture/fm-asb-promptkit-protocol-v1.md
- **Wave:** FirstMate↔ASB↔PromptKit boundary
