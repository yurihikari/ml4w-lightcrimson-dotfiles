#!/usr/bin/env bash

# This script monitors changes to the GTK settings.ini file and switches the
# desktop between light and dark when 'gtk-application-prefer-dark-theme' is
# changed from outside ML4W (a GTK settings tool).

# Path to the GTK settings file
SETTINGS_FILE="$HOME/.config/gtk-3.0/settings.ini"
SETTINGS_DIR="$HOME/.config/gtk-3.0"
SETTINGS_BASENAME=$(basename "$SETTINGS_FILE")

# Ensure inotify-tools is installed
if ! command -v inotifywait &> /dev/null
then
    echo "Error: inotifywait is not installed."
    echo "Please install inotify-tools (e.g., sudo apt install inotify-tools on Debian/Ubuntu)"
    exit 1
fi

echo "Monitoring $SETTINGS_FILE for changes..."
echo "Press Ctrl+C to stop."

# Applies a light / dark preference set in a GTK settings tool (nwg-look...):
# when it disagrees with ML4W's mode, switch the whole desktop with
# ml4w-toggle-theme (matugen, Quickshell, GTK and Qt). The toggle and
# matugen's GTK hook write this file too, but always in agreement with the
# mode, so their writes are ignored here (no loop, no second matugen run).
apply_theme() {
    [ -f "$SETTINGS_FILE" ] || return 0
    local pref want current
    sleep 0.5   # let a writer finish (the toggle writes several files)
    pref=$(grep -E '^gtk-application-prefer-dark-theme=' "$SETTINGS_FILE" | awk -F'=' '{print $2}')
    case "$pref" in
        1|true) want=1 ;;
        0|false) want=0 ;;
        *) return 0 ;;
    esac
    current=$(cat "$HOME/.config/ml4w/settings/darkmode" 2>/dev/null)
    [ "$current" = "$want" ] && return 0
    echo "Preference changed to $([ "$want" = 1 ] && echo dark || echo light): switching the desktop..."
    "$HOME/.config/ml4w/scripts/ml4w-toggle-theme" "$([ "$want" = 1 ] && echo dark || echo light)"
}

# Loop indefinitely, reading output from inotifywait
inotifywait -m -q -e close_write,moved_to "$SETTINGS_DIR" | while read -r dir events filename; do
    if [[ "$filename" == "$SETTINGS_BASENAME" ]]; then
        echo "Change detected in $SETTINGS_FILE. Re-applying theme..."
        apply_theme
    fi
done