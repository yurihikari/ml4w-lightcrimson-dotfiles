#!/usr/bin/env bash
# Points qt6ct (and qt5ct, when installed) at matugen's Qt palette and
# matches the Breeze icons to the mode. Runs after matugen has written
# ~/.config/qt6ct/colors/matugen.conf.
#
# Qt apps read the palette when they start: running ones keep their colours
# until they are restarted.

scheme="$HOME/.config/qt6ct/colors/matugen.conf"
[ -f "$scheme" ] || exit 0
mode=$(sed -n 's/^mode=//p' "$scheme" | head -n1)

# Sets key=value under [Appearance], only when it differs.
set_key() {
    local file="$1" key="$2" value="$3"
    if grep -q "^$key=" "$file"; then
        grep -qx "$key=$value" "$file" || sed -i "s|^$key=.*|$key=$value|" "$file"
    elif grep -q '^\[Appearance\]' "$file"; then
        sed -i "/^\[Appearance\]/a $key=$value" "$file"
    else
        printf '[Appearance]\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

for tool in qt6ct qt5ct; do
    conf="$HOME/.config/$tool/$tool.conf"
    [ "$tool" = qt5ct ] && ! command -v qt5ct >/dev/null && [ ! -f "$conf" ] && continue
    mkdir -p "$HOME/.config/$tool/colors"
    [ -f "$conf" ] || : > "$conf"
    target="$HOME/.config/$tool/colors/matugen.conf"
    [ "$target" = "$scheme" ] || cp -f "$scheme" "$target"

    set_key "$conf" color_scheme_path "$target"
    set_key "$conf" custom_palette true
    # Breeze's icons come in a light and a dark set; other icon themes are
    # left as they are.
    icons=$(sed -n 's/^icon_theme=//p' "$conf" | head -n1)
    if [ -z "$icons" ] || [[ "$icons" == breeze || "$icons" == breeze-dark ]]; then
        set_key "$conf" icon_theme "$([ "$mode" = dark ] && echo breeze-dark || echo breeze)"
    fi
done
