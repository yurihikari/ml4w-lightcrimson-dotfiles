#!/bin/bash

# --- CONFIGURATION ---
MY_DOTFILES_ROOT="$HOME/.mydotfiles"
TARGET_STORAGE="$MY_DOTFILES_ROOT/com.ml4w.dotfiles"
BACKUP_DIR="$MY_DOTFILES_ROOT/.backups"

echo "⏪ Starting ML4W Dotfiles Restore Tool..."

# 1. Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ No backups found at $BACKUP_DIR"
    exit 1
fi

# 2. Get a list of available backups (sorted by date, newest first)
# We store them in an array
cd "$BACKUP_DIR" || exit 1
backups=( $(ls -d backup_* 2>/dev/null | sort -r) )

if [ ${#backups[@]} -eq 0 ]; then
    echo "❌ No folders starting with 'backup_' found in $BACKUP_DIR"
    exit 1
fi

# 3. Display the backups to the user
echo ""
echo "Select a backup to restore:"
echo "--------------------------------"
for i in "${!backups[@]}"; do
    # Pretty print the folder name
    # e.g., backup_20231027_120000 -> 1) 2023-10-27 12:00:00
    folder_name="${backups[$i]}"
    date_part=$(echo "$folder_name" | cut -d'_' -f2)
    time_part=$(echo "$folder_name" | cut -d'_' -f3)
    
    formatted_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2}"
    formatted_time="${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
    
    echo "[$i] 📅 $formatted_date 🕒 $formatted_time ($folder_name)"
done
echo "--------------------------------"

# 4. Get user choice
read -p "Enter the number of the backup you want to restore: " choice

# Validate input
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge "${#backups[@]}" ]; then
    echo "❌ Invalid selection. Exiting."
    exit 1
fi

selected_backup="${backups[$choice]}"
echo ""
echo "⚠️ You selected: $selected_backup"
read -p "Are you sure you want to overwrite your current setup? (y/n): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Restore cancelled."
    exit 0
fi

# 5. Perform the Restore
echo "🔄 Restoring files to $TARGET_STORAGE..."

# Using 'cp -af' to overwrite files while keeping symlinks and structure intact
cp -af "$BACKUP_DIR/$selected_backup/com.ml4w.dotfiles/." "$TARGET_STORAGE/"

echo "✅ Restore completed successfully!"
echo "💡 You may need to restart Hyprland or reload Waybar to see the changes."