#!/usr/bin/env bash

# ============================================================================
# Per-workspace wallpaper manager (coordinated with the ML4W pipeline)
# ----------------------------------------------------------------------------
# Applies a different wallpaper per Hyprland workspace, and optionally recolors
# the Quickshell shell (bar/popups) to match each workspace's wallpaper.
#
# Source of truth:  ~/.config/hypr/conf/custom/workspace-wallpapers.json
#                   { "1": "/path/a.jpg", "3": "/path/b.png", ... }
#   • A workspace WITH an entry uses that wallpaper.
#   • A workspace WITHOUT an entry falls back to the active ML4W wallpaper.
#
# Coordination with ML4W:
#   ml4w-wallpaper calls us with `--record-current <path>` after a global
#   change, so the change pins to the workspace you were on (no more "snap
#   back to the old per-workspace wallpaper when you return"). ML4W already
#   ran full matugen for that change, so we only record — we do not recolor.
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

# Per-workspace color following (1 = on, 0 = off). Written by the Settings app.
COLORS_SETTING_FILE="$HOME/.config/ml4w/settings/workspace-wallpaper-colors"
# Dark/light mode, shared with the ML4W pipeline (1 = dark).
DARKMODE_SETTING="$HOME/.config/ml4w/settings/darkmode"
# Lightweight matugen config that regenerates ONLY the Quickshell shell colors
# (no kitty/gtk/hyprland post-hooks). See config-workspace.toml.
MATUGEN_WS_CONFIG="$HOME/.config/matugen/config-workspace.toml"
TRANSITION_SETTING="$HOME/.config/ml4w/settings/wallpaper-transition-effect"

# State: remembers what we last put on each monitor / used for colors so we can
# skip redundant work (this is what keeps workspace switching from being janky).
STATE_DIR="$HOME/.cache/workspace-wallpapers"
mkdir -p "$STATE_DIR"
COLOR_STATE_FILE="$STATE_DIR/last-color-wallpaper"

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
    # "off"/empty -> a safe simple transition.
    [[ -z "$t" || "$t" == "off" || "$t" == "none" ]] && t="simple"
    echo "$t"
}

# --- Colors ----------------------------------------------------------------
colors_enabled() {
    [[ -f "$COLORS_SETTING_FILE" ]] && [[ "$(cat "$COLORS_SETTING_FILE" 2>/dev/null)" == "1" ]]
}

matugen_bin() {
    if [[ -x "$HOME/.cargo/bin/matugen" ]]; then echo "$HOME/.cargo/bin/matugen"
    elif [[ -x "$HOME/.local/bin/matugen" ]]; then echo "$HOME/.local/bin/matugen"
    else echo "matugen"; fi
}

matugen_mode() {
    # Mirror ml4w-wallpaper: ML4W darkmode setting wins, default dark.
    if [[ -f "$DARKMODE_SETTING" ]] && [[ "$(cat "$DARKMODE_SETTING" 2>/dev/null)" == "0" ]]; then
        echo "light"
    else
        echo "dark"
    fi
}

# Lightweight recolor: regenerate ONLY the Quickshell shell colors from $1 and
# reload the shell. No kitty/gtk/hyprland reloads, so it's cheap enough to run
# on a workspace switch. Skips work if the wallpaper hasn't changed.
recolor_shell() {
    local wallpaper="$1"
    colors_enabled || return 0
    [[ -f "$MATUGEN_WS_CONFIG" ]] || { log "Per-workspace colors on but $MATUGEN_WS_CONFIG missing"; return 0; }
    local mg; mg="$(matugen_bin)"
    command -v "$mg" >/dev/null 2>&1 || { log "matugen not found; skipping recolor"; return 0; }

    local last=""
    [[ -f "$COLOR_STATE_FILE" ]] && last="$(cat "$COLOR_STATE_FILE")"
    if [[ "$wallpaper" == "$last" ]]; then
        return 0  # already showing these colors
    fi

    log "Recoloring shell from $wallpaper"
    "$mg" --config "$MATUGEN_WS_CONFIG" image "$wallpaper" \
        --source-color-index 0 -m "$(matugen_mode)" >/dev/null 2>&1

    # Reload the Quickshell shell + the ML4W settings shell.
    qs ipc call theme-manager reload >/dev/null 2>&1 || true
    qs -p "$HOME/.local/share/ml4w-dotfiles-settings/quickshell" ipc call theme-manager reload >/dev/null 2>&1 || true
    echo "$wallpaper" > "$COLOR_STATE_FILE"
}

# --- Apply -----------------------------------------------------------------
# Sets the per-workspace wallpaper on every monitor (skipping monitors that
# already show the right image), then recolors from the focused monitor's
# wallpaper (colors are global, so the focused workspace wins).
set_wallpapers() {
    require jq hyprctl awww || return 1
    start_awww || return 1

    local monitors_json transition focused_wallpaper=""
    monitors_json=$(hyprctl monitors -j 2>/dev/null)
    transition="$(transition_type)"

    while IFS=$'\t' read -r monitor workspace focused; do
        [[ -z "$monitor" ]] && continue
        local wallpaper state_file last=""
        wallpaper="$(get_workspace_wallpaper "$workspace")"
        state_file="$STATE_DIR/monitor-$monitor"
        [[ -f "$state_file" ]] && last="$(cat "$state_file")"

        if [[ "$focused" == "true" ]]; then
            focused_wallpaper="$wallpaper"
        fi

        if [[ "$wallpaper" == "$last" ]]; then
            continue  # already correct on this monitor — no flicker
        fi

        if [[ -f "$wallpaper" ]]; then
            log "Setting $monitor (workspace $workspace) -> $wallpaper"
            awww img "$wallpaper" -o "$monitor" \
                --transition-type "$transition" --transition-duration 0.4
            echo "$wallpaper" > "$state_file"
        else
            log "Wallpaper not found: $wallpaper"
        fi
    done < <(echo "$monitors_json" | jq -r '.[] | "\(.name)\t\(.activeWorkspace.name)\t\(.focused)"')

    [[ -n "$focused_wallpaper" ]] && recolor_shell "$focused_wallpaper"
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
        # ML4W hook: pin the just-set global wallpaper to the focused workspace,
        # WITHOUT re-applying (ML4W already set image + colors). We also sync the
        # color state so we don't needlessly recolor when staying on this ws.
        if [[ -z "$2" ]]; then log "--record-current needs <path>"; exit 1; fi
        require jq hyprctl || exit 0
        ws="$(active_workspace_of_focused_monitor)"
        [[ -z "$ws" ]] && exit 0
        config_set "$ws" "$2"
        # Mark this monitor/colors as already showing $2 so the daemon won't
        # re-apply or re-color on the next event.
        focused_mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
        [[ -n "$focused_mon" ]] && echo "$2" > "$STATE_DIR/monitor-$focused_mon"
        echo "$2" > "$COLOR_STATE_FILE"
        log "Recorded global change: workspace $ws -> $2"
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

if ! require jq hyprctl awww socat; then
    log "Daemon cannot start: missing dependencies (need jq, hyprctl, awww, socat)."
    exit 1
fi

# Forget stale monitor state on a fresh start so the first apply always paints.
rm -f "$STATE_DIR"/monitor-*
set_wallpapers

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
log "Listening on Hyprland socket2: $SOCKET"

while true; do
    socat -u UNIX-CONNECT:"$SOCKET" - | while read -r event; do
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
