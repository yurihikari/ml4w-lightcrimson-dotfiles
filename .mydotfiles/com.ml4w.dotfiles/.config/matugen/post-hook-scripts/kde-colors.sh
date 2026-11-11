#!/usr/bin/env bash
# Puts matugen's KDE colour groups into ~/.config/kdeglobals, which KDE apps
# (Dolphin, Kate, Ark...) read next to the Qt palette. Only the colour groups
# ([Colors:*], [ColorEffects:*], [WM]) are replaced; the rest of the file
# (default apps, file dialog settings...) is kept.

src="$HOME/.config/ml4w/colors/kdeglobals"
dst="$HOME/.config/kdeglobals"
[ -f "$src" ] || exit 0
touch "$dst"

tmp=$(mktemp)
awk '
    /^\[/ { skip = ($0 ~ /^\[(Colors:|ColorEffects:|WM\])/) }
    !skip
' "$dst" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$tmp"
{
    cat "$tmp"
    echo
    grep -v '^#' "$src"
} > "$dst"
rm -f "$tmp"

# Apps that apply a colour scheme themselves (Dolphin, Kate...) load the one
# named in kdeglobals from its .colors file, Breeze when none is named: give
# them these colours as the "Matugen" scheme. (kwriteconfig6 comes with
# KDE's frameworks, so it is there whenever a KDE app is.)
schemes="$HOME/.local/share/color-schemes"
mkdir -p "$schemes"
{
    printf '[General]\nColorScheme=Matugen\nName=Matugen\n\n'
    grep -v '^#' "$src"
} > "$schemes/Matugen.colors"
if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kdeglobals --group General --key ColorScheme Matugen
    kwriteconfig6 --file kdeglobals --group General --key ColorSchemeHash --delete
    # Outside Plasma those apps fall back to Breeze unless their own settings
    # name a scheme (Settings > Window Color Scheme): name this one, in the
    # installed ones where none was picked by hand.
    for app in dolphin kate kwrite ark gwenview okular konsole kcalc filelight \
               spectacle elisa kdeconnect-app kfind kcharselect partitionmanager; do
        command -v "$app" >/dev/null || continue
        [ -n "$(kreadconfig6 --file "${app}rc" --group UiSettings --key ColorScheme)" ] && continue
        kwriteconfig6 --file "${app}rc" --group UiSettings --key ColorScheme Matugen
    done
fi

# Running KDE apps reload their colours on this signal
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null
