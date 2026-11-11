#!/usr/bin/env bash

# ============================================================================
# Video wallpapers (mpvpaper on top of awww)
# ----------------------------------------------------------------------------
# awww stays the wallpaper backend for everything. A video wallpaper is shown as
#   1. a poster (the video's first frame) painted by awww underneath, which keeps
#      transitions, matugen theming and the blurred/square variants working, and
#   2. one mpvpaper per monitor drawn on top of it, playing the video in a loop.
# Both live on the background layer; the surface created later sits on top, so
# mpvpaper must always be (re)started after awww.
#
# Sourced as a library by workspace-wallpapers.sh and ml4w-wallpaper, and also
# usable as a command:
#   video-wallpaper.sh poster <video>       print the poster path (made if needed)
#   video-wallpaper.sh posters <folder>     make posters for every video in folder
#   video-wallpaper.sh play <monitor> <video>
#   video-wallpaper.sh stop <monitor> | stop-all | status
#
# Posters are cached as ~/.cache/video-wallpapers/posters/<md5 of path>.jpg; the
# Quickshell pickers compute the same name with Qt.md5() to show thumbnails.
# ============================================================================

VW_POSTERS="$HOME/.cache/video-wallpapers/posters"
VW_RUN="${XDG_RUNTIME_DIR:-/tmp}/video-wallpapers"   # per-monitor pid/video/want files
# mpv options: silent, looped, hardware-decoded, cropped to fill like awww's crop.
VW_MPV_OPTS="${VW_MPV_OPTS:-no-audio loop-file=inf hwdec=auto panscan=1.0 really-quiet}"

vw_is_video() {
    local p="${1,,}"
    [[ "$p" =~ \.(mp4|webm|mkv|mov|m4v|avi)$ ]]
}

vw_poster_path() {
    printf '%s/%s.jpg' "$VW_POSTERS" "$(printf '%s' "$1" | md5sum | cut -d' ' -f1)"
}

# Print the poster for a video, (re)generating it when missing or older than the video.
vw_poster() {
    local video="$1" poster
    poster="$(vw_poster_path "$video")"
    if [[ ! -s "$poster" || "$video" -nt "$poster" ]]; then
        mkdir -p "$VW_POSTERS"
        ffmpeg -nostdin -loglevel error -y -i "$video" -frames:v 1 -q:v 2 "$poster.tmp.jpg" \
            && mv -f "$poster.tmp.jpg" "$poster" \
            || { rm -f "$poster.tmp.jpg"; return 1; }
    fi
    printf '%s\n' "$poster"
}

vw_running() {  # $1 = monitor
    local pid
    pid="$(cat "$VW_RUN/$1.pid" 2>/dev/null)" || return 1
    [[ -n "$pid" && "$(cat "/proc/$pid/comm" 2>/dev/null)" == "mpvpaper" ]]
}

vw_current() {  # $1 = monitor → video currently playing there (empty if none)
    vw_running "$1" && cat "$VW_RUN/$1.video" 2>/dev/null
}

vw_stop() {  # $1 = monitor
    local pid
    rm -f "$VW_RUN/$1.want"   # cancels a pending delayed start
    if vw_running "$1"; then
        pid="$(cat "$VW_RUN/$1.pid")"
        kill "$pid" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    fi
    rm -f "$VW_RUN/$1.pid" "$VW_RUN/$1.video"
}

vw_stop_all() {
    local f
    for f in "$VW_RUN"/*.pid "$VW_RUN"/*.want; do
        [[ -e "$f" ]] || continue
        f="${f##*/}"; vw_stop "${f%.*}"
    done
}

vw_play() {  # $1 = monitor, $2 = video
    local mon="$1" video="$2" pid
    [[ "$(vw_current "$mon")" == "$video" ]] && return 0
    if ! command -v mpvpaper >/dev/null 2>&1; then
        echo "video-wallpaper: mpvpaper is not installed; showing the poster only" >&2
        return 1
    fi
    vw_stop "$mon"
    mkdir -p "$VW_RUN"
    # -p: pause while the wallpaper is fully hidden behind windows
    setsid mpvpaper -p -o "$VW_MPV_OPTS" "$mon" "$video" >/dev/null 2>&1 < /dev/null &
    pid=$!
    disown "$pid" 2>/dev/null
    echo "$pid" > "$VW_RUN/$mon.pid"
    printf '%s\n' "$video" > "$VW_RUN/$mon.video"
}

# Start after a delay (lets awww finish its transition to the poster first).
# A later vw_stop/vw_play_after on the same monitor cancels this one.
vw_play_after() {  # $1 = delay (s), $2 = monitor, $3 = video
    local delay="$1" mon="$2" video="$3" token
    [[ "$(vw_current "$mon")" == "$video" ]] && return 0
    mkdir -p "$VW_RUN"
    token="$video|$$|$RANDOM"
    printf '%s\n' "$token" > "$VW_RUN/$mon.want"
    (
        sleep "$delay"
        [[ "$(cat "$VW_RUN/$mon.want" 2>/dev/null)" == "$token" ]] || exit 0
        rm -f "$VW_RUN/$mon.want"
        vw_play "$mon" "$video"
    ) >/dev/null 2>&1 &
    disown $! 2>/dev/null
}

# --- Command mode -----------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "$1" in
        poster)   vw_poster "$2" ;;
        posters)
            [[ -d "$2" ]] || exit 1
            find "$2" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
                vw_is_video "$f" && vw_poster "$f" >/dev/null
            done ;;
        play)     vw_play "$2" "$3" ;;
        stop)     vw_stop "$2" ;;
        stop-all) vw_stop_all ;;
        status)
            for f in "$VW_RUN"/*.pid; do
                [[ -e "$f" ]] || continue
                m="${f##*/}"; m="${m%.pid}"
                vw_running "$m" && echo "$m: $(cat "$VW_RUN/$m.video")"
            done ;;
        *) echo "usage: ${0##*/} poster <video> | posters <folder> | play <monitor> <video> | stop <monitor> | stop-all | status" >&2; exit 1 ;;
    esac
fi
