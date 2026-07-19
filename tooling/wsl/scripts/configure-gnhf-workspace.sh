#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OPENCODE_CONFIGURATOR="$SCRIPT_DIR/configure-opencode-free-defaults.sh"

PLAN_ONLY=false
if [[ "${1:-}" == "--plan-only" ]]; then
  PLAN_ONLY=true
elif [[ $# -gt 0 ]]; then
  echo "ERROR: unsupported argument: $1" >&2
  exit 2
fi

CONFIG_JSON=$(cat)
if [[ -z "$CONFIG_JSON" ]]; then
  echo "ERROR: no configuration JSON was provided on stdin." >&2
  exit 2
fi

for required in jq curl tar sha256sum; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "ERROR: required command is missing: $required" >&2
    exit 3
  fi
done
if [[ ! -f "$OPENCODE_CONFIGURATOR" ]]; then
  echo "ERROR: OpenCode free-default configurator is missing: $OPENCODE_CONFIGURATOR" >&2
  exit 3
fi

jq -e '.schemaVersion == 1 and (.gnhf.enabled | type == "boolean") and (.opencode.enabled | type == "boolean")' \
  >/dev/null <<<"$CONFIG_JSON" || {
  echo "ERROR: unsupported or malformed tmux/GNHF manifest." >&2
  exit 4
}

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

log() {
  printf '%s\n' "$*"
}

backup_once() {
  local path="$1"
  local suffix=".agent-switchboard-backup"
  if [[ -f "$path" && ! -e "${path}${suffix}" ]]; then
    cp -- "$path" "${path}${suffix}"
    log "[PASS] backup created: ${path}${suffix}"
  fi
}

write_managed_bashrc_block() {
  local bashrc="$HOME/.bashrc"
  local begin="# BEGIN AgentSwitchboard tmux/GNHF"
  local end="# END AgentSwitchboard tmux/GNHF"
  local temp
  temp=$(mktemp)

  touch "$bashrc"
  backup_once "$bashrc"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$bashrc" >"$temp"

  cat >>"$temp" <<'BLOCK'
# BEGIN AgentSwitchboard tmux/GNHF
export PATH="$HOME/.local/agent-switchboard/bin:$HOME/.local/agent-switchboard/npm/bin:$PATH"
export GNHF_TELEMETRY=0
# END AgentSwitchboard tmux/GNHF
BLOCK

  mv -- "$temp" "$bashrc"
  log "[PASS] managed Bash environment block installed."
}

node_major() {
  if ! command -v node >/dev/null 2>&1; then
    printf '0\n'
    return
  fi
  node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

install_official_node_lts() {
  local minimum_major="$1"
  local node_root="$2"
  local bin_dir="$3"
  local machine_arch node_arch index_file version archive base_url work_dir expected

  machine_arch=$(uname -m)
  case "$machine_arch" in
    x86_64|amd64) node_arch="x64" ;;
    aarch64|arm64) node_arch="arm64" ;;
    *)
      echo "ERROR: automatic Node installation does not support architecture: $machine_arch" >&2
      return 1
      ;;
  esac

  command -v xz >/dev/null 2>&1 || {
    echo "ERROR: xz is required for the verified Node archive install. Add xz-utils to the WSL package list." >&2
    return 1
  }

  work_dir=$(mktemp -d)
  trap 'rm -rf "$work_dir"' RETURN
  index_file="$work_dir/index.json"
  curl -fsSLo "$index_file" https://nodejs.org/dist/index.json

  version=$(jq -r --argjson minimum "$minimum_major" '
    [ .[]
      | select(.lts != false)
      | select((.version | ltrimstr("v") | split(".")[0] | tonumber) >= $minimum)
    ][0].version // empty
  ' "$index_file")

  if [[ -z "$version" ]]; then
    echo "ERROR: no official Node LTS release satisfied minimum major $minimum_major." >&2
    return 1
  fi

  archive="node-${version}-linux-${node_arch}.tar.xz"
  base_url="https://nodejs.org/dist/${version}"
  curl -fsSLo "$work_dir/$archive" "$base_url/$archive"
  curl -fsSLo "$work_dir/SHASUMS256.txt" "$base_url/SHASUMS256.txt"

  expected=$(awk -v filename="$archive" '$2 == filename { print $1 }' "$work_dir/SHASUMS256.txt")
  if [[ -z "$expected" ]]; then
    echo "ERROR: official SHASUMS256.txt did not list $archive." >&2
    return 1
  fi
  printf '%s  %s\n' "$expected" "$work_dir/$archive" | sha256sum --check --status

  mkdir -p "$node_root/versions" "$bin_dir"
  local version_root="$node_root/versions/$version"
  if [[ ! -d "$version_root" ]]; then
    local extract_root="$work_dir/extract"
    mkdir -p "$extract_root"
    tar -xJf "$work_dir/$archive" -C "$extract_root"
    mv -- "$extract_root/node-${version}-linux-${node_arch}" "$version_root"
  fi

  for command_name in node npm npx corepack; do
    if [[ -e "$version_root/bin/$command_name" ]]; then
      ln -sfn "$version_root/bin/$command_name" "$bin_dir/$command_name"
    fi
  done
  export PATH="$bin_dir:$PATH"
  log "[PASS] verified official Node installed: $(node --version)"
}

SCHEMA_VERSION=$(jq -r '.schemaVersion' <<<"$CONFIG_JSON")
GNHF_ENABLED=$(jq -r '.gnhf.enabled' <<<"$CONFIG_JSON")
OPENCODE_ENABLED=$(jq -r '.opencode.enabled' <<<"$CONFIG_JSON")
OPENCODE_CONFIG_PATH=$(expand_home_path "$(jq -r '.opencode.configPath // "~/.config/opencode/opencode.json"' <<<"$CONFIG_JSON")")
OPENCODE_DEFAULT_MODEL=$(jq -r '.opencode.defaultModel // "opencode/deepseek-v4-flash-free"' <<<"$CONFIG_JSON")
OPENCODE_SMALL_MODEL=$(jq -r '.opencode.smallModel // .opencode.defaultModel // "opencode/deepseek-v4-flash-free"' <<<"$CONFIG_JSON")
NODE_MINIMUM=$(jq -r '.node.minimumMajor // 20' <<<"$CONFIG_JSON")
NODE_AUTO_INSTALL=$(jq -r '.node.autoInstallOfficialLts // false' <<<"$CONFIG_JSON")
NODE_ROOT=$(expand_home_path "$(jq -r '.node.installRoot // "~/.local/agent-switchboard/node"' <<<"$CONFIG_JSON")")
GNHF_AUTO_INSTALL=$(jq -r '.gnhf.autoInstall // false' <<<"$CONFIG_JSON")
GNHF_PACKAGE=$(jq -r '.gnhf.npmPackage // "gnhf"' <<<"$CONFIG_JSON")
DEFAULT_AGENT=$(jq -r '.gnhf.defaultAgent // "opencode"' <<<"$CONFIG_JSON")
INSTALL_DEFAULT_AGENT=$(jq -r '.gnhf.installDefaultAgent // false' <<<"$CONFIG_JSON")
DEFAULT_AGENT_PACKAGE=$(jq -r '.gnhf.defaultAgentNpmPackage // "opencode-ai"' <<<"$CONFIG_JSON")
GNHF_CONFIG_PATH=$(expand_home_path "$(jq -r '.gnhf.configPath // "~/.gnhf/config.yml"' <<<"$CONFIG_JSON")")
PRESERVE_CONFIG=$(jq -r '.gnhf.preserveExistingConfig // true' <<<"$CONFIG_JSON")
DISABLE_TELEMETRY=$(jq -r '.gnhf.disableTelemetry // true' <<<"$CONFIG_JSON")
MAX_FAILURES=$(jq -r '.gnhf.maxConsecutiveFailures // 3' <<<"$CONFIG_JSON")
PREVENT_SLEEP=$(jq -r '.gnhf.preventSleep // true' <<<"$CONFIG_JSON")
COMMIT_PRESET=$(jq -r '.gnhf.commitMessagePreset // "conventional"' <<<"$CONFIG_JSON")
SAFE_WRAPPER_NAME=$(jq -r '.gnhf.safeWrapper.name // "gnhf-safe"' <<<"$CONFIG_JSON")
SAFE_WORKTREE=$(jq -r '.gnhf.safeWrapper.worktree // true' <<<"$CONFIG_JSON")
SAFE_PUSH=$(jq -r '.gnhf.safeWrapper.push // false' <<<"$CONFIG_JSON")
SAFE_MAX_ITERATIONS=$(jq -r '.gnhf.safeWrapper.maxIterations // 10' <<<"$CONFIG_JSON")
SAFE_MAX_TOKENS=$(jq -r '.gnhf.safeWrapper.maxTokens // 5000000' <<<"$CONFIG_JSON")

if [[ "$GNHF_ENABLED" != true ]]; then
  log "[SKIP] GNHF configuration is disabled in the manifest."
  exit 0
fi
if [[ "$OPENCODE_ENABLED" != true ]]; then
  echo "ERROR: the managed tmux workspace requires opencode.enabled=true." >&2
  exit 5
fi

if [[ ! "$DEFAULT_AGENT" =~ ^[a-z0-9_-]+$ ]]; then
  echo "ERROR: unsafe defaultAgent value: $DEFAULT_AGENT" >&2
  exit 5
fi
if [[ ! "$SAFE_WRAPPER_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: unsafe safeWrapper.name value: $SAFE_WRAPPER_NAME" >&2
  exit 5
fi
if (( NODE_MINIMUM < 20 || MAX_FAILURES < 1 || SAFE_MAX_ITERATIONS < 1 || SAFE_MAX_TOKENS < 1 )); then
  echo "ERROR: manifest numeric limits are invalid." >&2
  exit 5
fi
if [[ "$SAFE_PUSH" == true ]]; then
  echo "ERROR: the managed safe wrapper must not push automatically." >&2
  exit 5
fi

BIN_DIR="$HOME/.local/agent-switchboard/bin"
NPM_PREFIX="$HOME/.local/agent-switchboard/npm"
STATE_DIR="$HOME/.local/state/agent-switchboard/tmux-gnhf"
OPENCODE_SUMMARY_PATH="$STATE_DIR/opencode-free-defaults-summary.json"
mkdir -p "$BIN_DIR" "$STATE_DIR"
export PATH="$BIN_DIR:$NPM_PREFIX/bin:$PATH"

log "=== AgentSwitchboard tmux + GNHF configuration ==="
log "schemaVersion: $SCHEMA_VERSION"
log "planOnly: $PLAN_ONLY"
log "defaultAgent: $DEFAULT_AGENT"
log "openCodeConfig: $OPENCODE_CONFIG_PATH"
log "openCodeDefaultModel: $OPENCODE_DEFAULT_MODEL"

CURRENT_NODE_MAJOR=$(node_major)
if (( CURRENT_NODE_MAJOR < NODE_MINIMUM )); then
  if [[ "$NODE_AUTO_INSTALL" != true ]]; then
    echo "ERROR: Node $NODE_MINIMUM+ is required; detected major $CURRENT_NODE_MAJOR." >&2
    exit 6
  fi
  if [[ "$PLAN_ONLY" == true ]]; then
    log "[PLAN] Install a checksum-verified official Node LTS release under $NODE_ROOT."
  else
    install_official_node_lts "$NODE_MINIMUM" "$NODE_ROOT" "$BIN_DIR"
  fi
else
  log "[PASS] Node satisfies policy: $(node --version)"
fi

if [[ "$PLAN_ONLY" == true ]]; then
  log "[PLAN] Install or reuse npm package: $GNHF_PACKAGE"
  if [[ "$INSTALL_DEFAULT_AGENT" == true ]]; then
    log "[PLAN] Install or reuse default agent package: $DEFAULT_AGENT_PACKAGE"
  fi
  printf '%s' "$CONFIG_JSON" | bash "$OPENCODE_CONFIGURATOR" --plan-only
  log "[PLAN] Configure $GNHF_CONFIG_PATH, wrappers, telemetry, and bounded worktree defaults."
  exit 0
fi

command -v npm >/dev/null 2>&1 || {
  echo "ERROR: npm is unavailable after Node validation." >&2
  exit 6
}
mkdir -p "$NPM_PREFIX"

if ! command -v gnhf >/dev/null 2>&1; then
  if [[ "$GNHF_AUTO_INSTALL" != true ]]; then
    echo "ERROR: gnhf is missing and autoInstall is false." >&2
    exit 7
  fi
  npm install --global --prefix "$NPM_PREFIX" "$GNHF_PACKAGE"
fi
GNHF_BIN=$(command -v gnhf || true)
if [[ -z "$GNHF_BIN" && -x "$NPM_PREFIX/bin/gnhf" ]]; then
  GNHF_BIN="$NPM_PREFIX/bin/gnhf"
fi
[[ -x "$GNHF_BIN" ]] || {
  echo "ERROR: gnhf installation completed but no executable was found." >&2
  exit 7
}
log "[PASS] GNHF ready: $($GNHF_BIN --version | head -n 1)"

if ! command -v "$DEFAULT_AGENT" >/dev/null 2>&1; then
  if [[ "$INSTALL_DEFAULT_AGENT" != true ]]; then
    echo "ERROR: default agent '$DEFAULT_AGENT' is missing and installDefaultAgent is false." >&2
    exit 8
  fi
  npm install --global --prefix "$NPM_PREFIX" "$DEFAULT_AGENT_PACKAGE"
fi
DEFAULT_AGENT_BIN=$(command -v "$DEFAULT_AGENT" || true)
if [[ -z "$DEFAULT_AGENT_BIN" && -x "$NPM_PREFIX/bin/$DEFAULT_AGENT" ]]; then
  DEFAULT_AGENT_BIN="$NPM_PREFIX/bin/$DEFAULT_AGENT"
fi
[[ -x "$DEFAULT_AGENT_BIN" ]] || {
  echo "ERROR: default agent '$DEFAULT_AGENT' was not resolved to an executable." >&2
  exit 8
}
log "[PASS] default agent ready: $($DEFAULT_AGENT_BIN --version 2>/dev/null | head -n 1 || printf 'detected')"

printf '%s' "$CONFIG_JSON" | bash "$OPENCODE_CONFIGURATOR"
[[ -f "$OPENCODE_SUMMARY_PATH" ]] || {
  echo "ERROR: OpenCode free-default summary was not produced: $OPENCODE_SUMMARY_PATH" >&2
  exit 9
}

AGENT_WRAPPER="$BIN_DIR/${DEFAULT_AGENT}-gnhf"
cat >"$AGENT_WRAPPER" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "$DEFAULT_AGENT_BIN" "\$@"
WRAPPER
chmod 0755 "$AGENT_WRAPPER"

SAFE_WRAPPER="$BIN_DIR/$SAFE_WRAPPER_NAME"
WORKTREE_FLAG=""
if [[ "$SAFE_WORKTREE" == true ]]; then
  WORKTREE_FLAG="--worktree"
fi
cat >"$SAFE_WRAPPER" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "$GNHF_BIN" $WORKTREE_FLAG --max-iterations "$SAFE_MAX_ITERATIONS" --max-tokens "$SAFE_MAX_TOKENS" --prevent-sleep on "\$@"
WRAPPER
chmod 0755 "$SAFE_WRAPPER"

mkdir -p "$(dirname "$GNHF_CONFIG_PATH")"
PROPOSED_CONFIG="${GNHF_CONFIG_PATH}.agent-switchboard-proposed"
cat >"$PROPOSED_CONFIG" <<YAML
# Managed proposal generated by AgentSwitchboard.
# GNHF upstream: https://github.com/kunchenguid/gnhf
agent: $DEFAULT_AGENT
agentPathOverride:
  $DEFAULT_AGENT: $AGENT_WRAPPER
commitMessage:
  preset: $COMMIT_PRESET
maxConsecutiveFailures: $MAX_FAILURES
preventSleep: $PREVENT_SLEEP
YAML

CONFIG_STATUS="installed"
if [[ -f "$GNHF_CONFIG_PATH" && "$PRESERVE_CONFIG" == true ]]; then
  CONFIG_STATUS="preserved-existing"
  log "[WARN] Existing GNHF config preserved: $GNHF_CONFIG_PATH"
  log "[ACTION] Review proposed config: $PROPOSED_CONFIG"
else
  backup_once "$GNHF_CONFIG_PATH"
  mv -- "$PROPOSED_CONFIG" "$GNHF_CONFIG_PATH"
  log "[PASS] GNHF config installed: $GNHF_CONFIG_PATH"
fi

if [[ "$DISABLE_TELEMETRY" == true ]]; then
  write_managed_bashrc_block
fi

TMUX_VERSION=$(tmux -V 2>/dev/null || true)
NODE_VERSION=$(node --version 2>/dev/null || true)
GNHF_VERSION=$($GNHF_BIN --version 2>/dev/null | head -n 1 || true)
AGENT_VERSION=$($DEFAULT_AGENT_BIN --version 2>/dev/null | head -n 1 || true)
OPENCODE_CONFIG_STATUS=$(jq -r '.status' "$OPENCODE_SUMMARY_PATH")
SUMMARY_PATH="$STATE_DIR/setup-summary.json"

jq -n \
  --arg completedAt "$(date --iso-8601=seconds)" \
  --arg nodeVersion "$NODE_VERSION" \
  --arg gnhfVersion "$GNHF_VERSION" \
  --arg defaultAgent "$DEFAULT_AGENT" \
  --arg agentVersion "$AGENT_VERSION" \
  --arg configStatus "$CONFIG_STATUS" \
  --arg configPath "$GNHF_CONFIG_PATH" \
  --arg safeWrapper "$SAFE_WRAPPER" \
  --arg tmuxVersion "$TMUX_VERSION" \
  --arg openCodeConfigStatus "$OPENCODE_CONFIG_STATUS" \
  --arg openCodeConfigPath "$OPENCODE_CONFIG_PATH" \
  --arg openCodeDefaultModel "$OPENCODE_DEFAULT_MODEL" \
  --arg openCodeSmallModel "$OPENCODE_SMALL_MODEL" \
  '{
    schemaVersion: 1,
    completedAt: $completedAt,
    status: "completed",
    nodeVersion: $nodeVersion,
    gnhfVersion: $gnhfVersion,
    defaultAgent: $defaultAgent,
    agentVersion: $agentVersion,
    configStatus: $configStatus,
    configPath: $configPath,
    safeWrapper: $safeWrapper,
    tmuxVersion: $tmuxVersion,
    openCode: {
      configStatus: $openCodeConfigStatus,
      configPath: $openCodeConfigPath,
      defaultModel: $openCodeDefaultModel,
      smallModel: $openCodeSmallModel,
      paidDefaultAllowed: false
    },
    proof: {
      install: true,
      configuration: ($configStatus == "installed" and $openCodeConfigStatus == "installed"),
      authentication: false,
      hostedAgentResponse: false,
      tmuxPersistence: false
    }
  }' >"$SUMMARY_PATH"

log "[PASS] summary: $SUMMARY_PATH"
log "[READY] Start bounded work from a clean repository with: $SAFE_WRAPPER_NAME \"<objective>\""
