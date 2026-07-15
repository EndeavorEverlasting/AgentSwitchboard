#!/usr/bin/env bash
set -euo pipefail

CONFIG_JSON=$(cat)
if [[ -z "$CONFIG_JSON" ]]; then
    echo "ERROR: No configuration JSON provided on stdin." >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq for configuration parsing..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq jq
    else
        echo "ERROR: jq not available and apt-get not found. Cannot parse configuration." >&2
        exit 1
    fi
fi

if ! jq -e . >/dev/null 2>&1 <<<"$CONFIG_JSON"; then
    echo "ERROR: Invalid configuration JSON." >&2
    exit 1
fi

DIST_NAME=$(jq -r '.distribution.name // "Ubuntu"' <<<"$CONFIG_JSON")
LINUX_DEV_ROOT=$(jq -r '.linuxDevRoot // "~/dev"' <<<"$CONFIG_JSON")
TMUX_ENABLED=$(jq -r '.tmux.enabled // false' <<<"$CONFIG_JSON")
TMUX_CONFIG_DEST=$(jq -r '.tmux.configDestination // "~/.tmux.conf"' <<<"$CONFIG_JSON")
DOTFILE_BACKUP=$(jq -r '.dotfilePolicy.backupExisting // true' <<<"$CONFIG_JSON")
DOTFILE_SUFFIX=$(jq -r '.dotfilePolicy.backupSuffix // ".agent-switchboard-backup"' <<<"$CONFIG_JSON")
FAILURES=0

record_failure() {
    echo "ERROR: $*" >&2
    FAILURES=1
}

expand_home_path() {
    local value="$1"
    case "$value" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${value#\~/}" ;;
        "$HOME"|"$HOME/"*) printf '%s\n' "$value" ;;
        *)
            echo "ERROR: Path must resolve under the current Linux home: $value" >&2
            return 1
            ;;
    esac
}

backup_file() {
    local filepath="$1"
    local backup="${filepath}${DOTFILE_SUFFIX}"
    if [[ ! -f "$filepath" ]]; then
        return 0
    fi
    if [[ -e "$backup" || -L "$backup" ]]; then
        echo "  Backup preserved: $backup"
        return 0
    fi
    if cp -p -- "$filepath" "$backup"; then
        echo "  Backed up: $filepath -> $backup"
    else
        record_failure "Could not back up $filepath"
    fi
}

probe_agent() {
    local agent="$1"
    case "$agent" in
        opencode) opencode --version ;;
        agy) agy --help ;;
        goose) goose --version ;;
        *) return 2 ;;
    esac
}

install_agent() {
    local agent="$1"
    case "$agent" in
        opencode)
            npm install --global opencode-ai
            ;;
        agy)
            npm install --global @anthropic-ai/agy
            ;;
        goose)
            local temp
            temp=$(mktemp)
            if ! curl -fsSL https://github.com/block/goose/releases/latest/download/goose-linux-x86_64 -o "$temp"; then
                rm -f -- "$temp"
                return 1
            fi
            if ! sudo install -m 0755 "$temp" /usr/local/bin/goose; then
                rm -f -- "$temp"
                return 1
            fi
            rm -f -- "$temp"
            ;;
        *)
            echo "Unsupported governed agent: $agent" >&2
            return 2
            ;;
    esac
}

print_agent_version() {
    local agent="$1"
    probe_agent "$agent" 2>/dev/null | head -n 1
}

echo "=== AgentSwitchboard WSL Bootstrap ==="
echo "Distribution: $DIST_NAME"
echo "Dev root: $LINUX_DEV_ROOT"
echo

echo "--- Package Installation ---"
if command -v apt-get >/dev/null 2>&1; then
    if ! sudo apt-get update -qq; then
        record_failure "apt package index update failed"
    fi
    while IFS= read -r package; do
        [[ -z "$package" ]] && continue
        if [[ ! "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9+.-]*$ ]]; then
            record_failure "Rejected invalid package name: $package"
            continue
        fi
        if dpkg -s "$package" >/dev/null 2>&1; then
            echo "  $package: already installed"
        else
            echo "  Installing $package..."
            if ! sudo apt-get install -y -qq "$package"; then
                record_failure "Package installation failed: $package"
            fi
        fi
    done < <(jq -r '.packages[]?' <<<"$CONFIG_JSON")
else
    record_failure "apt-get is unavailable; package installation was not performed"
fi

echo
echo "--- Development Root ---"
if EXPANDED_DEV_ROOT=$(expand_home_path "$LINUX_DEV_ROOT"); then
    if [[ -d "$EXPANDED_DEV_ROOT" ]]; then
        echo "Development root exists: $EXPANDED_DEV_ROOT"
    else
        echo "Creating development root: $EXPANDED_DEV_ROOT"
        if ! mkdir -p -- "$EXPANDED_DEV_ROOT"; then
            record_failure "Could not create development root"
        fi
    fi
else
    record_failure "Development root is outside the governed home boundary"
    EXPANDED_DEV_ROOT="$HOME/dev"
fi

echo
echo "--- tmux Configuration ---"
if [[ "$TMUX_ENABLED" == "true" ]]; then
    if command -v tmux >/dev/null 2>&1; then
        echo "tmux is available: $(tmux -V)"
    else
        record_failure "tmux not found after package installation"
    fi
    if EXPANDED_TMUX_DEST=$(expand_home_path "$TMUX_CONFIG_DEST"); then
        if [[ "$DOTFILE_BACKUP" == "true" ]]; then
            backup_file "$EXPANDED_TMUX_DEST"
        fi
        echo "tmux configuration destination: $EXPANDED_TMUX_DEST"
        echo "(Template applied by Windows-side installer if present)"
    else
        record_failure "tmux configuration destination is outside the governed home boundary"
    fi
else
    echo "tmux configuration: skipped (disabled in manifest)"
fi

echo
echo "--- Agent Installation ---"
while IFS=$'\t' read -r agent enabled requires_node; do
    [[ -z "$agent" ]] && continue
    case "$agent" in
        opencode|agy|goose) ;;
        *)
            record_failure "Unsupported agent in manifest: $agent"
            continue
            ;;
    esac
    if [[ "$enabled" != "true" ]]; then
        echo "  $agent: skipped (disabled)"
        continue
    fi
    if probe_agent "$agent" >/dev/null 2>&1; then
        echo "  $agent: already installed ($(print_agent_version "$agent"))"
        continue
    fi
    if [[ "$requires_node" == "true" ]]; then
        if ! command -v node >/dev/null 2>&1; then
            record_failure "$agent is blocked because Node.js is missing"
            continue
        fi
        if ! command -v npm >/dev/null 2>&1; then
            record_failure "$agent is blocked because npm is missing"
            continue
        fi
    fi
    echo "  $agent: installing through governed argv..."
    if ! install_agent "$agent"; then
        record_failure "$agent installation failed"
        continue
    fi
    if probe_agent "$agent" >/dev/null 2>&1; then
        echo "  $agent: READY ($(print_agent_version "$agent"))"
    else
        record_failure "$agent installed but its governed probe failed"
    fi
done < <(jq -r '.agents[]? | [.name, (.enabled // false), (.requiresNode // false)] | @tsv' <<<"$CONFIG_JSON")

echo
echo "--- Repository Cloning ---"
while IFS=$'\t' read -r repo_name repo_url repo_dest repo_branch repo_enabled; do
    [[ -z "$repo_name" ]] && continue
    if [[ "$repo_enabled" != "true" ]]; then
        echo "  $repo_name: skipped (disabled)"
        continue
    fi
    case "$repo_url" in
        https://github.com/*/*.git|git@github.com:*/*.git) ;;
        *)
            record_failure "$repo_name has a non-allowlisted repository URL"
            continue
            ;;
    esac
    if [[ ! "$repo_branch" =~ ^[A-Za-z0-9._/-]+$ || "$repo_branch" == *..* ]]; then
        record_failure "$repo_name has an invalid branch name"
        continue
    fi
    if ! expanded_dest=$(expand_home_path "$repo_dest"); then
        record_failure "$repo_name destination is outside the governed home boundary"
        continue
    fi
    if [[ -d "$expanded_dest/.git" ]]; then
        current_remote=$(git -C "$expanded_dest" remote get-url origin 2>/dev/null || printf 'NO_REMOTE')
        if [[ "$current_remote" == "$repo_url" ]]; then
            echo "  $repo_name: already exists with correct remote"
        else
            record_failure "$repo_name exists with the wrong remote"
        fi
        continue
    fi
    mkdir -p -- "$(dirname "$expanded_dest")"
    echo "  $repo_name: cloning from $repo_url..."
    if git clone --branch "$repo_branch" -- "$repo_url" "$expanded_dest"; then
        echo "  $repo_name: cloned successfully"
    else
        record_failure "$repo_name clone failed"
    fi
done < <(jq -r '.repositories[]? | [.name, .url, .destination, (.branch // "main"), (.enabled // false)] | @tsv' <<<"$CONFIG_JSON")

echo
echo "--- Probe Summary ---"
for command_name in git tmux node npm jq; do
    if command -v "$command_name" >/dev/null 2>&1; then
        case "$command_name" in
            git) version=$(git --version 2>/dev/null | head -n 1) ;;
            tmux) version=$(tmux -V 2>/dev/null | head -n 1) ;;
            node) version=$(node --version 2>/dev/null | head -n 1) ;;
            npm) version=$(npm --version 2>/dev/null | head -n 1) ;;
            jq) version=$(jq --version 2>/dev/null | head -n 1) ;;
        esac
        echo "  $command_name: $version"
    else
        echo "  $command_name: not found"
    fi
done

while IFS= read -r agent; do
    [[ -z "$agent" ]] && continue
    if probe_agent "$agent" >/dev/null 2>&1; then
        echo "  $agent: $(print_agent_version "$agent")"
    else
        echo "  $agent: not found or probe failed"
    fi
done < <(jq -r '.agents[]? | select(.enabled == true) | .name' <<<"$CONFIG_JSON")

echo
if [[ "$FAILURES" -ne 0 ]]; then
    echo "=== Bootstrap Completed With Failures ===" >&2
    exit 1
fi

echo "=== Bootstrap Complete ==="
