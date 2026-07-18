# Live cert model-route matrix (observed)

- Prompt kit: AI_Harness_Prompt_Kit_v39
- Related prompts: P37, P45, P47, P48, P49
- GNHF: 0.1.42 (CLI --model=False)
- Model pin authority: OpenCode preflight + OPENCODE_CONFIG_CONTENT
- Recommended default: deepseek/deepseek-v4-pro
- Capture note: sanitized fixture from a live Windows cert on 2026-07-18

| Model | Listed | Classification | Elapsed ms | Why |
| --- | --- | --- | --- | --- |
| `deepseek/deepseek-v4-pro` | True | ready | 6862 | Exact model listed and returned AGENT_SWITCHBOARD_MODEL_READY through Windows-safe dispatch. |
| `deepseek/deepseek-v4-flash` | True | ready | 5919 | Exact model listed and returned AGENT_SWITCHBOARD_MODEL_READY through Windows-safe dispatch. |
| `deepseek/deepseek-chat` | True | ready | 6081 | Exact model listed and returned AGENT_SWITCHBOARD_MODEL_READY through Windows-safe dispatch. |
| `deepseek/deepseek-reasoner` | True | ready | 6808 | Exact model listed and returned AGENT_SWITCHBOARD_MODEL_READY through Windows-safe dispatch. |

Proof ceiling: local authenticated marker and Windows dispatch only.
