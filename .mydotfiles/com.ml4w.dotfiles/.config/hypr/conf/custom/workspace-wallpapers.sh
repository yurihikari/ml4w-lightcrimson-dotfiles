#!/usr/bin/env bash

# Per-workspace wallpaper manager
# Applies a different wallpaper per Hyprland workspace.

# Log file for debugging
LOG_FILE="$HOME/.cache/workspace-wallpapers.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

log "--- workspace-wallpapers.sh starting ---"

# Prevent multiple copies of this script from running
LOCK_FILE="/tmp/workspace-wallpapers.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another instance is already running. Exiting."
    exit 0
fi
log "Lock acquired on $LOCK_FILE"

for cmd in jq socat hyprctl awww; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Missing dependency: $cmd"
        exit 1
    fi
done
log "All dependencies found"

# Your ML4W wallpaper folder
WALLPAPER_DIR="$HOME/.mydotfiles/com.ml4w.dotfiles/.config/ml4w/wallpapers"

# Fallback wallpaper
DEFAULT="$WALLPAPER_DIR/5447754-anime-anime-girls-blue-archive-aronablue-archive.jpg"

# Set wallpapers per workspace here
declare -A WALLPAPERS=(
    ["1"]="$WALLPAPER_DIR/teto_1.jpg"
    ["2"]="$WALLPAPER_DIR/rabbit_hole_miku2.jpg"
    ["3"]="$WALLPAPER_DIR/kanaria_1.png"
    ["4"]="$WALLPAPER_DIR/rabbit_hole_miku.png"
    ["5"]="$WALLPAPER_DIR/vbs_miku1.png"
    ["6"]="$WALLPAPER_DIR/n25_miku1.png"
    ["7"]="$WALLPAPER_DIR/DNA_kanade.png"
)

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
        wallpaper="${WALLPAPERS[$workspace]:-$DEFAULT}"

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
