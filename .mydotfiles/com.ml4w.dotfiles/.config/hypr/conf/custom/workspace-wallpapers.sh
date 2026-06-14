#!/usr/bin/env bash

# Per-workspace wallpaper manager
# Applies a different wallpaper per Hyprland workspace.

# Log file for debugging
LOG_FILE="$HOME/.cache/workspace-wallpapers.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

log "--- workspace-wallpapers.sh starting ---"

# Prevent multiple copies of this script from running as a background listener.
# One-shot invocations are not locked so they don't block on the daemon.
LOCK_FILE="/tmp/workspace-wallpapers.lock"
APPLY_ONCE=false
if [[ "$1" == "--apply-now" ]]; then
    APPLY_ONCE=true
    log "One-shot apply requested"
else
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log "Another instance is already running. Exiting."
        exit 0
    fi
    log "Lock acquired on $LOCK_FILE"
fi

for cmd in jq socat hyprctl awww; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Missing dependency: $cmd"
        exit 1
    fi
done
log "All dependencies found"

# Configuration file (managed by the Quickshell WorkspaceWallpaperAPP)
CONFIG_FILE="$HOME/.config/hypr/conf/custom/workspace-wallpapers.json"

# Active ML4W wallpaper (fallback for unassigned workspaces)
ACTIVE_WALLPAPER_FILE="$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper"

# Ultimate fallback if active ML4W wallpaper is missing
DEFAULT_WALLPAPER="$HOME/.config/ml4w/wallpapers/default.jpg"

# Ensure a configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo '{}' > "$CONFIG_FILE"
    log "Created empty config file: $CONFIG_FILE"
fi

# Get the active ML4W wallpaper to use as fallback
fallback_wallpaper() {
    if [[ -f "$ACTIVE_WALLPAPER_FILE" ]]; then
        cat "$ACTIVE_WALLPAPER_FILE"
    else
        echo "$DEFAULT_WALLPAPER"
    fi
}

# Resolve a wallpaper path from the config file for a given workspace name
get_workspace_wallpaper() {
    local workspace="$1"
    local path=""

    path=$(jq -r --arg ws "$workspace" '.[$ws] // empty' "$CONFIG_FILE" 2>/dev/null)

    # Expand $HOME / ~ if present
    path="${path//\$HOME/$HOME}"
    path="${path//\~/$HOME}"

    if [[ -z "$path" || ! -f "$path" ]]; then
        path=$(fallback_wallpaper)
    fi

    echo "$path"
}

start_awww() {
    if awww query >/dev/null 2>&1; then
        log "awww-daemon already running"
    else
        log "Starting awww-daemon..."
        awww-daemon >/dev/null 2>&1 &
        sleep 0.5
        if awww query >/dev/null 2>&1; then
            log "awww-daemon started successfully"
        else
            log "ERROR: awww-daemon failed to start"
        fi
    fi
}

set_wallpapers() {
    local monitors_json wallpaper
    monitors_json=$(hyprctl monitors -j)

    # Apply a per-workspace wallpaper on each monitor
    echo "$monitors_json" | jq -r '.[] | "\(.name)\t\(.activeWorkspace.name)"' | while IFS=$'\t' read -r monitor workspace; do
        wallpaper="$(get_workspace_wallpaper "$workspace")"

        if [[ -f "$wallpaper" ]]; then
            log "Setting $monitor (workspace $workspace) -> $wallpaper"
            awww img "$wallpaper" \
                -o "$monitor" \
                --transition-type fade \
                --transition-duration 0.4
        else
            log "Wallpaper not found: $wallpaper"
        fi
    done
}

start_awww
set_wallpapers

if [[ "$APPLY_ONCE" == true ]]; then
    log "One-shot apply complete, exiting"
    exit 0
fi

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
log "Using Hyprland socket2: $SOCKET"

# Listen for workspace/monitor events and restart socat if it exits
while true; do
    log "Starting socat listener..."
    socat -u UNIX-CONNECT:"$SOCKET" - | while read -r event; do
        case "$event" in
            workspace\>\>*|focusedmon\>\>*|moveworkspace\>\>*)
                log "Received event: $event"
                set_wallpapers
                ;;
        esac
    done
    log "socat exited (pipe status: ${PIPESTATUS[*]}), restarting in 2 seconds..."
    sleep 2
done
