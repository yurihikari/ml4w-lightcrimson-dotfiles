#!/usr/bin/env bash
#                                 __        __ 
#   ___ ___________ ___ ___  ___ / /  ___  / /_
#  (_-</ __/ __/ -_) -_) _ \(_-</ _ \/ _ \/ __/
# /___/\__/_/  \__/\__/_//_/___/_//_/\___/\__/ 
#                                              
# Based on https://github.com/hyprwm/contrib/blob/main/grimblast/screenshot.sh

# -----------------------------------------------------

prompt='Screenshot'
mesg="DIR: ~/Screenshots"

SAVE_DIR=$(cat ~/.config/ml4w/settings/screenshot-folder)
SAVE_FILENAME=$(cat ~/.config/ml4w/settings/screenshot-filename)
eval screenshot_folder="$SAVE_DIR"
eval NAME="$SAVE_FILENAME"

# Notifications
source "$HOME/.config/ml4w/scripts/ml4w-notification-handler"
APP_NAME="Screen Capture"
NOTIFICATION_ICON="camera-photo-symbolic"

# Screenshot Editor
export GRIMBLAST_EDITOR="$(cat ~/.config/ml4w/settings/screenshot-editor)"

# Helper to handle clipboard and notification with preview
post_process() {
    local FILE_PATH="$screenshot_folder/$NAME"
    if [[ -f "$FILE_PATH" ]]; then
        # Copy to clipboard
        wl-copy < "$FILE_PATH"
        # Notify with the image itself as the icon
        notify_user \
            --a "${APP_NAME}" \
            --i "$FILE_PATH" \
            --s "Screenshot saved & copied" \
            --m "$FILE_PATH" \
            --t 1000
    fi
}

# Quick instant mode: full screen
take_instant_full() {
    grim "$HOME/$NAME"
    if [[ -f "$HOME/$NAME" ]]; then
        [[ -d "$screenshot_folder" && -w "$screenshot_folder" ]] && mv "$HOME/$NAME" "$screenshot_folder/"
        post_process
    fi
}

# Quick instant mode: area selection
take_instant_area() {
    local pid_picker region

    # freeze screen for region selection
    hyprpicker -r -z &
    pid_picker=$!
    trap 'kill "$pid_picker" 2>/dev/null' EXIT
    sleep 0.1

    # user selects region; kill picker on cancel
    region=$(slurp -b "#00000080" -c "#888888ff" -w 1) || exit 0
    [[ -z "$region" ]] && exit 0

    # unfreeze screen
    kill "$pid_picker" 2>/dev/null
    trap - EXIT

    # capture
    grim -g "$region" "$HOME/$NAME"
    if [[ -f "$HOME/$NAME" ]]; then
        [[ -d "$screenshot_folder" && -w "$screenshot_folder" ]] && mv "$HOME/$NAME" "$screenshot_folder/"
        post_process
    fi
}

# Handle instant flags
if [[ "$1" == "--instant" ]]; then
    take_instant_full
    exit 0
elif [[ "$1" == "--instant-area" ]]; then
    take_instant_area
    exit 0
fi

# Options
option_1="Immediate"
option_2="Delayed"

option_capture_1="Capture Everything"
option_capture_2="Capture Active Display"
option_capture_3="Capture Selection"

option_time_1="5s"
option_time_2="10s"
option_time_3="20s"
option_time_4="30s"
option_time_5="60s"

list_col='1'
list_row='2'

copy='Copy'
save='Save'
copy_save='Copy & Save'
edit='Edit'

# Rofi CMD
rofi_cmd() {
    rofi -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 2 -width 30 -p "Take screenshot"
}

# Pass variables to rofi dmenu
run_rofi() {
    echo -e "$option_1\n$option_2" | rofi_cmd
}

# Choose Timer
timer_cmd() {
    rofi -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 5 -width 30 -p "Choose timer"
}

timer_exit() {
    echo -e "$option_time_1\n$option_time_2\n$option_time_3\n$option_time_4\n$option_time_5" | timer_cmd
}

timer_run() {
    selected_timer="$(timer_exit)"
    if [[ "$selected_timer" == "$option_time_1" ]]; then
        countdown=5
        ${1}
    elif [[ "$selected_timer" == "$option_time_2" ]]; then
        countdown=10
        ${1}
    elif [[ "$selected_timer" == "$option_time_3" ]]; then
        countdown=20
        ${1}
    elif [[ "$selected_timer" == "$option_time_4" ]]; then
        countdown=30
        ${1}
    elif [[ "$selected_timer" == "$option_time_5" ]]; then
        countdown=60
        ${1}
    else
        exit
    fi
}

# Choose Screenshot Type
type_screenshot_cmd() {
    rofi -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 3 -width 30 -p "Type of screenshot"
}

type_screenshot_exit() {
    echo -e "$option_capture_1\n$option_capture_2\n$option_capture_3" | type_screenshot_cmd
}

type_screenshot_run() {
    selected_type_screenshot="$(type_screenshot_exit)"
    if [[ "$selected_type_screenshot" == "$option_capture_1" ]]; then
        option_type_screenshot=screen
        ${1}
    elif [[ "$selected_type_screenshot" == "$option_capture_2" ]]; then
        option_type_screenshot=output
        ${1}
    elif [[ "$selected_type_screenshot" == "$option_capture_3" ]]; then
        option_type_screenshot=area
        ${1}
    else
        exit
    fi
}

# Choose to save or copy photo
copy_save_editor_cmd() {
    rofi -dmenu -replace -config ~/.config/rofi/config-screenshot.rasi -i -no-show-icons -l 4 -width 30 -p "How to save"
}

copy_save_editor_exit() {
    echo -e "$copy\n$save\n$copy_save\n$edit" | copy_save_editor_cmd
}

copy_save_editor_run() {
    selected_chosen="$(copy_save_editor_exit)"
    if [[ "$selected_chosen" == "$copy" ]]; then
        option_chosen=copy
        ${1}
    elif [[ "$selected_chosen" == "$save" ]]; then
        option_chosen=save
        ${1}
    elif [[ "$selected_chosen" == "$copy_save" ]]; then
        option_chosen=copysave
        ${1}
    elif [[ "$selected_chosen" == "$edit" ]]; then
        option_chosen=edit
        ${1}
    else
        exit
    fi
}

timer() {
    if [[ $countdown -gt 10 ]]; then
        notify_user --a "${APP_NAME}" --i "${NOTIFICATION_ICON}" --s "Taking screenshot in ${countdown} seconds" --t 1000
        sleep $((countdown - 10))
        countdown=10
    fi
    while [[ $countdown -ne 0 ]]; do
        notify_user --a "${APP_NAME}" --i "${NOTIFICATION_ICON}" --s "Taking screenshot in ${countdown} seconds" --t 1000
        countdown=$((countdown - 1))
        sleep 1
    done
}

# take shots
takescreenshot() {
    sleep 1
    # We always save to a file first so we can copy it and show a preview
    # If the user chose 'copy', we treat it as 'copysave' internally to get the file
    local action="$option_chosen"
    [[ "$action" == "copy" ]] && action="copysave"
    
    grimblast "$action" "$option_type_screenshot" "$HOME/$NAME"
    
    if [ -f "$HOME/$NAME" ]; then
        if [ -d "$screenshot_folder" ]; then
            mv "$HOME/$NAME" "$screenshot_folder/"
        fi
        post_process
    fi
}

takescreenshot_timer() {
    sleep 1
    timer
    takescreenshot
}

# Execute Command
run_cmd() {
    if [[ "$1" == '--opt1' ]]; then
        type_screenshot_run
        copy_save_editor_run "takescreenshot"
    elif [[ "$1" == '--opt2' ]]; then
        timer_run
        type_screenshot_run
        copy_save_editor_run "takescreenshot_timer"
    fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
    $option_1)
        run_cmd --opt1
        ;;
    $option_2)
        run_cmd --opt2
        ;;
esac