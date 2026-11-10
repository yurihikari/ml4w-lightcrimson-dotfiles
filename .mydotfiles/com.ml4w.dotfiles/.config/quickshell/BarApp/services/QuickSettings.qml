pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// State behind the quick settings corner (QuickPanel): keep awake, night
// light, game mode, power profile and battery draw, and presentation mode.
// (Do Not Disturb lives in Notifs; hotspot and VPN in the Settings app's NM.)
//
// System state is only polled while the drawer is open (watch / unwatch).
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // ── Keep awake ──────────────────────────────────────────────────────────
    // An idle inhibitor held while on: hypridle honours it, so the screen
    // neither dims, locks nor suspends. Lost with the shell, never left behind.
    property bool keepAwake: false
    Process {
        running: root.keepAwake
        command: ["systemd-inhibit", "--what=idle", "--who=Quickshell", "--why=Keep awake", "--mode=block", "sleep", "infinity"]
    }

    // ── Polled state ────────────────────────────────────────────────────────
    property bool nightLight: false
    property bool gameMode: false
    property string powerProfile: ""          // "" when power-profiles-daemon is missing
    property real watts: 0                    // battery draw (or charge rate)
    property bool charging: false
    property bool hasBattery: false

    property int watchers: 0
    function watch() { watchers += 1; refresh() }
    function unwatch() { watchers = Math.max(0, watchers - 1) }
    Timer { interval: 3000; repeat: true; running: root.watchers > 0; onTriggered: root.refresh() }

    function refresh() { if (!poll.running) poll.running = true }
    Process {
        id: poll
        command: ["bash", "-c", `
            pgrep -x hyprsunset >/dev/null && echo night=1 || echo night=0
            [ -f "$HOME/.config/ml4w/settings/gamemode-enabled" ] && echo game=1 || echo game=0
            echo "profile=$(powerprofilesctl get 2>/dev/null)"
            b=/sys/class/power_supply/BAT0
            if [ -d "$b" ]; then
                echo "status=$(cat $b/status 2>/dev/null)"
                if [ -r $b/power_now ]; then echo "uw=$(cat $b/power_now)"
                else echo "uw=$(( $(cat $b/current_now 2>/dev/null || echo 0) * $(cat $b/voltage_now 2>/dev/null || echo 0) / 1000000 ))"; fi
            fi`]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = {}
                for (const l of text.split("\n")) {
                    const i = l.indexOf("=")
                    if (i > 0) v[l.slice(0, i)] = l.slice(i + 1).trim()
                }
                root.nightLight = v.night === "1"
                root.gameMode = v.game === "1"
                root.powerProfile = v.profile || ""
                root.hasBattery = v.status !== undefined
                root.charging = v.status === "Charging" || v.status === "Full"
                root.watts = (parseFloat(v.uw) || 0) / 1e6
            }
        }
    }
    // Re-read shortly after changing something (scripts take a moment).
    Timer { id: soon; interval: 700; onTriggered: root.refresh() }

    function toggleNightLight() {
        nightLight = !nightLight
        Quickshell.execDetached([home + "/.config/ml4w/scripts/ml4w-toggle-hyprsunset"])
        soon.restart()
    }
    function toggleGameMode() {
        gameMode = !gameMode
        Quickshell.execDetached([home + "/.config/hypr/scripts/gamemode.sh"])
        soon.restart()
    }
    function setPowerProfile(p) {
        powerProfile = p
        Quickshell.execDetached(["powerprofilesctl", "set", p])
        soon.restart()
    }

    // ── Presentation ────────────────────────────────────────────────────────
    // For sharing a screen: Do Not Disturb and keep awake on, and optionally
    // every other monitor mirroring one of them. Switching it off puts all of
    // that back as it was: the previous DND / keep-awake state, each monitor's
    // mode, position and scale, and the workspaces on the monitors they came
    // from. Kept in a file, so a shell restart in between still restores it.
    property bool presenting: false
    property string mirrorSource: ""        // the monitor shown everywhere, "" = no mirroring
    property var _saved: null               // { dnd, awake, monitors: [...], workspaces: [...], active: [...] }

    FileView {
        id: stateFile
        path: root.home + "/.cache/ml4w/presentation.json"
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text())
                if (s && s.presenting) {
                    root._saved = s.saved
                    root.mirrorSource = s.mirrorSource || ""
                    root.presenting = true
                    root.keepAwake = true
                }
            } catch (e) {}
        }
    }
    function saveState() {
        stateFile.setText(JSON.stringify({ presenting: presenting, mirrorSource: mirrorSource, saved: _saved }) + "\n")
    }

    function togglePresentation(source) {
        if (presenting) stopPresentation()
        else startPresentation(source !== undefined ? source : defaultSource())
    }

    // The laptop panel when there is one (that is usually what gets shared),
    // otherwise the focused monitor.
    function defaultSource() {
        const names = Quickshell.screens.map(s => s.name)
        if (names.length < 2) return ""
        const laptop = names.find(n => n.startsWith("eDP"))
        return laptop || Corners.focusedScreen() || names[0]
    }

    function startPresentation(source) {
        if (presenting || starting.running) return
        starting.source = source || ""
        starting.running = true
    }
    // Snapshot monitors and workspaces first, then mirror.
    Process {
        id: starting
        property string source: ""
        command: ["bash", "-c", 'echo "{\\"monitors\\": $(hyprctl monitors -j), \\"workspaces\\": $(hyprctl workspaces -j)}"']
        stdout: StdioCollector {
            onStreamFinished: {
                let snap = null
                try { snap = JSON.parse(text) } catch (e) { return }
                const src = starting.source
                root._saved = {
                    dnd: Notifs.dnd,
                    awake: root.keepAwake,
                    monitors: snap.monitors.filter(m => !m.disabled && m.name !== src).map(m => ({
                        name: m.name,
                        mode: m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2),
                        position: m.x + "x" + m.y,
                        scale: m.scale,
                        transform: m.transform
                    })),
                    workspaces: snap.workspaces.filter(w => w.id > 0).map(w => ({ id: w.id, monitor: w.monitor })),
                    active: snap.monitors.map(m => ({ monitor: m.name, id: m.activeWorkspace ? m.activeWorkspace.id : -1 })),
                    focused: (snap.monitors.find(m => m.focused) || { activeWorkspace: { id: -1 } }).activeWorkspace.id
                }
                root.mirrorSource = src
                root.presenting = true
                Notifs.setDnd(true)
                root.keepAwake = true
                if (src !== "") {
                    const lua = root._saved.monitors.map(m =>
                        'hl.monitor({ output = "' + m.name + '", mode = "preferred", position = "auto", scale = "auto", mirror = "' + src + '" })'
                    ).join("; ")
                    if (lua !== "") Quickshell.execDetached(["hyprctl", "eval", lua])
                }
                root.saveState()
            }
        }
    }

    function stopPresentation() {
        if (!presenting) return
        const s = _saved || { dnd: false, awake: false, monitors: [], workspaces: [], active: [] }
        presenting = false
        Notifs.setDnd(s.dnd === true)
        keepAwake = s.awake === true
        if (mirrorSource !== "" && s.monitors.length > 0) {
            const lua = s.monitors.map(m =>
                'hl.monitor({ output = "' + m.name + '", mode = "' + m.mode + '", position = "' + m.position
                + '", scale = ' + m.scale + (m.transform ? ', transform = ' + m.transform : '')
                + ', mirror = "" })'          // (leaving mirror out keeps the monitor mirrored)
            ).join("; ")
            // Workspaces back on the monitors they came from, then each
            // monitor showing the workspace it showed before, and focus back
            // where it was.
            const back = s.workspaces.map(w =>
                'hl.dispatch(hl.dsp.workspace.move({ workspace = "' + w.id + '", monitor = "' + w.monitor + '" }))'
            ).concat(s.active.filter(a => a.id > 0).map(a =>
                'hl.dispatch(hl.dsp.focus({ workspace = "' + a.id + '" }))'
            )).concat(s.focused > 0 ? ['hl.dispatch(hl.dsp.focus({ workspace = "' + s.focused + '" }))'] : []
            ).join("; ")
            Quickshell.execDetached(["bash", "-c", 'hyprctl eval "$1"; sleep 1.2; [ -n "$2" ] && hyprctl eval "$2"', "restore", lua, back])
        }
        mirrorSource = ""
        _saved = null
        saveState()
    }
}
