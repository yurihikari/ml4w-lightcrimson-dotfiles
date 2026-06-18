import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Bluetooth"
    subheading: "Pair and manage Bluetooth devices"
    icon: "󰂯"

    property bool active: false
    property bool powered: false
    property bool scanning: false
    property var devices: []

    onActiveChanged: if (active) refresh()

    function refresh() {
        poweredReader.running = true
        if (powered) { page.scanning = true; scanner._buf = ""; scanner.running = true }
    }

    Process {
        id: poweredReader
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: SplitParser { onRead: page.powered = (data.trim() === "on") }
    }

    Process {
        id: scanner
        property string _buf: ""
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read _ mac name; do\n" +
            "  info=$(bluetoothctl info $mac 2>/dev/null)\n" +
            "  c=$(echo \"$info\" | grep -c 'Connected: yes')\n" +
            "  p=$(echo \"$info\" | grep -c 'Paired: yes')\n" +
            "  printf '%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$mac\" \"$name\" \"$c\" \"$p\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: scanner._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            page.scanning = false
            let devs = []
            for (let l of scanner._buf.trim().split("\n")) {
                let p = l.split("\x1f")
                if (p.length < 4) continue
                devs.push({ mac: p[0].trim(), name: p[1].trim(), connected: p[2].trim() === "1", paired: p[3].trim() === "1" })
            }
            devs.sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0))
            page.devices = devs
            scanner._buf = ""
        }
    }

    Process { id: btAction; onRunningChanged: if (!running) scanner.running = true }
    Process { id: powerToggle; onRunningChanged: if (!running) page.refresh() }

    StCard {
        StRow {
            icon: "󰂯"
            title: "Bluetooth"
            subtitle: page.powered ? (page.scanning ? "Scanning…" : page.devices.length + " known devices") : "Bluetooth is off"
            StIconButton {
                icon: "󰑓"
                busy: page.scanning
                enabled: page.powered
                onClicked: { page.scanning = true; scanner._buf = ""; scanner.running = true }
            }
            StToggle {
                checked: page.powered
                onToggled: (v) => { powerToggle.command = ["bash", "-c", v ? "bluetoothctl power on" : "bluetoothctl power off"]; powerToggle.running = true }
            }
        }
    }

    StCard {
        title: "Devices"
        visible: page.powered

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(100, Math.min(420, devList.contentHeight + 12))
            color: "transparent"

            Text {
                anchors.centerIn: parent
                visible: page.devices.length === 0
                text: page.scanning ? "Scanning…" : "No devices found"
                color: Theme.primary; opacity: 0.4; font.pixelSize: 13
            }

            ListView {
                id: devList
                anchors.fill: parent
                anchors.margins: 4
                model: page.devices
                spacing: 4
                clip: true
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: StRow {
                    required property var modelData
                    width: ListView.view.width
                    icon: "󰂯"
                    title: modelData.name || modelData.mac
                    subtitle: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Available")
                    StButton {
                        text: modelData.connected ? "Disconnect" : "Connect"
                        accent: !modelData.connected
                        implicitHeight: 30
                        onClicked: { btAction.command = ["bash", "-c", (modelData.connected ? "bluetoothctl disconnect " : "bluetoothctl connect ") + modelData.mac]; btAction.running = true }
                    }
                    StIconButton {
                        icon: "󰆴"
                        visible: modelData.paired
                        onClicked: { btAction.command = ["bash", "-c", "bluetoothctl remove " + modelData.mac]; btAction.running = true }
                    }
                }
            }
        }
    }

    StCard {
        StRow {
            icon: "󰂱"
            title: "Bluetooth manager"
            subtitle: "Open Blueman for advanced pairing"
            clickable: true
            onClicked: Quickshell.execDetached(["blueman-manager"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
