#!/bin/bash

# ==========================================
# 1. PATHS & VARIABLES
# ==========================================
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TARGET_STORAGE="$HOME/.mydotfiles/com.ml4w.dotfiles"
INSTALLER_DIR="$HOME/ml4w-dotfiles-installer"
PROFILE_URL="https://raw.githubusercontent.com/mylinuxforwork/dotfiles/main/hyprland-dotfiles.dotinst"

echo "📂 Repo: $REPO_ROOT"
echo "📂 Storage: $TARGET_STORAGE"

# ==========================================
# 2. INSTALL DEPENDENCIES
# ==========================================
# Only what this setup adds on top of ML4W: the ML4W installer (step 3)
# installs ML4W's own dependencies (Hyprland, Quickshell, awww, matugen,
# cliphist, grimblast, ...). Packages come from the official repositories
# when they are there, otherwise from the AUR through paru or yay (mpvpaper
# is AUR-only on plain Arch).
DEPENDENCIES=(
    rsync                # merging these dotfiles (step 4), dotswitch
    gum                  # dotswitch's theme picker
    cava                 # audio visualizer (media popup)
    zoxide               # 'cd' directory jumping in bash, fish and zsh
    socat                # per-workspace wallpaper daemon (Hyprland events)
    ffmpeg mpvpaper      # video wallpapers (first frames, playback)
    gpu-screen-recorder  # screen recording and instant replay (capture drawer)
    qt6-5compat          # Quickshell effects (album art, wallpaper picker)
    wireplumber libpulse # volume, mic and output switching (wpctl, pactl)
    networkmanager       # Wi-Fi, VPN and network settings (nmcli)
    bluez bluez-utils    # Bluetooth popup and settings (bluetoothctl)
    gnome-keyring        # secrets and SSH keys (custom autostart)
    pciutils             # GPU name in Settings > Hardware (lspci)
    xdg-utils            # opening files and folders (xdg-open)
    zenity               # file picker for VPN imports
    nemo                 # the file manager this setup uses
)

echo -e "\n========================================"
echo "📦 Installing Dependencies"
echo "========================================"
missing=()
for pkg in "${DEPENDENCIES[@]}"; do
    if pacman -Qi "$pkg" &> /dev/null; then
        echo "✅ $pkg is already installed."
    else
        missing+=("$pkg")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    repo_pkgs=(); aur_pkgs=()
    for pkg in "${missing[@]}"; do
        if pacman -Si "$pkg" &> /dev/null; then repo_pkgs+=("$pkg"); else aur_pkgs+=("$pkg"); fi
    done
    if [ ${#repo_pkgs[@]} -gt 0 ]; then
        echo "📦 Installing: ${repo_pkgs[*]}"
        sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}" \
            || echo "⚠️ Warning: Failed to install some of: ${repo_pkgs[*]}. You may need to do it manually."
    fi
    if [ ${#aur_pkgs[@]} -gt 0 ]; then
        aur_helper=""
        for helper in paru yay; do
            command -v "$helper" &> /dev/null && { aur_helper="$helper"; break; }
        done
        if [ -n "$aur_helper" ]; then
            echo "📦 Installing from the AUR with $aur_helper: ${aur_pkgs[*]}"
            "$aur_helper" -S --needed --noconfirm "${aur_pkgs[@]}" \
                || echo "⚠️ Warning: Failed to install some of: ${aur_pkgs[*]}. You may need to do it manually."
        else
            echo "⚠️ Warning: ${aur_pkgs[*]} are not in your repositories and no AUR helper (paru, yay) was found. Install them manually."
        fi
    fi
fi

# Not installed, used when present:
#   pear-desktop                 the music app the media popup's button opens
#   ufw                          Settings > Firewall
#   cups system-config-printer   Settings > Printers
#   nvidia-utils                 NVIDIA GPU stats (nvidia-smi)

# ==========================================
# 3. OFFICIAL ML4W UPDATE / INSTALLATION
# ==========================================
echo -e "\n========================================"
echo "🚀 Installing ML4W Dotfiles..."
echo "========================================"
if [ ! -d "$INSTALLER_DIR" ]; then
    git clone https://github.com/mylinuxforwork/ml4w-dotfiles-installer.git "$INSTALLER_DIR"
else
    echo "🔄 Updating ML4W Installer..."
    cd "$INSTALLER_DIR" && git pull && cd "$REPO_ROOT"
fi

cd "$INSTALLER_DIR"
make install

# This command is synchronous. The script will wait here until ML4W finishes its job.
echo "⏳ Running ML4W Profile Installer..."
~/.local/bin/ml4w-dotfiles-installer --install "$PROFILE_URL"
echo "✅ ML4W installation phase completed."

# ==========================================
# 4. OVERRIDE WITH YOUR CUSTOM DOTFILES
# ==========================================
echo -e "\n========================================"
echo "🔄 Applying Custom Overrides"
echo "========================================"
# Create the config folder just in case
mkdir -p "$TARGET_STORAGE/.config"

# We use rsync instead of cp. Rsync perfectly merges directories without 
# failing on symlink loops or skipping existing files.
# -a: archive (recursive, preserves attributes)
# -L: transforms symlinks into real files (solves the circular loop issue)
echo "📂 Merging REPO_ROOT into TARGET_STORAGE..."
if command -v rsync &> /dev/null; then
    rsync -aL --exclude='.git/' "$REPO_ROOT/.config/" "$TARGET_STORAGE/.config/"
else
    # Fallback just in case rsync fails to install
    cp -rLf "$REPO_ROOT/.config/"* "$TARGET_STORAGE/.config/"
fi

# Ensure custom scripts remain executable after rsync
chmod +x "$TARGET_STORAGE/.config/hypr/conf/custom/workspace-wallpapers.sh" 2>/dev/null || true

# ==========================================
# 4b. QUICKSHELL OVERVIEW (META+Tab)
# ==========================================
# ML4W moved the window overview out of the dotfiles into its own repo. The
# profile install above doesn't fetch it (only ML4W's full setup does), but the
# META+Tab keybind, ml4w-autostart and matugen all expect it here.
# The ML4W dock / power menu / walker are deliberately NOT installed: this
# setup has its own dock and power menu in the Quickshell bar.
echo -e "\n========================================"
echo "🪟 Installing Quickshell Overview (META+Tab)"
echo "========================================"
QSO_DIR="$HOME/.local/share/quickshell-overview"
if [ -d "$QSO_DIR/.git" ]; then
    git -C "$QSO_DIR" pull --ff-only || echo "⚠️ Warning: Could not update quickshell-overview."
elif [ -d "$QSO_DIR" ]; then
    echo "⚠️ $QSO_DIR exists but is not a git repository; leaving it alone."
else
    mkdir -p "$(dirname "$QSO_DIR")"
    git clone https://github.com/Shanu-Kumawat/quickshell-overview "$QSO_DIR" \
        || echo "⚠️ Warning: Failed to clone quickshell-overview. META+Tab won't work until it's installed."
fi

# ==========================================
# 4c. NOTIFICATIONS (Quickshell instead of SwayNC)
# ==========================================
# The Quickshell bar is the notification daemon (BarApp/services/Notifs.qml).
# Only one program can own org.freedesktop.Notifications, and SwayNC ships a
# D-Bus activation file that would start it (and take the name) whenever a
# notification arrives before Quickshell is up. Masking its user unit blocks
# that activation; undo with: systemctl --user unmask swaync.service
echo -e "\n========================================"
echo "🔔 Handing notifications to Quickshell (masking SwayNC)"
echo "========================================"
systemctl --user mask swaync.service || echo "⚠️ Warning: Could not mask swaync.service."
pkill -x swaync 2>/dev/null || true

# ==========================================
# 5. SPECIFIC FILE FAILSAFES
# ==========================================
# The rsync command above technically copies all of this already if they are inside 
# your .config folder, but keeping these ensures your most important files are 100% applied.

echo "📂 Enforcing critical shell and quickshell files..."
# Quickshell
mkdir -p "$TARGET_STORAGE/.config/quickshell"
cp -f "$REPO_ROOT/.config/quickshell/shell.qml" "$TARGET_STORAGE/.config/quickshell/shell.qml" 2>/dev/null

# Shell settings
mkdir -p "$TARGET_STORAGE/.config/bashrc" "$TARGET_STORAGE/.config/zshrc" "$TARGET_STORAGE/.config/fish/conf.d"
cp -f "$REPO_ROOT/.config/bashrc/zoxide" "$TARGET_STORAGE/.config/bashrc/zoxide" 2>/dev/null
cp -f "$REPO_ROOT/.config/fish/conf.d/zoxide.fish" "$TARGET_STORAGE/.config/fish/conf.d/zoxide.fish" 2>/dev/null
cp -f "$REPO_ROOT/.config/zshrc/zoxide" "$TARGET_STORAGE/.config/zshrc/zoxide" 2>/dev/null
cp -f "$REPO_ROOT/.config/fish/conf.d/10-aliases.fish" "$TARGET_STORAGE/.config/fish/conf.d/10-aliases.fish" 2>/dev/null
cp -f "$REPO_ROOT/.config/bashrc/10-aliases" "$TARGET_STORAGE/.config/bashrc/10-aliases" 2>/dev/null
cp -f "$REPO_ROOT/.config/zshrc/25-aliases" "$TARGET_STORAGE/.config/zshrc/25-aliases" 2>/dev/null

# ==========================================
# 6. THEME SWITCHER (dotswitch)
# ==========================================
# Switch between complete themes in ~/.mydotfiles/<id>, keeping your data
# (see dotswitch/README.md). The keep list is only seeded, never overwritten.
echo -e "\n========================================"
echo "🎭 Installing the theme switcher (dotswitch)"
echo "========================================"
install -Dm755 "$REPO_ROOT/dotswitch/dotswitch" "$HOME/.local/bin/dotswitch"
[ -f "$HOME/.config/dotswitch/keep" ] || install -Dm644 "$REPO_ROOT/dotswitch/keep" "$HOME/.config/dotswitch/keep"
# LightCrimson's name and activate/deactivate scripts
rsync -a "$REPO_ROOT/.mydotfiles/com.ml4w.dotfiles/.dotswitch/" "$TARGET_STORAGE/.dotswitch/"
# Other themes kept in this repo: installed next to LightCrimson, not activated
for theme in "$REPO_ROOT"/.mydotfiles/*/; do
    id="$(basename "$theme")"
    [ "$id" = "com.ml4w.dotfiles" ] && continue
    [ -d "$theme/.config" ] || continue
    "$HOME/.local/bin/dotswitch" install "$theme" --id "$id" -y || echo "⚠️ Warning: could not install theme $id."
done

echo "
============================================================
        ✅ ML4W LightCrimson installed
============================================================

🐚 Quickshell shell (replaces Waybar and SwayNC)
   • Popups: media (META+M), calendar (META+C), system (META+N),
     dashboard (META+I), dock (META+A), clipboard (META+SHIFT+V),
     keyboard (META+SHIFT+K), power (META+X)
   • Corner drawers: quick settings (META+ALT+Q), capture (PRINT)
   • Notifications, OSD, Settings app (META+SHIFT+I)

🖼️ Wallpapers
   • Images and videos (mp4, webm, mkv, mov, m4v)
   • Per workspace: META+SHIFT+E
   • Selector: META+CTRL+W   Carousel: META+W

📸 Capture: screenshots, recording (CTRL+PRINT), instant replay,
   text from the screen, colour picker (META+P)

🎮 Game mode (META+ALT+G): no animations or blur, videos stopped

🎭 Themes: run 'dotswitch' (LightCrimson, BA Inspired, HyperBA)

Log out and back in to start everything.
============================================================
"