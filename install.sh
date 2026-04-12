#!/bin/bash

# 1. PATHS
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TARGET_STORAGE="$HOME/.mydotfiles/com.ml4w.dotfiles"
INSTALLER_DIR="$HOME/ml4w-dotfiles-installer"
PROFILE_URL="https://raw.githubusercontent.com/mylinuxforwork/dotfiles/main/hyprland-dotfiles.dotinst"

echo "📂 Repo: $REPO_ROOT"
echo "📂 Storage: $TARGET_STORAGE"

# 2. CREATE FOLDERS (No links)
mkdir -p "$TARGET_STORAGE/.config/ml4w/scripts"
mkdir -p "$TARGET_STORAGE/.config/ml4w/settings"
mkdir -p "$TARGET_STORAGE/.config/hypr/scripts"
mkdir -p "$TARGET_STORAGE/.config/hypr/conf/keybindings"

# 3. SELECTIVE COPY (Avoiding circular symlinks)
# We ONLY copy the .config folder contents. 
# We do NOT copy the root files (.git, .mydotfiles link, etc.)
echo "🔄 Updating .config in storage..."
if [ -d "$REPO_ROOT/.config" ]; then
    # -L follows the links in your repo and turns them into REAL files in storage
    # This kills the circular loop "Too many levels" error.
    cp -rL "$REPO_ROOT/.config/"* "$TARGET_STORAGE/.config/"
fi

# 4. OFFICIAL ML4W UPDATE
if [ ! -d "$INSTALLER_DIR" ]; then
    git clone https://github.com/mylinuxforwork/ml4w-dotfiles-installer.git "$INSTALLER_DIR"
else
    cd "$INSTALLER_DIR" && git pull && cd "$REPO_ROOT"
fi
cd "$INSTALLER_DIR"
make install
~/.local/bin/ml4w-dotfiles-installer --install "$PROFILE_URL"

# 5. RESTORE YOUR CUSTOMIZATIONS INTO STORAGE
echo "🎨 Restoring custom edits..."
# This specifically puts your edited files into the storage folder
# It uses the Repo as the source.
cp -f "$REPO_ROOT/.config/ml4w/scripts/ml4w-toggle-theme" "$TARGET_STORAGE/.config/ml4w/scripts/ml4w-toggle-theme"
cp -f "$REPO_ROOT/.config/ml4w/scripts/ml4w-wallpaper" "$TARGET_STORAGE/.config/ml4w/scripts/ml4w-wallpaper"
cp -f "$REPO_ROOT/.config/hypr/scripts/screenshot" "$TARGET_STORAGE/.config/hypr/scripts/screenshot"
cp -f "$REPO_ROOT/.config/hypr/scripts/colorpicker" "$TARGET_STORAGE/.config/hypr/scripts/colorpicker"
cp -f "$REPO_ROOT/.config/hypr/conf/keybindings/default.conf" "$TARGET_STORAGE/.config/hypr/conf/keybindings/default.conf"
cp -f "$REPO_ROOT/.config/ml4w/settings/darkmode" "$TARGET_STORAGE/.config/ml4w/settings/darkmode"

echo "✅ Done. ~/.mydotfiles updated."