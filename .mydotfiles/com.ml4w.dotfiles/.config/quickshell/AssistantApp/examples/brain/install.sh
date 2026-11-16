#!/bin/sh
# Create the starter second brain in ~/brain, shared by the panel's assistants
# and Claude in a terminal. Never overwrites an existing brain.
#
#   install.sh             create ~/brain and enable the nightly digest
#   install.sh --no-timer  create ~/brain only
set -eu

here=$(cd "$(dirname "$0")" && pwd)
brain="$HOME/brain"
timer=1
for arg in "$@"; do
    case $arg in
        --no-timer) timer=0 ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ -e "$brain/BRAIN.md" ]; then
    echo "~/brain already exists: left as it is."
else
    mkdir -p "$brain"
    cp -rn "$here/skeleton/." "$brain/"
    for d in tickets clients projects notes/kb journal memory/daily conversations; do
        mkdir -p "$brain/$d"
    done
    chmod +x "$brain/tools/brain.py"
    python3 -I "$brain/tools/brain.py" index > /dev/null
    if command -v git > /dev/null; then
        git -C "$brain" init -q
        git -C "$brain" add -A
        git -C "$brain" commit -qm "brain: start" 2> /dev/null \
            || echo "git: no commit made (set user.name and user.email), the repo is ready anyway."
    fi
    echo "Created ~/brain."
fi

if [ "$timer" = 1 ]; then
    units="$HOME/.config/systemd/user"
    mkdir -p "$units"
    cp "$here/systemd/brain-digest.service" "$here/systemd/brain-digest.timer" "$units/"
    systemctl --user daemon-reload
    systemctl --user enable --now brain-digest.timer
    echo "Nightly digest enabled (23:30): systemctl --user list-timers brain-digest.timer"
fi

echo "Next: write your name after '- Called:' in ~/brain/memory/profile.md, then press + in the assistant panel."
