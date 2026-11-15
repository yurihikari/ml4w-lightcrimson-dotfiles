#!/usr/bin/env bash
# Step through a character's animations, one every few seconds, with each
# name in the speech bubble, to find which ones to use in character.json.
#   preview.sh <persona id> [seconds per animation] [name filter regex]
# e.g. preview.sh arona 4 '^[0-9]+$'   (only the numbered ones)
id="${1:?usage: preview.sh <persona id> [seconds] [filter]}"; secs="${2:-4}"; filter="${3:-.}"
dir="$HOME/.local/share/ml4w-assistant/characters/$id"
here="$(dirname "$(readlink -f "$0")")"
coproc CHAR { python3 -I "$here/character.py" --assets "$dir" --right 40; }
names=()
while read -r line <&"${CHAR[0]}"; do
    case "$line" in
        *'"ready"'*) mapfile -t names < <(python3 -c 'import json,sys; [print(n) for n in json.loads(sys.argv[1])["animations"]]' "$line"); break ;;
        *'"error"'*) echo "$line"; exit 1 ;;
    esac
done
for n in "${names[@]}"; do
    [[ "$n" =~ $filter ]] || continue
    echo "$n"
    printf '{"cmd":"preview","name":"%s"}\n' "$n" >&"${CHAR[1]}"
    sleep "$secs"
done
echo '{"cmd":"quit"}' >&"${CHAR[1]}"
