#!/bin/bash

# 1. PATHS
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
TARGET_STORAGE="$HOME/.mydotfiles/com.ml4w.dotfiles"
INSTALLER_DIR="$HOME/ml4w-dotfiles-installer"
PROFILE_URL="https://raw.githubusercontent.com/mylinuxforwork/dotfiles/main/hyprland-dotfiles.dotinst"
# Welcome message for the installation process

echo "📂 Repo: $REPO_ROOT"
echo "📂 Storage: $TARGET_STORAGE"

# 2. CREATE FOLDERS (No links)
echo "📂 Creating folders in storage..."
mkdir -p "$TARGET_STORAGE/.config/ml4w/scripts"
mkdir -p "$TARGET_STORAGE/.config/ml4w/settings"
mkdir -p "$TARGET_STORAGE/.config/hypr/scripts"
mkdir -p "$TARGET_STORAGE/.config/hypr/conf/keybindings"
echo "✅ Folders created in storage."

# 3. SELECTIVE COPY (Avoiding circular symlinks)
# We ONLY copy the .config folder contents. 
# We do NOT copy the root files (.git, .mydotfiles link, etc.)
echo "🔄 Updating .config in storage..."
if [ -d "$REPO_ROOT/.config" ]; then
    # -L follows the links in your repo and turns them into REAL files in storage
    # This kills the circular loop "Too many levels" error.
    cp -rL "$REPO_ROOT/.config/"* "$TARGET_STORAGE/.config/"
fi
echo "✅ .config updated in storage."

# 4. OFFICIAL ML4W UPDATE
echo "🚀 Installing ML4W Dotfiles and Hyprland Settings App..."
if [ ! -d "$INSTALLER_DIR" ]; then
    git clone https://github.com/mylinuxforwork/ml4w-dotfiles-installer.git "$INSTALLER_DIR"
else
    cd "$INSTALLER_DIR" && git pull && cd "$REPO_ROOT"
fi
cd "$INSTALLER_DIR"
make install
~/.local/bin/ml4w-dotfiles-installer --install "$PROFILE_URL"
# SELECTIVE COPY BACK TO STORAGE (to preserve your custom edits)
echo "🔄 Updating .config in storage after ml4w installation..."
if [ -d "$REPO_ROOT/.config" ]; then
    cp -rL "$REPO_ROOT/.config/"* "$TARGET_STORAGE/.config/"
fi
echo "✅ .config updated in storage."
echo "✅ ML4W Dotfiles installed."

# 5. RESTORE YOUR CUSTOMIZATIONS INTO STORAGE
# Quickshell settings
cp -f "$REPO_ROOT/.config/quickshell/shell.qml" "$TARGET_STORAGE/.config/quickshell/shell.qml"

# Install cava
echo "📂 Setting up cava..."
if ! command -v cava &> /dev/null; then
    echo "📦 cava not found. Installing..."
    sudo pacman -Sy cava
    ## If installation fails, continue but print a warning for user to manually install cava, otherwise the music visualizer won't work.
    if ! command -v cava &> /dev/null; then
        echo "⚠️ Warning: cava installation failed. Please install cava manually for the music visualizer to work."
    else
        echo "✅ cava installed successfully."
    fi
fi

# Install zoxide
echo "📂 Setting up zoxide..."
if ! command -v zoxide &> /dev/null; then
    echo "📦 zoxide not found. Installing..."
    sudo pacman -Sy zoxide
    ## If installation fails, continue but print a warning for user to manually install zoxide, otherwise the cd alias won't work.
    if ! command -v zoxide &> /dev/null; then
        echo "⚠️ Warning: zoxide installation failed. Please install zoxide manually for the 'cd' alias to work."
    else
        echo "✅ zoxide installed successfully."
    fi
fi
# Install zoxide init in bash, fish and zsh
echo "📂 Setting up zoxide init in shell configs..."
## Check if zoxide is installed, if not install it using pacman (auto-confirm)
if ! command -v zoxide &> /dev/null; then
    echo "📦 zoxide not found. Installing..."
    sudo pacman -Sy zoxide
    ## If installation fails, continue but print a warning for user to manually install zoxide, otherwise the cd alias won't work.
    if ! command -v zoxide &> /dev/null; then
        echo "⚠️ Warning: zoxide installation failed. Please install zoxide manually for the 'cd' alias to work."
    else
        echo "✅ zoxide installed successfully."
    fi
fi
## Copying zoxide init lines to respective shell config files in storage
cp -f "$REPO_ROOT/.config/bashrc/zoxide" "$TARGET_STORAGE/.config/bashrc/zoxide"
cp -f "$REPO_ROOT/.config/fish/conf.d/zoxide.fish" "$TARGET_STORAGE/.config/fish/conf.d/zoxide.fish"
cp -f "$REPO_ROOT/.config/zshrc/zoxide" "$TARGET_STORAGE/.config/zshrc/zoxide"
## Copying alias lines to fish aliases file
cp -f "$REPO_ROOT/.config/fish/conf.d/10-aliases.fish" "$TARGET_STORAGE/.config/fish/conf.d/10-aliases.fish"
## Copying alias lines to bash aliases file
cp -f "$REPO_ROOT/.config/bashrc/10-aliases" "$TARGET_STORAGE/.config/bashrc/10-aliases"
## Copying alias lines to zsh aliases file
cp -f "$REPO_ROOT/.config/zshrc/25-aliases" "$TARGET_STORAGE/.config/zshrc/25-aliases"
echo "✅ zoxide init and aliases set up in shell configs."

echo "
============================================================
        ✅ CUSTOM DOTFILES CHANGES SUMMARY
============================================================

🎨 ML4W Theme & Wallpaper Customizations
   • ml4w-toggle-theme: Added 'Save' theme mode variable
     → Theme stays consistent after waybar/matugen changes
   • darkmode: Custom darkmode state file preserved
   • ml4w-wallpaper: Added darkmode variable
     → Matugen won't override darkmode unless desired

📱 Quickshell
   • Made a custom bar, replacing waybar. 

📸 Screenshot & Colorpicker Enhancements
   • screenshot.sh: Screenshots now copied to clipboard
     + saved to file (dual functionality)
   • colorpicker.sh: Added hyprpicker integration
     → Press META+P to pick colors

⌨️ Custom Keybindings Added
   • META+X → Powermenu
   • META+P → Colorpicker (hyprpicker)
   • META+D → Application launcher
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
        All changes saved to ~/.mydotfiles
============================================================
"