#!/bin/bash

# 1. FIND REPO LOCATION
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- CONFIGURATION ---
PROFILE_URL="https://raw.githubusercontent.com/mylinuxforwork/repo/main/profile.dotinst"
MY_DOTFILES_ROOT="$HOME/.mydotfiles"
TARGET_STORAGE="$MY_DOTFILES_ROOT/com.ml4w.dotfiles"
INSTALLER_DIR="$HOME/ml4w-dotfiles-installer"
DATE=$(date +%Y%m%d_%H%M%S)

echo "📂 Repo detected at: $REPO_ROOT"

# 2. BACKUP EXISTING .MYDOTFILES (If it exists)
if [ -d "$MY_DOTFILES_ROOT" ]; then
    BACKUP_DIR="$MY_DOTFILES_ROOT/.backups/backup_$DATE"
    echo "📦 Backing up current .mydotfiles to $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$TARGET_STORAGE" "$BACKUP_DIR" 2>/dev/null
else
    echo "📁 Creating .mydotfiles directory..."
    mkdir -p "$TARGET_STORAGE"
fi

# 3. SYNC REPO CONTENT TO STORAGE
# Using 'cp -a' to ensure symlinks are copied as links, not as the files they point to.
echo "🔄 Syncing repo files to $TARGET_STORAGE..."
cp -af "$REPO_ROOT/." "$TARGET_STORAGE/"

# 4. APPLY REPO CONFIGS TO ~/.config
# This will overwrite files/links in ~/.config with the ones from your repo
echo "🔗 Applying .config links/files from repo..."
mkdir -p "$HOME/.config"
cp -af "$REPO_ROOT/.config/." "$HOME/.config/"

# 5. OFFICIAL ML4W INSTALLATION/UPDATE
if [ ! -d "$INSTALLER_DIR" ]; then
    echo "📥 Downloading official ML4W installer..."
    git clone https://github.com/mylinuxforwork/ml4w-dotfiles-installer.git "$INSTALLER_DIR"
else
    echo "🔄 Updating the official ML4W installer tool..."
    cd "$INSTALLER_DIR" && git pull 
fi

echo "🛠️ Running official installer..."
cd "$INSTALLER_DIR"
make install
~/.local/bin/ml4w-dotfiles-installer --install "$PROFILE_URL"

# 6. FINAL OVERWRITE (Ensure your customizations win)
# We copy from the Repo directly to the storage. 
# Since ~/.config is symlinked to this storage, the changes reflect immediately.
echo "🎨 Restoring your specific edits over the update..."

# A helper function to make it clean
force_copy() {
    src="$REPO_ROOT/$1"
    dest="$TARGET_STORAGE/$1"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -f "$src" "$dest"
        echo "✅ Restored: $1"
    fi
}

# The list of files you specifically customized:
force_copy ".config/ml4w/scripts/ml4w-toggle-theme"
force_copy ".config/ml4w/scripts/ml4w-wallpaper"
force_copy ".config/hypr/scripts/screenshot"
force_copy ".config/hypr/scripts/colorpicker"
force_copy ".config/hypr/conf/keybindings/default.conf"
force_copy ".config/ml4w/settings/darkmode"

echo "✅ Done! All files updated. Your symlinks and customizations are preserved."