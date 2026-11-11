#!/usr/bin/env bash
# Applies matugen's colours and light / dark mode to GTK apps. Runs after
# matugen has written ~/.config/gtk-4.0/colors.css.
#
# - GTK 4 (libadwaita) apps read the colours straight from gtk-4.0/colors.css.
# - GTK 3 apps read gtk-3.0/colors.css through the adw-gtk3 theme, switched
#   here to its light or dark variant. A theme picked by hand (anything not
#   adw-gtk3) is left alone.
# - The colour scheme preference (prefer-light / prefer-dark) follows the
#   mode, for libadwaita, portals, Electron apps and browsers.

colors="$HOME/.config/gtk-4.0/colors.css"
mode=$(grep -oE 'mode: (dark|light)' "$colors" 2>/dev/null | head -n1 | cut -d' ' -f2)
[ -n "$mode" ] || exit 0

if [ "$mode" = "dark" ]; then
    scheme="prefer-dark"; other="prefer-light"; prefer3=1; prefer4=true; variant="adw-gtk3-dark"
else
    scheme="prefer-light"; other="prefer-dark"; prefer3=0; prefer4=false; variant="adw-gtk3"
fi

# Sets key=value under [Settings], only when it differs (the GTK settings
# listener watches these files).
set_key() {
    local file="$1" key="$2" value="$3"
    [ -f "$file" ] || return 0
    if grep -q "^$key=" "$file"; then
        grep -qx "$key=$value" "$file" || sed -i "s|^$key=.*|$key=$value|" "$file"
    else
        sed -i "/^\[Settings\]/a $key=$value" "$file"
    fi
}

gtk3="$HOME/.config/gtk-3.0/settings.ini"
gtk4="$HOME/.config/gtk-4.0/settings.ini"

theme=$(grep -E '^gtk-theme-name=' "$gtk3" 2>/dev/null | cut -d= -f2-)
installed=""
for dir in "$HOME/.local/share/themes" "$HOME/.themes" /usr/share/themes; do
    [ -d "$dir/adw-gtk3" ] && installed=1 && break
done
if [ -n "$installed" ] && [[ "$theme" == adw-gtk3* ]]; then
    theme="$variant"
    set_key "$gtk3" gtk-theme-name "$theme"
    set_key "$gtk4" gtk-theme-name "$theme"
    gsettings set org.gnome.desktop.interface gtk-theme "$theme"
    # X11 apps (XWayland) read it from xsettingsd, when that is in use
    xs="$HOME/.config/xsettingsd/xsettingsd.conf"
    if [ -f "$xs" ]; then
        sed -i "s|^Net/ThemeName .*|Net/ThemeName \"$theme\"|" "$xs"
        pkill -HUP -x xsettingsd 2>/dev/null
    fi
fi

set_key "$gtk3" gtk-application-prefer-dark-theme "$prefer3"
set_key "$gtk4" gtk-application-prefer-dark-theme "$prefer4"

# Through the other value and back: running GTK apps only reload their CSS
# (the new colours) when the preference changes.
gsettings set org.gnome.desktop.interface color-scheme "$other"
gsettings set org.gnome.desktop.interface color-scheme "$scheme"
