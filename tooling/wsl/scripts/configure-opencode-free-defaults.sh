#!/usr/bin/env bash
set -euo pipefail

PLAN_ONLY=false
if [[ "${1:-}" == "--plan-only" ]]; then
  PLAN_ONLY=true
elif [[ $# -gt 0 ]]; then
  echo "ERROR: unsupported argument: $1" >&2
  exit 2
fi

CONFIG_JSON=$(cat)
if [[ -z "$CONFIG_JSON" ]]; then
  echo "ERROR: no workstation configuration JSON was provided on stdin." >&2
  exit 2
fi

for required in jq mktemp; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "ERROR: required command is missing: $required" >&2
    exit 3
  fi
done

expand_home_path() {
  local value="$1"
  if [[ "$value" == "~" ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$value" == "~/"* ]]; then
    printf '%s/%s\n' "$HOME" "${value:2}"
  else
    printf '%s\n' "$value"
  fi
}

OPENCODE_ENABLED=$(jq -r '.opencode.enabled // false' <<<"$CONFIG_JSON")
if [[ "$OPENCODE_ENABLED" != true ]]; then
  echo "[SKIP] OpenCode free-default configuration is disabled in the manifest."
  exit 0
fi

CONFIG_PATH=$(expand_home_path "$(jq -r '.opencode.configPath // "~/.config/opencode/opencode.json"' <<<"$CONFIG_JSON")")
DEFAULT_MODEL=$(jq -r '.opencode.defaultModel // "opencode/deepseek-v4-flash-free"' <<<"$CONFIG_JSON")
SMALL_MODEL=$(jq -r '.opencode.smallModel // .opencode.defaultModel // "opencode/deepseek-v4-flash-free"' <<<"$CONFIG_JSON")
SHARE_MODE=$(jq -r '.opencode.share // "disabled"' <<<"$CONFIG_JSON")
RESTRICT_FREE=$(jq -r '.opencode.restrictZenToFreeModels // true' <<<"$CONFIG_JSON")
FREE_MODEL_IDS=$(jq -c '.opencode.freeModelIds // ["deepseek-v4-flash-free"]' <<<"$CONFIG_JSON")
STATE_DIR="$HOME/.local/state/agent-switchboard/tmux-gnhf"
SUMMARY_PATH="$STATE_DIR/opencode-free-defaults-summary.json"

if [[ ! "$DEFAULT_MODEL" =~ ^opencode/[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: defaultModel must use the opencode/<model-id> format: $DEFAULT_MODEL" >&2
  exit 4
fi
if [[ ! "$SMALL_MODEL" =~ ^opencode/[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: smallModel must use the opencode/<model-id> format: $SMALL_MODEL" >&2
  exit 4
fi
if [[ "$SHARE_MODE" != "disabled" ]]; then
  echo "ERROR: managed workstation OpenCode sharing must remain disabled." >&2
  exit 4
fi
if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and test("^[A-Za-z0-9._-]+$"))' >/dev/null <<<"$FREE_MODEL_IDS"; then
  echo "ERROR: freeModelIds must be a non-empty array of provider-local model IDs." >&2
  exit 4
fi

DEFAULT_ID=${DEFAULT_MODEL#opencode/}
SMALL_ID=${SMALL_MODEL#opencode/}
if ! jq -e --arg model "$DEFAULT_ID" 'index($model) != null' >/dev/null <<<"$FREE_MODEL_IDS"; then
  echo "ERROR: defaultModel is not included in freeModelIds: $DEFAULT_MODEL" >&2
  exit 4
fi
if ! jq -e --arg model "$SMALL_ID" 'index($model) != null' >/dev/null <<<"$FREE_MODEL_IDS"; then
  echo "ERROR: smallModel is not included in freeModelIds: $SMALL_MODEL" >&2
  exit 4
fi
if jq -e 'any(.[]; test("(^|[-_.])(pro|paid)([-_.]|$)"; "i"))' >/dev/null <<<"$FREE_MODEL_IDS"; then
  echo "ERROR: freeModelIds contains a paid-looking model identifier." >&2
  exit 4
fi

if [[ "$PLAN_ONLY" == true ]]; then
  echo "[PLAN] OpenCode config: $CONFIG_PATH"
  echo "[PLAN] Default model: $DEFAULT_MODEL"
  echo "[PLAN] Small model: $SMALL_MODEL"
  echo "[PLAN] Restrict OpenCode Zen picker to verified free IDs: $RESTRICT_FREE"
  exit 0
fi

mkdir -p "$(dirname "$CONFIG_PATH")" "$STATE_DIR"
TEMP_INPUT=$(mktemp)
TEMP_OUTPUT=$(mktemp)
trap 'rm -f "$TEMP_INPUT" "$TEMP_OUTPUT"' EXIT

if [[ -f "$CONFIG_PATH" ]]; then
  if ! jq -e 'type == "object"' "$CONFIG_PATH" >/dev/null; then
    echo "ERROR: existing OpenCode config is not a valid JSON object: $CONFIG_PATH" >&2
    exit 5
  fi
  cp -- "$CONFIG_PATH" "$TEMP_INPUT"
  BACKUP_PATH="${CONFIG_PATH}.agent-switchboard-backup-$(date +%Y%m%d-%H%M%S)"
  cp -- "$CONFIG_PATH" "$BACKUP_PATH"
  echo "[PASS] OpenCode config backup: $BACKUP_PATH"
else
  printf '{}\n' >"$TEMP_INPUT"
  BACKUP_PATH=""
fi

jq -S \
  --arg model "$DEFAULT_MODEL" \
  --arg smallModel "$SMALL_MODEL" \
  --arg share "$SHARE_MODE" \
  --argjson restrictFree "$RESTRICT_FREE" \
  --argjson freeModels "$FREE_MODEL_IDS" '
    .["$schema"] = "https://opencode.ai/config.json"
    | .model = $model
    | .small_model = $smallModel
    | .share = $share
    | if has("disabled_providers") then
        .disabled_providers = ((.disabled_providers // []) | map(select(. != "opencode")))
      else . end
    | if has("enabled_providers") then
        .enabled_providers = (((.enabled_providers // []) + ["opencode"]) | unique)
      else . end
    | .provider = (.provider // {})
    | .provider.opencode = (.provider.opencode // {})
    | if $restrictFree then .provider.opencode.whitelist = $freeModels else . end
  ' "$TEMP_INPUT" >"$TEMP_OUTPUT"

jq -e \
  --arg model "$DEFAULT_MODEL" \
  --arg smallModel "$SMALL_MODEL" \
  --argjson freeModels "$FREE_MODEL_IDS" '
    .model == $model
    and .small_model == $smallModel
    and .share == "disabled"
    and .provider.opencode.whitelist == $freeModels
    and ((.disabled_providers // []) | index("opencode") | not)
  ' "$TEMP_OUTPUT" >/dev/null

mv -- "$TEMP_OUTPUT" "$CONFIG_PATH"
chmod 0600 "$CONFIG_PATH"

jq -n \
  --arg completedAt "$(date --iso-8601=seconds)" \
  --arg configPath "$CONFIG_PATH" \
  --arg defaultModel "$DEFAULT_MODEL" \
  --arg smallModel "$SMALL_MODEL" \
  --arg backupPath "$BACKUP_PATH" \
  --argjson freeModelIds "$FREE_MODEL_IDS" \
  '{
    schemaVersion: 1,
    completedAt: $completedAt,
    status: "installed",
    configPath: $configPath,
    defaultModel: $defaultModel,
    smallModel: $smallModel,
    freeModelIds: $freeModelIds,
    backupPath: (if $backupPath == "" then null else $backupPath end),
    paidDefaultAllowed: false,
    credentialsChanged: false
  }' >"$SUMMARY_PATH"

printf '[PASS] OpenCode free defaults installed: %s\n' "$CONFIG_PATH"
printf '[PASS] OpenCode default model: %s\n' "$DEFAULT_MODEL"
printf '[PASS] OpenCode small model: %s\n' "$SMALL_MODEL"
printf '[PASS] Summary: %s\n' "$SUMMARY_PATH"
