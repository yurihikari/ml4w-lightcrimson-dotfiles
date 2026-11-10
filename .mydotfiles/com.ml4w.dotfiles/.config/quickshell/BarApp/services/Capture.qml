pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen capture for the capture corner (CapturePanel) and its keybindings:
// screenshots, screen recording and instant replay (gpu-screen-recorder, which
// encodes on the GPU, so recording barely costs CPU or battery), text from the
// screen (OCR) and the colour picker, plus the latest captures.
//
// Screenshots follow the ML4W settings (screenshot folder and editor), are
// copied to the clipboard and announced with Open / Annotate / Show in folder
// actions. Every capture first closes the corner drawers and waits for them to
// slide away, so they never end up in the picture.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // ── Where things go ─────────────────────────────────────────────────────
    property string shotDir: home + "/Pictures/Screenshots"
    property string editor: ""
    readonly property string recDir: home + "/Videos/Recordings"
    readonly property string replayDir: home + "/Videos/Replays"
    readonly property string thumbDir: home + "/.cache/ml4w/capture-thumbs"

    function expand(p) { return p.replace(/^~(?=\/|$)/, home).replace(/^\$HOME(?=\/|$)/, home) }

    FileView {
        path: root.home + "/.config/ml4w/settings/screenshot-folder"
        printErrors: false
        onLoaded: { const t = text().trim(); if (t !== "") root.shotDir = root.expand(t) }
    }
    FileView {
        path: root.home + "/.config/ml4w/settings/screenshot-editor"
        printErrors: false
        onLoaded: root.editor = text().trim()
    }

    // ── Tools ───────────────────────────────────────────────────────────────
    property bool hasRecorder: false
    function checkTools() { if (!toolCheck.running) toolCheck.running = true }
    Process {
        id: toolCheck
        running: true
        command: ["bash", "-c", "command -v gpu-screen-recorder >/dev/null && echo recorder"]
        stdout: StdioCollector { onStreamFinished: root.hasRecorder = text.indexOf("recorder") >= 0 }
    }

    // Time for the drawers to slide back into the frame before capturing.
    readonly property string settle: "0.4"

    // ── Screenshots ─────────────────────────────────────────────────────────
    property int delay: 0               // seconds before the shot
    property bool annotate: false       // open the editor instead of notifying
    readonly property bool shooting: shotProc.running

    // mode: region | window | screen | all; screen: the monitor for "screen"
    function screenshot(mode, screen) {
        if (shotProc.running) return
        Corners.closeAll()
        const out = screen || Corners.focusedScreen()
        shotProc.command = ["bash", "-c", `
            dir="$1"; mode="$2"; wait="$3"; out="$4"
            mkdir -p "$dir" || exit 1
            f="$dir/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
            sleep "$wait"
            case "$mode" in
                region) grimblast --freeze save area "$f" >/dev/null 2>&1 ;;
                window) grimblast save active "$f" >/dev/null 2>&1 ;;
                screen) grim -o "$out" "$f" ;;
                *)      grim "$f" ;;
            esac
            [ -s "$f" ] || exit 1
            wl-copy --type image/png < "$f"
            echo "$f"`,
            "screenshot", shotDir, mode, String(parseFloat(settle) + delay), out]
        shotProc.running = true
    }
    Process {
        id: shotProc
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim()
                if (f === "") return
                if (root.annotate && root.editor !== "") root.edit(f)
                else root.announceShot(f)
                root.refreshRecent()
            }
        }
    }

    function edit(f) {
        Quickshell.execDetached(["bash", "-c", 'eval "$1 \\"\\$2\\""', "edit", editor, f])
    }

    function announceShot(f) {
        Quickshell.execDetached(["bash", "-c", `
            f="$1"; dir="$2"; editor="$3"
            acts=(-A open=Open)
            [ -n "$editor" ] && acts+=(-A edit=Annotate)
            acts+=(-A folder="Show in folder")
            a=$(notify-send -a "Screen capture" -i "$f" "\${acts[@]}" "Screenshot copied" "$(basename "$f")")
            case "$a" in
                open) xdg-open "$f" ;;
                edit) eval "$editor \\"\\$f\\"" ;;
                folder) xdg-open "$dir" ;;
            esac`, "notify", f, shotDir, editor])
    }

    // ── Text from the screen ────────────────────────────────────────────────
    function ocr() {
        Corners.closeAll()
        Quickshell.execDetached(["bash", "-c", `
            sleep "$1"
            img=$(mktemp --suffix .png)
            trap 'rm -f "$img"' EXIT
            grimblast --freeze save area "$img" >/dev/null 2>&1 && [ -s "$img" ] || exit 0
            langs=$(tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vx osd | paste -sd+)
            text=$(magick "$img" -colorspace Gray -normalize -contrast-stretch 2% -sharpen 0x1.0 -resize 200% png:- \\
                | tesseract - stdout -l "\${langs:-eng}" --psm 6 2>/dev/null)
            if [ -z "\${text//[[:space:]]/}" ]; then
                notify-send -a "Screen capture" -i edit-find "No text found" "Nothing readable in that area."
                exit 0
            fi
            printf '%s' "$text" | wl-copy
            notify-send -a "Screen capture" -i edit-copy "Text copied" "$(printf '%s' "$text" | head -c 200)"`,
            "ocr", settle])
    }

    // ── Colour picker ───────────────────────────────────────────────────────
    // Latest first, kept across restarts.
    property var colors: []
    readonly property bool picking: pickProc.running

    function pickColor() {
        if (pickProc.running) return
        Corners.closeAll()
        pickProc.command = ["bash", "-c", 'sleep "$1"; hyprpicker -a -f hex 2>/dev/null', "pick", settle]
        pickProc.running = true
    }
    Process {
        id: pickProc
        stdout: StdioCollector {
            onStreamFinished: {
                const c = text.trim()
                if (!/^#[0-9a-fA-F]{6,8}$/.test(c)) return
                root.remember(c)
                Quickshell.execDetached(["bash", "-c", `
                    img="\${XDG_RUNTIME_DIR:-/tmp}/picked-color.png"
                    magick -size 48x48 xc:"$1" "$img" 2>/dev/null
                    notify-send -a "Colour picker" -u low -i "$img" "$1" "Copied to the clipboard"`, "notify", c])
            }
        }
    }
    function remember(c) {
        const list = [c].concat(colors.filter(x => x.toLowerCase() !== c.toLowerCase())).slice(0, 8)
        colors = list
        colorFile.setText(list.join("\n") + "\n")
    }
    function copyColor(c) {
        Quickshell.execDetached(["wl-copy", c])
        remember(c)
    }
    FileView {
        id: colorFile
        path: root.home + "/.cache/ml4w/picked-colors"
        printErrors: false
        onLoaded: root.colors = text().split("\n").map(s => s.trim()).filter(s => /^#[0-9a-fA-F]{6,8}$/.test(s)).slice(0, 8)
    }

    // ── Screen recording ────────────────────────────────────────────────────
    property bool recMic: false
    property bool recSystem: true
    readonly property bool recording: recProc.running
    property bool paused: false
    property int elapsed: 0              // seconds recorded (pauses excluded)
    property string recFile: ""
    property bool preparing: prepProc.running

    function audioArgs(system, mic) {
        const a = []
        if (system) a.push("default_output")
        if (mic) a.push("default_input")
        return a.length > 0 ? ["-a", a.join("|")] : []
    }

    // mode: region | screen; screen: the monitor for "screen"
    function record(mode, screen) {
        if (!hasRecorder || recProc.running || prepProc.running) return
        Corners.closeAll()
        prepProc.mode = mode
        prepProc.out = screen || Corners.focusedScreen()
        // A region is picked first; the screen just waits for the drawers.
        prepProc.command = mode === "region"
            // (slurp's stdin must not be the pipe Quickshell opens: when stdin
            // isn't a terminal, slurp waits there for preset boxes instead of
            // letting you draw one, so it never showed up.)
            ? ["bash", "-c", 'sleep "$1"; slurp -f "%wx%h+%x+%y" </dev/null', "prep", settle]
            : ["bash", "-c", 'sleep "$1"; echo screen', "prep", settle]
        prepProc.running = true
    }
    Process {
        id: prepProc
        property string mode: "screen"
        property string out: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim()
                if (r === "") return            // selection cancelled
                const file = root.recDir + "/recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4"
                // A region is given in logical pixels (slurp's); the recorder
                // scales it per monitor itself.
                const target = ["-w", prepProc.mode === "region" ? r : prepProc.out]
                root.recFile = file
                root.elapsed = 0
                root.paused = false
                recProc.command = ["bash", "-c", 'mkdir -p "$1"; shift; exec "$@"', "rec", root.recDir,
                    "gpu-screen-recorder"].concat(target,
                    ["-f", "60", "-c", "mp4", "-ac", "aac", "-cursor", "yes", "-v", "no"],
                    root.audioArgs(root.recSystem, root.recMic), ["-o", file])
                recProc.running = true
            }
        }
    }
    Process {
        id: recProc
        stderr: StdioCollector { id: recErr }
        onExited: (code) => {
            root.paused = false
            const f = root.recFile
            Quickshell.execDetached(["bash", "-c", `
                f="$1"; thumbs="$2"; err="$3"
                if [ ! -s "$f" ]; then
                    notify-send -a "Screen recorder" -u critical -i dialog-error "Recording failed" "$(printf '%s' "$err" | tail -n 3)"
                    exit 0
                fi
                mkdir -p "$thumbs"
                t="$thumbs/$(basename "$f").jpg"
                ffmpeg -loglevel error -y -ss 0.5 -i "$f" -frames:v 1 -vf scale=320:-1 "$t" </dev/null >/dev/null 2>&1
                a=$(notify-send -a "Screen recorder" -i "$t" -A open=Open -A folder="Show in folder" "Recording saved" "$(basename "$f")")
                case "$a" in open) xdg-open "$f" ;; folder) xdg-open "$(dirname "$f")" ;; esac`,
                "recorded", f, root.thumbDir, recErr.text])
            refreshTimer.restart()
        }
    }
    function stopRecording() { if (recProc.running) recProc.signal(2) }        // SIGINT: finish the file
    function togglePause() {
        if (!recProc.running) return
        recProc.signal(12)                                                       // SIGUSR2: pause / resume
        paused = !paused
    }
    Timer {
        interval: 1000; repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsed += 1
    }
    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }

    // ── Instant replay ──────────────────────────────────────────────────────
    // Keeps the last 30 seconds of the screen in memory; saveReplay() writes
    // them to a file.
    readonly property bool replayOn: replayProc.running
    readonly property int replaySeconds: 30

    function toggleReplay(screen) {
        if (replayProc.running) { replayProc.signal(2); return }
        if (!hasRecorder) return
        replayProc.command = ["bash", "-c", 'mkdir -p "$1"; shift; exec "$@"', "replay", replayDir,
            "gpu-screen-recorder", "-w", screen || Corners.focusedScreen(), "-f", "60", "-c", "mp4", "-ac", "aac",
            "-r", String(replaySeconds), "-cursor", "yes", "-v", "no"].concat(audioArgs(recSystem, recMic), ["-o", replayDir])
        replayProc.running = true
    }
    function saveReplay() {
        if (!replayProc.running) return
        replayProc.signal(10)                                                    // SIGUSR1: save
        replaySaved.restart()
    }
    Process { id: replayProc }
    // gpu-screen-recorder takes a moment to write the clip.
    Timer {
        id: replaySaved
        interval: 1500
        onTriggered: {
            Quickshell.execDetached(["bash", "-c", `
                f=$(ls -t "$1"/*.mp4 2>/dev/null | head -n 1)
                [ -n "$f" ] || exit 0
                mkdir -p "$2"; t="$2/$(basename "$f").jpg"
                ffmpeg -loglevel error -y -ss 0.5 -i "$f" -frames:v 1 -vf scale=320:-1 "$t" </dev/null >/dev/null 2>&1
                a=$(notify-send -a "Screen recorder" -i "$t" -A open=Open -A folder="Show in folder" "Replay saved" "Last $3 seconds: $(basename "$f")")
                case "$a" in open) xdg-open "$f" ;; folder) xdg-open "$1" ;; esac`,
                "replay", root.replayDir, root.thumbDir, String(root.replaySeconds)])
            refreshTimer.restart()
        }
    }

    // ── Latest captures ─────────────────────────────────────────────────────
    // [{ path, thumb, video }], newest first
    property var recent: []
    function refreshRecent() { if (!recentProc.running) recentProc.running = true }
    Timer { id: refreshTimer; interval: 1200; onTriggered: root.refreshRecent() }
    Process {
        id: recentProc
        command: ["bash", "-c", `
            thumbs="$1"; shift
            find "$@" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\
                -o -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \\) -printf '%T@\\t%p\\n' 2>/dev/null \\
                | sort -rn | head -n 4 | cut -f2- | while IFS= read -r f; do
                case "\${f,,}" in
                    *.mp4|*.mkv|*.webm)
                        t="$thumbs/$(basename "$f").jpg"
                        if [ ! -s "$t" ]; then
                            mkdir -p "$thumbs"
                            ffmpeg -loglevel error -y -ss 0.5 -i "$f" -frames:v 1 -vf scale=320:-1 "$t" </dev/null >/dev/null 2>&1
                        fi
                        printf 'v\\t%s\\t%s\\n' "$f" "$t" ;;
                    *) printf 'i\\t%s\\t%s\\n' "$f" "$f" ;;
                esac
            done`, "recent", root.thumbDir, root.shotDir, root.recDir, root.replayDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.recent = text.split("\n").filter(l => l !== "").map(l => {
                    const p = l.split("\t")
                    return { video: p[0] === "v", path: p[1], thumb: p[2] }
                })
            }
        }
    }
    function openFile(f) { Quickshell.execDetached(["xdg-open", f]) }
    function openFolder(f) { Quickshell.execDetached(["xdg-open", f]) }
}
