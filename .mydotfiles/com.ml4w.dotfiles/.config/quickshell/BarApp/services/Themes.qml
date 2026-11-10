pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The theme switcher (dotswitch, ~/.local/bin/dotswitch) for the Settings
// page and the quick settings corner. Reads `dotswitch json`; actions run
// dotswitch.
//
// Switching (or restoring the active theme) stops this very shell: its
// deactivate script kills Quickshell, and the new theme's activate script
// starts its own. So those run fully detached and log to ~/.local/state/
// dotswitch/ui.log; everything else runs here and refreshes when done.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string bin: home + "/.local/bin/dotswitch"
    readonly property string logFile: home + "/.local/state/dotswitch/ui.log"

    property bool available: true       // dotswitch is installed
    property bool loaded: false
    property string active: ""
    property string previous: ""
    property var themes: []             // [{ id, name, description, active, live, preview, path }]
    property var snapshots: []          // [{ theme, name, file, size, time }], newest first
    property string keepFile: ""
    property int keepCount: 0

    property string busy: ""            // "", "switch", "save", "new", "remove", "restore", "preview"
    property string busyTheme: ""
    property string error: ""
    property int previewRev: 0          // bumped when a preview is retaken (image cache buster)

    readonly property var activeTheme: themes.find(t => t.active) || null
    readonly property var previousTheme: previous !== active ? (themes.find(t => t.id === previous) || null) : null
    function theme(id) { return themes.find(t => t.id === id) || null }
    function snapshotsOf(id) { return snapshots.filter(s => s.theme === id) }
    function isBusy(kind, id) { return busy === kind && (id === undefined || busyTheme === id) }

    // ── Reading ────────────────────────────────────────────────────────────
    function refresh() { if (!reader.running) reader.running = true }
    Process {
        id: reader
        command: ["bash", "-c", '[ -x "$1" ] || { echo missing; exit 0; }; exec "$1" json', "themes", root.bin]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                root.loaded = true
                if (t === "missing") { root.available = false; return }
                root.available = true
                try {
                    const j = JSON.parse(t)
                    root.active = j.active || ""
                    root.previous = j.previous || ""
                    root.themes = j.themes || []
                    root.snapshots = j.snapshots || []
                    root.keepFile = j.keepFile || ""
                    root.keepCount = j.keepCount || 0
                } catch (e) {
                    root.error = "Couldn't read the theme list"
                }
            }
        }
    }
    Component.onCompleted: refresh()

    // ── Actions that keep this shell running ───────────────────────────────
    function save(id) { act("save", id, ["save", id]) }
    function create(name, from) {
        const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "theme"
        let id = "com.lightcrimson." + slug, n = 2
        while (theme(id)) id = "com.lightcrimson." + slug + "-" + n++
        act("new", id, ["new", id, "--from", from || active, "--name", name])
    }
    function remove(id) { act("remove", id, ["remove", id, "-y"]) }
    function restore(id, file) {
        if (id === active) { detached("restore", id, ["restore", id, file, "-y"]); return }
        act("restore", id, ["restore", id, file, "-y"])
    }
    // A screenshot of the focused monitor as the active theme's thumbnail,
    // taken a moment later so whatever asked for it can get out of the way.
    function updatePreview() { act("preview", active, ["preview"], 1.2) }

    function act(kind, id, args, delay) {
        if (busy !== "") return
        busy = kind; busyTheme = id || ""; error = ""
        actor.command = ["bash", "-c", 'sleep "$1"; shift; exec "$@"', "themes", String(delay || 0), root.bin].concat(args)
        actor.running = true
    }
    Process {
        id: actor
        stderr: StdioCollector { id: actorErr }
        onExited: (code) => {
            if (code !== 0) {
                const lines = actorErr.text.trim().split("\n").filter(l => l !== "")
                root.error = (lines.length ? lines[lines.length - 1] : "dotswitch failed").replace(/^error:\s*/, "")
            }
            if (root.busy === "preview") root.previewRev++
            root.busy = ""; root.busyTheme = ""
            root.refresh()
        }
    }

    // ── Actions that replace this shell ────────────────────────────────────
    function switchTo(id) { if (id !== active) detached("switch", id, ["use", id, "-y"]) }

    function detached(kind, id, args) {
        if (busy !== "") return
        busy = kind; busyTheme = id; error = ""
        Quickshell.execDetached(["setsid", "-f", "bash", "-c",
            'mkdir -p "$(dirname "$1")"; log="$1"; shift; exec "$@" > "$log" 2>&1',
            "themes", root.logFile, root.bin].concat(args))
        stuck.restart()
    }
    // Normally this shell is gone long before this fires. If it is still
    // here, the switch didn't happen (dotswitch refused): show why.
    Timer {
        id: stuck
        interval: 12000
        onTriggered: { root.busy = ""; root.busyTheme = ""; logReader.running = true; root.refresh() }
    }
    Process {
        id: logReader
        command: ["bash", "-c", 'grep -m1 "error:" "$1" | sed "s/.*error: *//"', "themes", root.logFile]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.error = text.trim() }
    }

    // ── IPC (keybindings, scripts) ─────────────────────────────────────────
    //   qs ipc call themes switchTo <id or name>    qs ipc call themes list
    IpcHandler {
        target: "themes"
        function list(): string { return root.themes.map(t => (t.active ? "* " : "  ") + t.name + "\t" + t.id).join("\n") }
        function switchTo(theme: string): void {
            const w = theme.toLowerCase()
            const t = root.themes.find(x => x.id.toLowerCase() === w || x.name.toLowerCase() === w || x.id.split(".").pop() === w)
            if (t) root.switchTo(t.id)
        }
        function create(name: string): void { root.create(name, root.active) }
        function snapshot(): void { root.save(root.active) }
        function preview(): void { root.updatePreview() }
        function refresh(): void { root.refresh() }
    }

    // ── Misc ───────────────────────────────────────────────────────────────
    function editKeepList() {
        Quickshell.execDetached(["bash", "-c", '"$HOME/.config/ml4w/settings/editor.sh" "$1" || xdg-open "$1"', "themes", keepFile])
    }
    function openFolder(id) {
        const t = theme(id)
        if (t) Quickshell.execDetached(["xdg-open", t.path])
    }

    function sizeText(b) {
        return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : b >= 1e6 ? Math.round(b / 1e6) + " MB" : Math.round(b / 1e3) + " kB"
    }
    function ago(t) {
        const s = Date.now() / 1000 - t
        if (s < 90) return "just now"
        if (s < 3600) return Math.round(s / 60) + " min ago"
        if (s < 86400) return Math.round(s / 3600) + " h ago"
        if (s < 86400 * 2) return "yesterday"
        if (s < 86400 * 14) return Math.round(s / 86400) + " days ago"
        return Qt.formatDate(new Date(t * 1000), "d MMM yyyy")
    }
}
