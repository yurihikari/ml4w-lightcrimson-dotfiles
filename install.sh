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
# 2. INSTALL DEPENDENCIES (cava, zoxide, rsync)
# ==========================================
echo -e "\n========================================"
echo "📦 Installing Dependencies"
echo "========================================"
# Loop through required packages to install them cleanly
for pkg in cava zoxide rsync socat; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "📦 $pkg not found. Installing..."
        # Added --noconfirm so the script doesn't pause waiting for "Y"
        sudo pacman -Sy --noconfirm "$pkg" || echo "⚠️ Warning: Failed to install $pkg. You may need to do it manually."
    else
        echo "✅ $pkg is already installed."
    fi
done

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

echo "
============================================================
        ✅ CUSTOM DOTFILES CHANGES SUMMARY
============================================================

🐚 Custom Quickshell Bar (replaces Waybar)
   • Top bar: workspaces w/ app icons, system tray, media pill,
     mic/brightness/volume ring controls, kb layout, notifications,
     clock, network/bluetooth/battery pill, instant OSD + screen frame
   • Multi-monitor aware — popups open on the monitor under your mouse
   • Popups (keybinding or click):
     → Media (META+M): MPRIS player, Cava visualizer, sink switcher
     → Calendar (META+C): calendar + weather + world clock
     → System/Network (META+N): Wi-Fi, Bluetooth, network
     → Dashboard (META+I): system info, mounted disks & drives
     → Dock (META+A): app launcher w/ keyboard nav, notes, todo, screenshots
     → Clipboard (META+SHIFT+V): clipboard history (cliphist)
     → Keyboard Layout (META+SHIFT+K): switch layout/variant
     → Power (META+X): power menu with keyboard selection
     → Radial Menu (META+R) + Display Manager (META+ALT+M)

🎨 ML4W Theme & Wallpaper Customizations
   • ml4w-toggle-theme: Added 'Save' theme mode variable
     → Theme stays consistent after waybar/matugen changes
   • darkmode: Custom darkmode state file preserved
   • ml4w-wallpaper: Added darkmode variable
     → Matugen won't override darkmode unless desired

🖼️ Per-Workspace Wallpapers
   • workspace-wallpapers.sh: Different wallpaper per Hyprland workspace
     → Autostarted via ~/.config/hypr/conf/custom/autostart.lua
   • WorkspaceWallpaperAPP: Separate Quickshell app to select wallpapers per workspace
     → Open with SUPER + SHIFT + E
     → Saves assignments to ~/.config/hypr/conf/custom/workspace-wallpapers.json

📸 Screenshot & Colorpicker Enhancements
   • screenshot.sh: Screenshots now copied to clipboard
     + saved to file (dual functionality)
   • colorpicker.sh: Added hyprpicker integration
     → Press META+P to pick colors

⌨️ Custom Keybindings
   • META+D → Application launcher
   • META+P → Colorpicker (hyprpicker)
   • META+R → Radial menu
   • META+ALT+M → Display manager
   • Quickshell popups: META+M (media), META+C (calendar),
     META+N (network/system), META+I (dashboard), META+A (dock),
     META+SHIFT+V (clipboard), META+SHIFT+K (keyboard), META+X (power)
   • Plus other custom overrides in default.conf

🖥️ Fastfetch Customization
   • Custom logo image added (you can replace it with your own)
   • GPU information display enabled

🐚 Shell Configuration Fixes
   • zsh plugins: Fixed path issue for AUR vs git clone
     → 00-init & 20-customization updated
   • zoxide: Installed and initialized for bash/fish/zsh
     → 'cd' alias with directory jumping available
   • Aliases: Added for bash, fish, and zsh

============================================================
        All changes successfully saved!
============================================================
"