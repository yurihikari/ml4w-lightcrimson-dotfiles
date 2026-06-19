import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Power"
    subheading: "Power profile, battery and session"
    icon: "󰂄"

    property bool active: false
    property string profile: "balanced"
    property bool hasProfiles: true
    property int batteryPct: -1
    property bool charging: false
    property bool hasBattery: false
    property bool tuxedo: false
    // Mirrors the ml4w sidebar / SystemPopup state: presence of the
    // gamemode-enabled marker file means game mode is on.
    property bool gamemode: false

    onActiveChanged: if (active) refresh()

    function refresh() { profileReader.running = true; batteryReader.running = true; tuxedoDetector.running = true; gamemodeReader.running = true }

    Process {
        id: gamemodeReader
        command: ["bash", "-c", "test -f \"$HOME/.config/ml4w/settings/gamemode-enabled\" && echo 1 || echo 0"]
        stdout: SplitParser { onRead: data => page.gamemode = (data.trim() === "1") }
    }
    // Runs the shared ml4w gamemode script (toggles the marker + hyprctl), then
    // re-reads the state so the switch reflects reality.
    Process {
        id: gamemodeToggle
        command: ["bash", "-c", "$HOME/.config/hypr/scripts/gamemode.sh"]
        onRunningChanged: if (!running) gamemodeReader.running = true
    }
    // Catch external changes (sidebar / SystemPopup) while the page is open.
    Timer { interval: 2000; repeat: true; running: page.active; onTriggered: gamemodeReader.running = true }

    Process {
        id: tuxedoDetector
        command: ["bash", "-c", "command -v tuxedo-control-center >/dev/null 2>&1 || [ -d /opt/tuxedo-control-center ] && echo yes || echo no"]
        stdout: SplitParser { onRead: page.tuxedo = (data.trim() === "yes") }
    }

    Timer { interval: 5000; repeat: true; running: page.active; onTriggered: batteryReader.running = true }

    readonly property var profileOptions: [
        { value: "power-saver", label: "Saver",       icon: "󰌪" },
        { value: "balanced",    label: "Balanced",    icon: "󰾅" },
        { value: "performance", label: "Performance", icon: "󰓅" }
    ]

    Process {
        id: profileReader
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || echo NONE"]
        stdout: SplitParser {
            onRead: {
                let v = data.trim()
                if (v === "NONE") page.hasProfiles = false
                else { page.hasProfiles = true; page.profile = v }
            }
        }
    }

    Process { id: profileSetter; onRunningChanged: if (!running) profileReader.running = true }

    Process {
        id: batteryReader
        property string _buf: ""
        command: ["bash", "-c",
            "for b in /sys/class/power_supply/BAT*; do [ -d \"$b\" ] || continue;\n" +
            "  echo \"pct=$(cat $b/capacity 2>/dev/null)\"; echo \"st=$(cat $b/status 2>/dev/null)\"; break; done"
        ]
        stdout: SplitParser { onRead: batteryReader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let found = false
            for (let l of batteryReader._buf.trim().split("\n")) {
                let i = l.indexOf("="); if (i < 1) continue
                let k = l.substring(0, i), v = l.substring(i + 1).trim()
                if (k === "pct" && v !== "") { page.batteryPct = parseInt(v); found = true }
                else if (k === "st") page.charging = (v === "Charging")
            }
            page.hasBattery = found
            batteryReader._buf = ""
        }
    }

    Process { id: sessionAction; function run(c) { command = ["bash", "-c", c]; running = true } }

    // ── TUXEDO Control Center (takes over power management on TUXEDO laptops) ─
    StCard {
        title: "Power profile"
        visible: page.tuxedo
        StRow {
            icon: "󰓅"
            title: "TUXEDO Control Center"
            subtitle: "Power profiles and fan curves are managed by TUXEDO on this device"
            clickable: true
            onClicked: Quickshell.execDetached(["bash", "-c", "tuxedo-control-center || gtk-launch tuxedo-control-center"])
            StButton {
                text: "Open"
                accent: true
                icon: "󰜎"
                implicitHeight: 30
                onClicked: Quickshell.execDetached(["bash", "-c", "tuxedo-control-center || gtk-launch tuxedo-control-center"])
            }
        }
    }

    // ── Power profile (power-profiles-daemon) ────────────────────────────
    StCard {
        title: "Power profile"
        visible: page.hasProfiles && !page.tuxedo
        StRow {
            icon: "󰓅"
            title: "Mode"
            subtitle: "Balance performance against energy use"
            StSegmented {
                implicitWidth: 280
                model: page.profileOptions
                current: page.profile
                onSelected: (v) => { profileSetter.command = ["bash", "-c", "powerprofilesctl set " + v]; profileSetter.running = true }
            }
        }
    }

    // ── Game mode ───────────────────────────────────────────────────────
    StCard {
        title: "Performance"
        StRow {
            icon: "󰊴"
            title: "Game mode"
            subtitle: "Disable animations and blur for maximum performance"
            StToggle {
                controlled: true
                checked: page.gamemode
                onToggled: gamemodeToggle.running = true
            }
        }
    }

    // ── Battery ─────────────────────────────────────────────────────────
    StCard {
        title: "Battery"
        visible: page.hasBattery
        StRow {
            icon: page.charging ? "󰂄" : (page.batteryPct > 60 ? "󰂁" : page.batteryPct > 25 ? "󰁾" : "󰂃")
            title: page.batteryPct + "%"
            subtitle: page.charging ? "Charging" : "On battery"
            Rectangle {
                width: 120; height: 12; radius: 6
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, page.batteryPct / 100))
                    height: parent.height; radius: 6
                    color: page.batteryPct <= 20 && !page.charging ? "#e06c75" : Theme.primary
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }
        }
    }

    // ── Session ─────────────────────────────────────────────────────────
    StCard {
        title: "Session"
        StRow {
            icon: "󰍃"
            title: "Power menu"
            subtitle: "Open the full power menu"
            clickable: true
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            StButton { Layout.fillWidth: true; text: "Lock";      icon: "󰌾"; onClicked: sessionAction.run("loginctl lock-session || hyprlock") }
            StButton { Layout.fillWidth: true; text: "Suspend";   icon: "󰒲"; onClicked: sessionAction.run("systemctl suspend") }
            StButton { Layout.fillWidth: true; text: "Log out";   icon: "󰍃"; onClicked: sessionAction.run("hyprctl dispatch exit") }
            StButton { Layout.fillWidth: true; text: "Restart";   icon: "󰜉"; onClicked: sessionAction.run("systemctl reboot") }
            StButton { Layout.fillWidth: true; text: "Power off"; icon: "󰐥"; dangerous: true; onClicked: sessionAction.run("systemctl poweroff") }
        }
    }
}
