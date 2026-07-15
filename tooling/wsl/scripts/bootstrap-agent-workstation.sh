#!/usr/bin/env bash
set -euo pipefail

CONFIG_JSON=""

while IFS= read -r line; do
    CONFIG_JSON+="$line"
done

if [ -z "$CONFIG_JSON" ]; then
    echo "ERROR: No configuration JSON provided on stdin." >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Installing jq for configuration parsing..."
    if command -v apt &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq jq
    else
        echo "ERROR: jq not available and apt not found. Cannot parse configuration." >&2
        exit 1
    fi
fi

echo "$CONFIG_JSON" | jq -e . >/dev/null 2>&1 || {
    echo "ERROR: Invalid configuration JSON." >&2
    exit 1
}

DIST_NAME=$(echo "$CONFIG_JSON" | jq -r '.distribution.name // "Ubuntu"')
LINUX_DEV_ROOT=$(echo "$CONFIG_JSON" | jq -r '.linuxDevRoot // "~/dev"')
SKIP_PACKAGE_INSTALLATION=$(echo "$CONFIG_JSON" | jq -r '.skipPackageInstallation // false')
TMUX_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.tmux.enabled // false')
TMUX_CONFIG_DEST=$(echo "$CONFIG_JSON" | jq -r '.tmux.configDestination // "~/.tmux.conf"')
WEZTERM_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.wezterm.enabled // false')
WEZTERM_CONFIG_DEST=$(echo "$CONFIG_JSON" | jq -r '.wezterm.configDestination // "~/.wezterm.lua"')
DOTFILE_BACKUP=$(echo "$CONFIG_JSON" | jq -r '.dotfilePolicy.backupExisting // true')
DOTFILE_SUFFIX=$(echo "$CONFIG_JSON" | jq -r '.dotfilePolicy.backupSuffix // ".agent-switchboard-backup"')

echo "=== AgentSwitchboard WSL Bootstrap ==="
echo "Distribution: $DIST_NAME"
echo "Dev root: $LINUX_DEV_ROOT"
echo ""

backup_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        cp "$filepath" "${filepath}${DOTFILE_SUFFIX}"
        echo "  Backed up: $filepath -> ${filepath}${DOTFILE_SUFFIX}"
    fi
}

echo "--- Package Installation ---"

if [ "$SKIP_PACKAGE_INSTALLATION" = "true" ]; then
    echo "Package installation: skipped (prepared by the Windows guided orchestrator)"
elif command -v apt &>/dev/null; then
    echo "Updating apt package lists..."
    sudo apt-get update -qq

    PACKAGE_COUNT=$(echo "$CONFIG_JSON" | jq -r '.packages | length')
    for i in $(seq 0 $((PACKAGE_COUNT - 1))); do
        PKG=$(echo "$CONFIG_JSON" | jq -r ".packages[$i]")
        if dpkg -s "$PKG" &>/dev/null; then
            echo "  $PKG: already installed"
        else
            echo "  Installing $PKG..."
            sudo apt-get install -y -qq "$PKG"
        fi
    done
else
    echo "WARNING: apt not available. Skipping package installation."
fi

echo ""
echo "--- Development Root ---"

EXPANDED_DEV_ROOT=$(eval echo "$LINUX_DEV_ROOT")
if [ -d "$EXPANDED_DEV_ROOT" ]; then
    echo "Development root exists: $EXPANDED_DEV_ROOT"
else
    echo "Creating development root: $EXPANDED_DEV_ROOT"
    mkdir -p "$EXPANDED_DEV_ROOT"
fi

echo ""
echo "--- tmux Configuration ---"

if [ "$TMUX_ENABLED" = "true" ]; then
    if command -v tmux &>/dev/null; then
        echo "tmux is available: $(tmux -V)"
    else
        echo "tmux not found after package installation."
    fi

    EXPANDED_TMUX_DEST=$(eval echo "$TMUX_CONFIG_DEST")
    if [ "$DOTFILE_BACKUP" = "true" ]; then
        backup_file "$EXPANDED_TMUX_DEST"
    fi
    echo "tmux configuration destination: $EXPANDED_TMUX_DEST"
    echo "(Template applied by Windows-side installer if present)"
else
    echo "tmux configuration: skipped (disabled in manifest)"
fi

echo ""
echo "--- Agent Installation ---"

AGENT_COUNT=$(echo "$CONFIG_JSON" | jq -r '.agents | length')
for i in $(seq 0 $((AGENT_COUNT - 1))); do
    AGENT_NAME=$(echo "$CONFIG_JSON" | jq -r ".agents[$i].name")
    AGENT_ENABLED=$(echo "$CONFIG_JSON" | jq -r ".agents[$i].enabled")
    INSTALL_CMD=$(echo "$CONFIG_JSON" | jq -r ".agents[$i].installCommand")
    PROBE_CMD=$(echo "$CONFIG_JSON" | jq -r ".agents[$i].probeCommand")
    REQUIRES_NODE=$(echo "$CONFIG_JSON" | jq -r ".agents[$i].requiresNode // false")

    if [ "$AGENT_ENABLED" != "true" ]; then
        echo "  $AGENT_NAME: skipped (disabled)"
        continue
    fi

    if eval "$PROBE_CMD" &>/dev/null; then
        echo "  $AGENT_NAME: already installed ($(eval "$PROBE_CMD" 2>/dev/null | head -1))"
        continue
    fi

    if [ "$REQUIRES_NODE" = "true" ]; then
        if ! command -v node &>/dev/null; then
            echo "  $AGENT_NAME: BLOCKED (Node.js required but not found)"
            continue
        fi
        if ! command -v npm &>/dev/null; then
            echo "  $AGENT_NAME: BLOCKED (npm required but not found)"
            continue
        fi
    fi

    echo "  $AGENT_NAME: installing..."
    if eval "$INSTALL_CMD"; then
        if eval "$PROBE_CMD" &>/dev/null; then
            echo "  $AGENT_NAME: READY ($(eval "$PROBE_CMD" 2>/dev/null | head -1))"
        else
            echo "  $AGENT_NAME: installed but probe failed"
        fi
    else
        echo "  $AGENT_NAME: installation failed (exit code $?)"
    fi
done

echo ""
echo "--- Repository Cloning ---"

REPO_COUNT=$(echo "$CONFIG_JSON" | jq -r '.repositories | length')
for i in $(seq 0 $((REPO_COUNT - 1))); do
    REPO_NAME=$(echo "$CONFIG_JSON" | jq -r ".repositories[$i].name")
    REPO_URL=$(echo "$CONFIG_JSON" | jq -r ".repositories[$i].url")
    REPO_DEST=$(echo "$CONFIG_JSON" | jq -r ".repositories[$i].destination")
    REPO_BRANCH=$(echo "$CONFIG_JSON" | jq -r ".repositories[$i].branch // \"main\"")
    REPO_ENABLED=$(echo "$CONFIG_JSON" | jq -r ".repositories[$i].enabled")

    if [ "$REPO_ENABLED" != "true" ]; then
        echo "  $REPO_NAME: skipped (disabled)"
        continue
    fi

    EXPANDED_DEST=$(eval echo "$REPO_DEST")

    if [ -d "$EXPANDED_DEST/.git" ]; then
        CURRENT_REMOTE=$(git -C "$EXPANDED_DEST" remote get-url origin 2>/dev/null || echo "NO_REMOTE")
        if [ "$CURRENT_REMOTE" = "$REPO_URL" ]; then
            echo "  $REPO_NAME: already exists with correct remote"
        else
            echo "  $REPO_NAME: WARNING exists with wrong remote ($CURRENT_REMOTE, expected $REPO_URL)"
        fi
    else
        PARENT_DIR=$(dirname "$EXPANDED_DEST")
        mkdir -p "$PARENT_DIR"
        echo "  $REPO_NAME: cloning from $REPO_URL..."
        if git clone --branch "$REPO_BRANCH" "$REPO_URL" "$EXPANDED_DEST"; then
            echo "  $REPO_NAME: cloned successfully"
        else
            echo "  $REPO_NAME: clone failed"
        fi
    fi
done

echo ""
echo "--- Probe Summary ---"

PROBE_COMMANDS=("git:git --version" "tmux:tmux -V" "node:node --version" "npm:npm --version" "jq:jq --version")

for entry in "${PROBE_COMMANDS[@]}"; do
    CMD_NAME="${entry%%:*}"
    CMD_PROBE="${entry#*:}"
    if command -v "$CMD_NAME" &>/dev/null; then
        VERSION=$(eval "$CMD_PROBE" 2>/dev/null | head -1)
        echo "  $CMD_NAME: $VERSION"
    else
        echo "  $CMD_NAME: not found"
    fi
done

AGENT_PROBES=$(echo "$CONFIG_JSON" | jq -r '.agents[] | select(.enabled == true) | "\(.name):\(.probeCommand)"')
while IFS= read -r probe_entry; do
    [ -z "$probe_entry" ] && continue
    AGENT_NAME="${probe_entry%%:*}"
    AGENT_CMD="${probe_entry#*:}"
    if eval "$AGENT_CMD" &>/dev/null; then
        VERSION=$(eval "$AGENT_CMD" 2>/dev/null | head -1)
        echo "  $AGENT_NAME: $VERSION"
    else
        echo "  $AGENT_NAME: not found or probe failed"
    fi
done <<< "$AGENT_PROBES"

echo ""
echo "=== Bootstrap Complete ==="
