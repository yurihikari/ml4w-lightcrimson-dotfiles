import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// Power menu (META+X, the bar's power button). A centered modal over a frosted
// full-screen backdrop: a clock header, then the actions as tiles that rise in
// one after another. Reboot and shutdown light up in the error colour so the
// destructive ones read differently.
//
// Keys: left/right (or h/l, Tab) to choose, Enter/Space to confirm, Esc to
// cancel. Hovering a tile also selects it.
BarPopupWindow {
    id: root
    ipcTarget: "bar-power"
    onOpened: {
        root.selectedIndex = 0
        uptimeReader.running = true
    }

    property int selectedIndex: 0
    property var powerActions: [
        { icon: "󰌾", label: "Lock",     action: ["hyprlock"],                             danger: false },
        { icon: "󰤄", label: "Suspend",  action: ["systemctl", "suspend"],                 danger: false },
        { icon: "󰍃", label: "Log Out",  action: ["hyprctl", "dispatch", "hl.dsp.exit()"], danger: false },
        { icon: "󰑓", label: "Reboot",   action: ["systemctl", "reboot"],                  danger: true },
        { icon: "󰐥", label: "Shutdown", action: ["systemctl", "poweroff"],                danger: true }
    ]

    function activate(i) {
        Sys.run(root.powerActions[i].action)
        root.active = false
    }

    // ── Header data ─────────────────────────────────────────────────────────
    SystemClock { id: clock; precision: SystemClock.Minutes }

    property string uptimeStr: ""
    readonly property string userName: Quickshell.env("USER") || ""
    Process {
        id: uptimeReader
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = Math.floor(parseFloat(this.text.split(" ")[0]) || 0)
                const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
                root.uptimeStr = d > 0 ? d + "d " + h + "h " + m + "m" : (h > 0 ? h + "h " + m + "m" : m + "m")
            }
        }
    }

    // ── Keyboard ────────────────────────────────────────────────────────────
    FocusScope {
        anchors.fill: parent
        focus: root.active
        Keys.onPressed: (event) => {
            let n = root.powerActions.length
            if (event.key === Qt.Key_Escape) {
                root.active = false; event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.selectedIndex = (root.selectedIndex - 1 + n) % n; event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) {
                root.selectedIndex = (root.selectedIndex + 1) % n; event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.activate(root.selectedIndex); event.accepted = true
            }
        }
    }

    // ── Frosted backdrop ────────────────────────────────────────────────────
    // 0.8 so Hyprland blurs everything behind it (the quickshell layer rule).
    Rectangle {
        anchors.fill: parent
        color: Theme.background
        opacity: root.active ? 0.8 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: root.active ? 320 : 220
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !root.active) root.isAnimating = false
            }
        }
    }

    // ── Content ─────────────────────────────────────────────────────────────
    ColumnLayout {
        id: content
        anchors.centerIn: parent
        spacing: 0

        // Header
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            opacity: root.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.active ? 380 : 160; easing.type: Easing.OutCubic } }
            transform: Translate {
                y: root.active ? 0 : -14
                Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 76
                font.weight: Font.Light
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                color: Theme.primary
                opacity: 0.75
                font.family: Theme.fontFamily
                font.pixelSize: 15
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                visible: text !== ""
                text: [root.uptimeStr !== "" ? "up " + root.uptimeStr : "", root.userName].filter(s => s !== "").join("  ·  ")
                color: Theme.primary
                opacity: 0.45
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }

        // Actions
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 56
            spacing: 22

            // One tile per action
            Repeater {
                model: root.powerActions
                delegate: Item {
                    id: tile
                    required property int index
                    required property var modelData
                    readonly property int idx: index
                    readonly property string icon: modelData.icon
                    readonly property string label: modelData.label
                    readonly property bool danger: modelData.danger
                    readonly property bool selected: root.selectedIndex === idx
                    readonly property color accent: danger ? Theme.error : Theme.primary
                    readonly property color accentText: danger ? Theme.on_error : Theme.on_primary

                    implicitWidth: 104
                    implicitHeight: face.height + 14 + caption.implicitHeight

                    // Staggered entrance: rise and fade in one after another.
                    opacity: root.active ? 1 : 0
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: root.active ? 60 + tile.idx * 45 : 0 }
                            NumberAnimation { duration: root.active ? 300 : 160; easing.type: Easing.OutCubic }
                        }
                }
                transform: Translate {
                    y: root.active ? 0 : 26
                    Behavior on y {
                        SequentialAnimation {
                            PauseAnimation { duration: root.active ? 60 + tile.idx * 45 : 0 }
                            NumberAnimation { duration: root.active ? 460 : 160; easing.type: Easing.OutExpo }
                        }
                    }
                }

                Rectangle {
                    id: face
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 88; height: 88
                    radius: 28
                    color: tile.selected ? tile.accent : Theme.withAlpha(tile.accent, tileMouse.containsMouse ? 0.16 : 0.08)
                    scale: tileMouse.pressed ? 0.93 : (tile.selected ? 1.06 : 1.0)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: tile.icon
                        color: tile.selected ? tile.accentText : tile.accent
                        font.pixelSize: 32
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }

                Text {
                    id: caption
                    anchors.top: face.bottom
                    anchors.topMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.label
                    color: tile.selected ? tile.accent : Theme.primary
                    opacity: tile.selected ? 1 : 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: face
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Keep the keyboard selection in sync with the mouse
                    onContainsMouseChanged: if (containsMouse) root.selectedIndex = tile.idx
                    onClicked: root.activate(tile.idx)
                }
                }
            }
        }

        // Keyboard hint
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 44
            text: "←  →  choose    ·    Enter  confirm    ·    Esc  cancel"
            color: Theme.primary
            opacity: root.active ? 0.4 : 0
            Behavior on opacity { NumberAnimation { duration: root.active ? 600 : 150 } }
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}
