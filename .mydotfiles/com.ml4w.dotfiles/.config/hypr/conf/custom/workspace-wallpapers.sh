#!/usr/bin/env bash

# ============================================================================
# Per-workspace wallpaper manager (coordinated with the ML4W pipeline)
# ----------------------------------------------------------------------------
# Applies a different wallpaper per Hyprland workspace. It ONLY changes the
# wallpaper image — it never touches the colour theme. To recolour the desktop,
# use the normal ML4W wallpaper flow (which runs matugen); that change also
# pins itself to the workspace you're on (see --record-current below).
#
# Source of truth:  ~/.config/hypr/conf/custom/workspace-wallpapers.json
#                   { "1": "/path/a.jpg", "3": "/path/b.png", ... }
#   • A workspace WITH an entry uses that wallpaper.
#   • A workspace WITHOUT an entry falls back to the active ML4W wallpaper.
#
# Modes:
#   (no args)                  Run as the daemon: apply now, then listen for
#                              workspace/monitor events and re-apply.
#   --apply-now                One-shot: apply wallpapers for the current
#                              workspaces and exit. (used by the pickers)
#   --assign <ws> <path>       Assign <path> to workspace <ws>, then apply if
#                              that workspace is currently active.
#   --clear <ws>               Remove workspace <ws>'s assignment (falls back
#                              to the ML4W wallpaper), then apply if active.
#   --record-current <path>    Pin <path> as the *current* workspace's
#                              assignment without re-applying (ML4W hook).
# ============================================================================

# --- Logging --------------------------------------------------------------
LOG_FILE="$HOME/.cache/workspace-wallpapers.log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# --- Paths / settings ------------------------------------------------------
CONFIG_FILE="$HOME/.config/hypr/conf/custom/workspace-wallpapers.json"
ACTIVE_WALLPAPER_FILE="$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper"
DEFAULT_WALLPAPER="$HOME/.config/ml4w/wallpapers/default.jpg"
TRANSITION_SETTING="$HOME/.config/ml4w/settings/wallpaper-transition-effect"

# Video wallpapers: a video path is shown as an awww poster + mpvpaper on top.
VIDEO_LIB="$HOME/.config/hypr/conf/custom/video-wallpaper.sh"
if [[ -f "$VIDEO_LIB" ]]; then
    source "$VIDEO_LIB"
else
    vw_is_video() { return 1; }; vw_stop() { :; }; vw_stop_all() { :; }
fi
TRANSITION_DURATION=0.4

# State: remembers what we last put on each monitor so we can skip redundant
# work (this is what keeps workspace switching from flickering).
STATE_DIR="$HOME/.cache/workspace-wallpapers"
mkdir -p "$STATE_DIR"

# --- Dependency checks -----------------------------------------------------
# jq/hyprctl/awww are always needed. socat is only needed by the daemon's event
# loop, so the one-shot modes below don't require it (this was the bug that made
# the picker do nothing when socat was missing).
require() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "Missing dependency: $cmd"
            missing=1
        fi
    done
    return $missing
}

# --- Config helpers --------------------------------------------------------
ensure_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo '{}' > "$CONFIG_FILE"
        log "Created empty config file: $CONFIG_FILE"
    fi
}

# Write JSON atomically with jq.
config_set() {  # $1 = workspace key, $2 = path
    ensure_config
    local tmp
    tmp="$(mktemp)"
    if jq --arg ws "$1" --arg path "$2" '.[$ws] = $path' "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CONFIG_FILE"
        log "Assigned workspace $1 -> $2"
    else
        rm -f "$tmp"
        log "ERROR: failed to write config for workspace $1"
    fi
}

config_unset() {  # $1 = workspace key
    ensure_config
    local tmp
    tmp="$(mktemp)"
    if jq --arg ws "$1" 'del(.[$ws])' "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CONFIG_FILE"
        log "Cleared workspace $1"
    else
        rm -f "$tmp"
        log "ERROR: failed to clear config for workspace $1"
    fi
}

fallback_wallpaper() {
    if [[ -f "$ACTIVE_WALLPAPER_FILE" ]]; then
        cat "$ACTIVE_WALLPAPER_FILE"
    else
        echo "$DEFAULT_WALLPAPER"
    fi
}

# Resolve the wallpaper path for a workspace, expanding $HOME/~ and falling back
# to the active ML4W wallpaper when unassigned or the file is missing.
get_workspace_wallpaper() {
    local workspace="$1"
    local path=""
    ensure_config
    path=$(jq -r --arg ws "$workspace" '.[$ws] // empty' "$CONFIG_FILE" 2>/dev/null)
    path="${path//\$HOME/$HOME}"
    path="${path//\~/$HOME}"
    if [[ -z "$path" || ! -f "$path" ]]; then
        path=$(fallback_wallpaper)
    fi
    echo "$path"
}

active_workspace_of_focused_monitor() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .activeWorkspace.name' | head -n1
}

# --- awww ------------------------------------------------------------------
start_awww() {
    if awww query >/dev/null 2>&1; then
        return 0
    fi
    log "Starting awww-daemon..."
    # A new awww surface would cover running videos; stop them so they are
    # restarted on top, and forget monitor state so everything is repainted.
    vw_stop_all
    rm -f "$STATE_DIR"/monitor-*
    awww-daemon >/dev/null 2>&1 &
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        awww query >/dev/null 2>&1 && { log "awww-daemon started"; return 0; }
        sleep 0.2
    done
    log "ERROR: awww-daemon failed to start"
    return 1
}

transition_type() {
    local t="fade"
    [[ -f "$TRANSITION_SETTING" ]] && t="$(cat "$TRANSITION_SETTING")"
    [[ -z "$t" || "$t" == "off" || "$t" == "none" ]] && t="simple"
    echo "$t"
}

# --- Apply -----------------------------------------------------------------
# Sets the per-workspace wallpaper on every monitor, skipping monitors that
# already show the right image (so switching doesn't flicker).
set_wallpapers() {
    require jq hyprctl awww || return 1
    start_awww || return 1

    local monitors_json transition
    monitors_json=$(hyprctl monitors -j 2>/dev/null)
    transition="$(transition_type)"

    while IFS=$'\t' read -r monitor workspace; do
        [[ -z "$monitor" ]] && continue
        local wallpaper state_file last=""
        wallpaper="$(get_workspace_wallpaper "$workspace")"
        state_file="$STATE_DIR/monitor-$monitor"
        [[ -f "$state_file" ]] && last="$(cat "$state_file")"

        if [[ ! -f "$wallpaper" ]]; then
            log "Wallpaper not found: $wallpaper"
            continue
        fi

        if vw_is_video "$wallpaper"; then
            # Poster underneath via awww, then the video on top once the
            # transition has finished (the poster is the first frame, so the
            # hand-over is seamless).
            local delay="${VW_START_DELAY:-0}"
            if [[ "$wallpaper" != "$last" ]]; then
                local poster
                if ! poster="$(vw_poster "$wallpaper")"; then
                    log "Could not extract a poster frame from: $wallpaper"
                    continue
                fi
                [[ -n "$(vw_current "$monitor")" ]] && vw_stop "$monitor"
                log "Setting $monitor (workspace $workspace) -> $wallpaper (video)"
                awww img "$poster" -o "$monitor" \
                    --transition-type "$transition" --transition-duration "$TRANSITION_DURATION"
                echo "$wallpaper" > "$state_file"
                delay="$TRANSITION_DURATION"
            fi
            vw_play_after "$delay" "$monitor" "$wallpaper"
            continue
        fi

        # Still image: drop any video on this monitor (reveals awww underneath).
        vw_stop "$monitor"

        if [[ "$wallpaper" == "$last" ]]; then
            continue  # already correct on this monitor — no flicker
        fi

        log "Setting $monitor (workspace $workspace) -> $wallpaper"
        awww img "$wallpaper" -o "$monitor" \
            --transition-type "$transition" --transition-duration "$TRANSITION_DURATION"
        echo "$wallpaper" > "$state_file"

    done < <(echo "$monitors_json" | jq -r '.[] | "\(.name)\t\(.activeWorkspace.name)"')
}

# ============================================================================
# Entry points
# ============================================================================
case "$1" in
    --assign)
        # $2 = workspace, $3 = path
        if [[ -z "$2" || -z "$3" ]]; then log "--assign needs <ws> <path>"; exit 1; fi
        config_set "$2" "$3"
        # Apply immediately only if that workspace is currently focused.
        if [[ "$2" == "$(active_workspace_of_focused_monitor)" ]]; then
            set_wallpapers
        fi
        exit 0
        ;;
    --clear)
        if [[ -z "$2" ]]; then log "--clear needs <ws>"; exit 1; fi
        config_unset "$2"
        if [[ "$2" == "$(active_workspace_of_focused_monitor)" ]]; then
            # Force re-apply (the fallback wallpaper differs from the cleared one).
            rm -f "$STATE_DIR"/monitor-*
            set_wallpapers
        fi
        exit 0
        ;;
    --record-current)
        # ML4W hook: ML4W just painted the new wallpaper on EVERY monitor (its
        # `awww img` call has no -o), which clobbers the per-workspace wallpapers
        # on any monitor not showing the focused workspace. So we:
        #   1. Pin the new wallpaper to the focused workspace, so returning to it
        #      doesn't snap back to a stale per-workspace assignment.
        #   2. Mark the focused monitor as already-correct (no flicker), then
        #      invalidate every OTHER monitor's now-stale state and re-apply, so
        #      they snap back to their per-workspace wallpapers immediately.
        #
        # Without step 2, other monitors kept the global image until a daemon
        # restart: their stale state still matched the per-workspace wallpaper, so
        # the daemon's anti-flicker check skipped the repaint on workspace events.
        if [[ -z "$2" ]]; then log "--record-current needs <path>"; exit 1; fi
        require jq hyprctl || exit 0
        ws="$(active_workspace_of_focused_monitor)"
        [[ -z "$ws" ]] && exit 0
        config_set "$ws" "$2"
        focused_mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
        # Focused monitor is already correct — record it so it isn't repainted.
        [[ -n "$focused_mon" ]] && echo "$2" > "$STATE_DIR/monitor-$focused_mon"
        # Drop every other monitor's stale state so set_wallpapers repaints them.
        for sf in "$STATE_DIR"/monitor-*; do
            [[ -e "$sf" ]] || continue
            [[ -n "$focused_mon" && "$sf" == "$STATE_DIR/monitor-$focused_mon" ]] && continue
            rm -f "$sf"
        done
        log "Recorded global change: workspace $ws -> $2; re-applying other monitors"
        # ML4W already painted the poster with its own transition; give it a
        # moment before a video covers the focused monitor.
        VW_START_DELAY=1 set_wallpapers
        exit 0
        ;;
    --apply-now)
        log "One-shot apply requested"
        set_wallpapers
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# Daemon mode (default): needs socat for the Hyprland event socket.
# ---------------------------------------------------------------------------
log "--- workspace-wallpapers.sh daemon starting ---"

LOCK_FILE="/tmp/workspace-wallpapers.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another daemon instance is already running. Exiting."
    exit 0
fi

# Keep the log from growing forever (it gets a line per workspace switch).
if [[ -f "$LOG_FILE" ]] && (( $(stat -c %s "$LOG_FILE") > 1048576 )); then
    tail -n 2000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    log "Log trimmed to its last 2000 lines"
fi

if ! require jq hyprctl awww socat; then
    log "Daemon cannot start: missing dependencies (need jq, hyprctl, awww, socat)."
    exit 1
fi

# Forget stale monitor state on a fresh start so the first apply always paints.
rm -f "$STATE_DIR"/monitor-*
vw_stop_all
set_wallpapers

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
log "Listening on Hyprland socket2: $SOCKET"

while true; do
    # 9>&-: socat must not inherit the lock, or an orphaned socat left by a
    # killed daemon keeps it held and the next daemon refuses to start.
    socat -u UNIX-CONNECT:"$SOCKET" - 9>&- | while read -r event; do
        case "$event" in
            workspace\>\>*|focusedmon\>\>*|moveworkspace\>\>*)
                log "Event: $event"
                set_wallpapers
                ;;
        esac
    done
    log "socat exited (status: ${PIPESTATUS[*]}), restarting in 2s..."
    sleep 2
done
