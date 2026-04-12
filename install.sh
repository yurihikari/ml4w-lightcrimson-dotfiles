#!/bin/bash

# 1. FIND REPO LOCATION
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# --- CONFIGURATION ---
PROFILE_URL="https://raw.githubusercontent.com/mylinuxforwork/dotfiles/main/hyprland-dotfiles.dotinst"
MY_DOTFILES_ROOT="$HOME/.mydotfiles"
TARGET_STORAGE="$MY_DOTFILES_ROOT/com.ml4w.dotfiles"
INSTALLER_DIR="$HOME/ml4w-dotfiles-installer"
DATE=$(date +%Y%m%d_%H%M%S)

echo "📂 Repo detected at: $REPO_ROOT"

# 2. BACKUP TARGET_STORAGE (Not the whole .config)
if [ -d "$TARGET_STORAGE" ]; then
    BACKUP_DIR="$MY_DOTFILES_ROOT/.backups/backup_$DATE"
    echo "📦 Backing up current storage to $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp -rp "$TARGET_STORAGE" "$BACKUP_DIR" 2>/dev/null
else
    echo "📁 Creating storage directory at $TARGET_STORAGE..."
    mkdir -p "$TARGET_STORAGE"
fi

# 3. SYNC REPO TO STORAGE
# We use rsync here because it is much safer than 'cp' for folder-to-folder syncing.
# It will NOT copy the .git folder or create recursive loops.
echo "🔄 Updating storage files from repo..."
rsync -av --exclude='.git' --exclude='.backups' "$REPO_ROOT/" "$TARGET_STORAGE/"

# 4. OFFICIAL ML4W INSTALLATION
if [ ! -d "$INSTALLER_DIR" ]; then
    echo "📥 Downloading official ML4W installer..."
    git clone https://github.com/mylinuxforwork/ml4w-dotfiles-installer.git "$INSTALLER_DIR"
else
    echo "🔄 Updating official ML4W installer..."
    cd "$INSTALLER_DIR" && git pull
fi

echo "🛠️ Running official ML4W update..."
cd "$INSTALLER_DIR"
make install
~/.local/bin/ml4w-dotfiles-installer --install "$PROFILE_URL"

# 5. RESTORE CUSTOMIZATIONS INTO STORAGE
# Since your ~/.config files are symlinks to this storage, 
# overwriting these files here updates your system automatically.
echo "🎨 Overwriting storage with your custom edits..."

force_copy() {
    src="$REPO_ROOT/$1"
    dest="$TARGET_STORAGE/$1"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -f "$src" "$dest"
        echo "✅ Updated in storage: $1"
    fi
}

# The specific files you want to keep customized
force_copy ".config/ml4w/scripts/ml4w-toggle-theme"
force_copy ".config/ml4w/scripts/ml4w-wallpaper"
force_copy ".config/hypr/scripts/screenshot"
force_copy ".config/hypr/scripts/colorpicker"
force_copy ".config/hypr/conf/keybindings/default.conf"
force_copy ".config/ml4w/settings/darkmode"

echo "✅ All done. Only ~/.mydotfiles was modified by this script."