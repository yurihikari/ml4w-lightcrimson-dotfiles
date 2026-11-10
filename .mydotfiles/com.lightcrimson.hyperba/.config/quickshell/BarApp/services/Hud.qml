pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// HyperBA's HUD data: what the level plate and the counters show that the bar
// didn't have yet (memory in GB, free disk space, the user), and the lobby's
// state (shown, or hidden to look at the wallpaper).
Singleton {
    id: root

    readonly property string user: Quickshell.env("USER") || "user"

    property real memUsedGb: 0
    property real memTotalGb: 0
    property real diskFreeGb: 0
    property real diskTotalGb: 0

    // The level plate's "level": the focused workspace
    readonly property int level: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    // Hide everything but the wallpaper (the lobby's "view" button); any
    // click on the desktop brings it all back.
    property bool viewMode: false

    // The lobby asks its own screen's bar / drawer for a popup (IPC would
    // reach one screen's only). what: media, notifications, clipboard,
    // dashboard, dock (arg: tab index, or undefined to toggle).
    signal request(string screen, string what, var arg)

    // ── Busy screens ────────────────────────────────────────────────────────
    // A screen is busy when its visible workspace has a tiled (or fullscreen)
    // window: the lobby there unloads and the level card turns compact, so the
    // windows get the room of a regular bar. Refreshed on Hyprland's window /
    // workspace events (debounced), with a slow poll as a safety net.
    property var busyScreens: ({})
    function busy(screenName) { return busyScreens[screenName] === true }

    Process {
        id: busyProc
        command: ["bash", "-c", 'printf \'{"m":%s,"c":%s}\' "$(hyprctl monitors -j)" "$(hyprctl clients -j)"']
        stdout: StdioCollector {
            onStreamFinished: {
                let j; try { j = JSON.parse(text) } catch (e) { return }
                const active = {}, names = {}
                for (const m of j.m) { active[m.name] = m.activeWorkspace ? m.activeWorkspace.id : -1; names[m.id] = m.name }
                const out = {}
                for (const c of j.c) {
                    if (!c.mapped || c.hidden || !c.workspace) continue
                    const mon = names[c.monitor]
                    if (mon === undefined || c.workspace.id !== active[mon]) continue
                    if (!c.floating || c.fullscreen > 0) out[mon] = true
                }
                if (JSON.stringify(out) !== JSON.stringify(root.busyScreens)) root.busyScreens = out
            }
        }
    }
    Timer { id: busyDebounce; interval: 120; onTriggered: busyProc.running = true }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: busyDebounce.restart() }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name
            if (n.startsWith("openwindow") || n.startsWith("closewindow") || n.startsWith("movewindow")
                || n.startsWith("changefloatingmode") || n.startsWith("workspace") || n.startsWith("focusedmon")
                || n.startsWith("fullscreen") || n.startsWith("moveworkspace")) busyDebounce.restart()
        }
    }

    function fmt(n) { return Math.round(n).toLocaleString(Qt.locale("en_US"), "f", 0) }

    Process {
        id: poll
        command: ["bash", "-c",
            "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"mem %.2f %.2f\\n\", (t-a)/1048576, t/1048576}' /proc/meminfo; " +
            "df -B1 --output=avail,size \"$HOME\" | awk 'NR==2{printf \"disk %.1f %.1f\\n\", $1/1e9, $2/1e9}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const p = l.trim().split(/\s+/)
                    if (p[0] === "mem") { root.memUsedGb = parseFloat(p[1]) || 0; root.memTotalGb = parseFloat(p[2]) || 0 }
                    if (p[0] === "disk") { root.diskFreeGb = parseFloat(p[1]) || 0; root.diskTotalGb = parseFloat(p[2]) || 0 }
                }
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: poll.running = true }

    IpcHandler {
        target: "hud"
        function view(): void { root.viewMode = !root.viewMode }
        function show(): void { root.viewMode = false }
        // A popup on a given screen: qs ipc call hud ask DP-2 media
        // (media, notifications, clipboard, dashboard, dock)
        function ask(screen: string, what: string): void { root.request(screen, what, null) }
    }
}
