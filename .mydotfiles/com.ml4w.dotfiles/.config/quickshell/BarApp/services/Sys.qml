pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Single source of truth for everything the bar polls: audio, brightness,
// battery, network, bluetooth, performance, keyboard layout, the active media
// player and SwayNC state. One shared engine for all monitors (the bar is
// instantiated per-screen via Variants, but the data is identical everywhere).
//
// Popups read these properties directly (e.g. Sys.volValue, Sys.activePlayer)
// instead of reaching into the bar window through QML's context chain.
Singleton {
    id: root

    // ── Audio / brightness ──────────────────────────────────────────────────
    property real volValue: 0.0
    property bool isMuted: false
    property real micValue: 0.0
    property bool isMicMuted: false
    property real briValue: 0.0

    // ── Battery / network / bluetooth ───────────────────────────────────────
    property string bat: "0%"
    property int batLevel: 0
    property bool batCharging: false
    property string wifi: ""
    property bool wifiRadio: false
    property string connType: "none"
    property bool bluetooth: false
    property bool hasBattery: true

    // ── Performance ─────────────────────────────────────────────────────────
    property real cpuUsage: 0.0
    property real ramUsage: 0.0
    property real diskUsage: 0.0

    // ── Keyboard layout ─────────────────────────────────────────────────────
    property string kbLayout: "US"
    property string kbVariant: ""

    // ── OSD coordination ────────────────────────────────────────────────────
    // While an OSD is showing for a given channel the matching poller stops
    // overwriting its value, so the on-screen slider reflects the user's input.
    property string activeOSD: ""

    // ── Hyprland clients (for workspace app icons) ──────────────────────────
    property var hyprClients: []
    property string _clientsBuf: ""

    // ── Notifications ───────────────────────────────────────────────────────
    property string swayncState: "none"

    // ── Media (native MPRIS) ────────────────────────────────────────────────
    property var activePlayer: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // ── Fire-and-forget command runner ──────────────────────────────────────
    function run(args) { Quickshell.execDetached(args) }

    // ── Icon helpers ────────────────────────────────────────────────────────
    function batteryIcon(level, charging) {
        if (charging) return "󰂄"
        if (level >= 90) return "󰁹"
        if (level >= 80) return "󰂁"
        if (level >= 70) return "󰂀"
        if (level >= 60) return "󰁿"
        if (level >= 50) return "󰁾"
        if (level >= 40) return "󰁽"
        if (level >= 30) return "󰁼"
        if (level >= 20) return "󰁻"
        if (level >= 10) return "󰁺"
        return "󰂎"
    }

    function notificationIcon(state) {
        if (state.includes("notification")) return "󰂠"
        return state.includes("dnd") ? "󰂛" : "󰂚"
    }

    // ════════════════════════════════════════════════════════════════════════
    //  POLLERS
    // ════════════════════════════════════════════════════════════════════════
    Process {
        id: clientsGetter; running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: SplitParser { onRead: data => root._clientsBuf += data }
        onRunningChanged: {
            if (running) {
                root._clientsBuf = ""
            } else {
                try { root.hyprClients = JSON.parse(root._clientsBuf) }
                catch(e) {}
                root._clientsBuf = ""
            }
        }
    }

    Process {
        id: volGetter; running: true
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => {
                if (root.activeOSD !== "vol") {
                    let out = data.trim(); root.isMuted = out.includes("[MUTED]")
                    let m = out.match(/[0-9.]+/)
                    if (m) root.volValue = parseFloat(m[0])
                }
            }
        }
    }

    Process {
        id: micGetter; running: true
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@"]
        stdout: SplitParser {
            onRead: data => {
                if (root.activeOSD !== "mic") {
                    let out = data.trim(); root.isMicMuted = out.includes("[MUTED]")
                    let m = out.match(/[0-9.]+/)
                    if (m) root.micValue = parseFloat(m[0])
                }
            }
        }
    }

    Process {
        id: briGetter; running: true
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{print $4}' | tr -d % || echo '0'"]
        stdout: SplitParser {
            onRead: data => {
                if (root.activeOSD !== "bri") {
                    root.briValue = (parseFloat(data.trim()) || 0) / 100
                }
            }
        }
    }

    Process {
        id: kbGetter; running: true
        command: ["bash", "-c", "l=$(grep -E 'kb_layout\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); v=$(grep -E 'kb_variant\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); echo \"${l:-US}|${v}\""]
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("|")
                root.kbLayout = (parts[0] || "US").toUpperCase()
                root.kbVariant = parts[1] || ""
            }
        }
    }

    Process {
        id: batGetter; running: true
        command: ["bash", "-c", "cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null); st=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null); if [ -z \"$cap\" ]; then echo 'none'; else echo \"$cap|$st\"; fi"]
        stdout: SplitParser {
            onRead: data => {
                let out = data.trim()
                if (out === "none") { root.hasBattery = false }
                else {
                    let parts = out.split("|")
                    root.batLevel = parseInt(parts[0]) || 0
                    root.bat = (parseInt(parts[0]) || 0) + "%"
                    root.batCharging = (parts[1] === "Charging" || parts[1] === "Full")
                }
            }
        }
    }

    Process {
        id: wifiGetter; running: true
        command: ["bash", "-c", "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected' | head -1); wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2); if [ -n \"$eth\" ]; then connType=\"ethernet\"; elif [ -n \"$wifi\" ]; then connType=\"wifi\"; else connType=\"none\"; fi; echo \"$connType:$wifi\""]
        stdout: SplitParser { onRead: data => { let parts = data.trim().split(":"); root.connType = parts[0]; root.wifi = parts[1] || "" } }
    }

    Process {
        id: wifiRadioGetter; running: true
        command: ["bash", "-c", "nmcli radio wifi"]
        stdout: SplitParser { onRead: data => { root.wifiRadio = data.trim() === "enabled" } }
    }

    Process {
        id: btGetter; running: true
        command: ["bash", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo 'on' || echo 'off'"]
        stdout: SplitParser { onRead: data => { root.bluetooth = (data.trim() === "on") } }
    }

    Process {
        id: perfGetter; running: true
        command: ["bash", "-c", "cpu=$(top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8}'); mem=$(free | grep Mem | awk '{print $3/$2 * 100.0}'); disk=$(df / --output=pcent | tail -1 | tr -dc '0-9'); echo \"$cpu|$mem|$disk\""]
        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split("|")
                if (parts.length >= 3) {
                    root.cpuUsage = (parseFloat(parts[0]) || 0) / 100
                    root.ramUsage = (parseFloat(parts[1]) || 0) / 100
                    root.diskUsage = (parseFloat(parts[2]) || 0) / 100
                }
            }
        }
    }

    Process {
        id: swayncWatcher; running: true
        command: ["swaync-client", "-swb"]
        stdout: SplitParser { onRead: data => { try { let json = JSON.parse(data.trim()); root.swayncState = json.alt } catch (e) {} } }
    }

    // ── Refresh timers ──────────────────────────────────────────────────────
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: {
            batGetter.running = true; wifiGetter.running = true; btGetter.running = true; perfGetter.running = true
            volGetter.running = true; micGetter.running = true; briGetter.running = true; kbGetter.running = true
            clientsGetter.running = true
        }
    }

    // Faster refresh for clients so workspace icons feel responsive
    Timer { interval: 1500; running: true; repeat: true; onTriggered: clientsGetter.running = true }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: wifiRadioGetter.running = true }

    // Keep the active player tracked as players come and go.
    Connections {
        target: Mpris.players
        function onValuesChanged() {
            if (Mpris.players.values.length > 0) {
                let found = Mpris.players.values.some(p => p === root.activePlayer)
                if (!found) root.activePlayer = Mpris.players.values[0]
            } else { root.activePlayer = null }
        }
    }

    // Drive position updates while something is playing.
    Timer {
        interval: 1000; repeat: true
        running: root.activePlayer !== null && root.activePlayer.playbackState === MprisPlaybackState.Playing
        onTriggered: { if (root.activePlayer) root.activePlayer.positionChanged() }
    }
}
