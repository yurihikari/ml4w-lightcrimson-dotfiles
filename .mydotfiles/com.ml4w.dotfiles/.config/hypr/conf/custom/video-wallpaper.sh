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
#   video-wallpaper.sh suspend | resume
#
# Game mode: while ~/.config/ml4w/settings/gamemode-enabled exists, no video
# plays. `suspend` (run by gamemode.sh when it turns on) stops the running
# videos, which frees their decoder and memory; the poster underneath stays, so
# the desktop keeps its wallpaper as a still frame. Any video asked for while
# suspended (a workspace switch, a new wallpaper) is only remembered, and
# `resume` starts whatever each monitor should be playing by then.
#
# Posters are cached as ~/.cache/video-wallpapers/posters/<md5 of path>.jpg; the
# Quickshell pickers compute the same name with Qt.md5() to show thumbnails.
# ============================================================================

VW_POSTERS="$HOME/.cache/video-wallpapers/posters"
VW_RUN="${XDG_RUNTIME_DIR:-/tmp}/video-wallpapers"   # per-monitor pid/video/want/paused files
VW_SUSPEND_FLAG="${VW_SUSPEND_FLAG:-$HOME/.config/ml4w/settings/gamemode-enabled}"
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

vw_suspended() { [[ -f "$VW_SUSPEND_FLAG" ]]; }

vw_stop() {  # $1 = monitor
    local pid
    rm -f "$VW_RUN/$1.want" "$VW_RUN/$1.paused"   # cancels a pending/suspended start
    if vw_running "$1"; then
        pid="$(cat "$VW_RUN/$1.pid")"
        kill "$pid" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    fi
    rm -f "$VW_RUN/$1.pid" "$VW_RUN/$1.video"
}

vw_stop_all() {
    local f
    for f in "$VW_RUN"/*.pid "$VW_RUN"/*.want "$VW_RUN"/*.paused; do
        [[ -e "$f" ]] || continue
        f="${f##*/}"; vw_stop "${f%.*}"
    done
}

# Stop every video (running or about to start) and remember it per monitor.
vw_suspend_all() {
    local f mon video
    for f in "$VW_RUN"/*.pid "$VW_RUN"/*.want; do
        [[ -e "$f" ]] || continue
        mon="${f##*/}"; mon="${mon%.*}"
        if [[ "$f" == *.pid ]]; then
            video="$(vw_current "$mon")"
        else
            video="$(cat "$f" 2>/dev/null)"; video="${video%|*|*}"   # token: video|pid|rand
        fi
        vw_stop "$mon"
        [[ -n "$video" ]] && printf '%s\n' "$video" > "$VW_RUN/$mon.paused"
    done
}

# Start the videos remembered while suspended.
vw_resume_all() {
    local f mon video
    for f in "$VW_RUN"/*.paused; do
        [[ -e "$f" ]] || continue
        mon="${f##*/}"; mon="${mon%.paused}"
        video="$(cat "$f" 2>/dev/null)"
        rm -f "$f"
        [[ -f "$video" ]] && vw_play "$mon" "$video"
    done
}

vw_play() {  # $1 = monitor, $2 = video
    local mon="$1" video="$2" pid
    [[ "$(vw_current "$mon")" == "$video" ]] && return 0
    if vw_suspended; then
        # Game mode: keep the poster, play this once it is turned off.
        vw_stop "$mon"
        mkdir -p "$VW_RUN"
        printf '%s\n' "$video" > "$VW_RUN/$mon.paused"
        return 0
    fi
    if ! command -v mpvpaper >/dev/null 2>&1; then
        echo "video-wallpaper: mpvpaper is not installed; showing the poster only" >&2
        return 1
    fi
    vw_stop "$mon"
    mkdir -p "$VW_RUN"
    # -p: pause while the wallpaper is fully hidden behind windows.
    # 9>&-: don't hand the per-workspace daemon's lock (fd 9) to the video,
    # which outlives it and would keep a restarted daemon from starting.
    setsid mpvpaper -p -o "$VW_MPV_OPTS" "$mon" "$video" >/dev/null 2>&1 < /dev/null 9>&- &
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
        suspend)  vw_suspend_all ;;
        resume)   vw_suspended || vw_resume_all ;;
        status)
            for f in "$VW_RUN"/*.pid; do
                [[ -e "$f" ]] || continue
                m="${f##*/}"; m="${m%.pid}"
                vw_running "$m" && echo "$m: $(cat "$VW_RUN/$m.video")"
            done
            for f in "$VW_RUN"/*.paused; do
                [[ -e "$f" ]] || continue
                m="${f##*/}"; m="${m%.paused}"
                echo "$m: $(cat "$f") (suspended)"
            done ;;
        *) echo "usage: ${0##*/} poster <video> | posters <folder> | play <monitor> <video> | stop <monitor> | stop-all | suspend | resume | status" >&2; exit 1 ;;
    esac
fi
