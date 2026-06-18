import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Wi-Fi"
    subheading: "Connect to wireless networks and manage saved connections"
    icon: "󰤨"

    // The window sets this true when the page is visible, so we only scan
    // while the user is actually looking at it.
    property bool active: false

    property bool radioOn: true
    property var networks: []
    property bool scanning: false
    property string connecting: ""
    property string passwordTarget: ""

    onActiveChanged: if (active) refresh()

    function refresh() {
        radioReader.running = true
        if (radioOn) { page.scanning = true; scanner._buf = ""; scanner.running = true }
    }

    function signalIcon(sig) {
        if (sig >= 75) return "󰤨"
        if (sig >= 50) return "󰤥"
        if (sig >= 25) return "󰤢"
        return "󰤟"
    }

    // ── Processes ──────────────────────────────────────────────────────────
    Process {
        id: radioReader
        command: ["bash", "-c", "nmcli -t radio wifi 2>/dev/null"]
        stdout: SplitParser { onRead: page.radioOn = (data.trim() === "enabled") }
    }

    Process {
        id: scanner
        property string _buf: ""
        command: ["bash", "-c",
            "SAVED=$(nmcli -t -f NAME con show 2>/dev/null)\n" +
            "nmcli -t -f SSID,SIGNAL,SECURITY,ACTIVE dev wifi list 2>/dev/null | while IFS= read -r line; do\n" +
            "  ssid=$(echo \"$line\" | rev | cut -d: -f4- | rev)\n" +
            "  rest=$(echo \"$line\" | rev | cut -d: -f1-3 | rev)\n" +
            "  signal=$(echo \"$rest\" | cut -d: -f1)\n" +
            "  security=$(echo \"$rest\" | cut -d: -f2)\n" +
            "  active=$(echo \"$rest\" | cut -d: -f3 | tr -d '\\r')\n" +
            "  [ -z \"$ssid\" ] || [ \"$ssid\" = \"--\" ] && continue\n" +
            "  if echo \"$SAVED\" | grep -qxF \"$ssid\"; then saved=yes; else saved=no; fi\n" +
            "  printf '%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$ssid\" \"$signal\" \"$security\" \"$active\" \"$saved\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: scanner._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            page.scanning = false
            let lines = scanner._buf.trim().split("\n")
            scanner._buf = ""
            let seen = {}, nets = []
            for (let l of lines) {
                let p = l.split("\x1f")
                if (p.length < 5) continue
                let ssid = p[0].trim()
                if (!ssid || seen[ssid]) continue
                seen[ssid] = true
                nets.push({ ssid, signal: parseInt(p[1]) || 0, security: p[2].trim(),
                            active: p[3].trim() === "yes", saved: p[4].trim() === "yes" })
            }
            nets.sort((a, b) => b.signal - a.signal)
            page.networks = nets
        }
    }

    Process { id: connector;    onRunningChanged: if (!running) { page.connecting = ""; scanner.running = true } }
    Process { id: disconnector; onRunningChanged: if (!running) scanner.running = true }
    Process { id: forgetter;    onRunningChanged: if (!running) scanner.running = true }
    Process { id: radioToggle;  onRunningChanged: if (!running) page.refresh() }

    // ── UI ───────────────────────────────────────────────────────────────
    StCard {
        StRow {
            icon: "󰤨"
            title: "Wi-Fi"
            subtitle: page.radioOn ? (page.scanning ? "Scanning for networks…" : page.networks.length + " networks in range")
                                   : "Wireless is turned off"
            StIconButton {
                icon: "󰑓"
                busy: page.scanning
                enabled: page.radioOn
                onClicked: { page.scanning = true; scanner._buf = ""; scanner.running = true }
            }
            StToggle {
                checked: page.radioOn
                onToggled: (v) => { radioToggle.command = ["bash", "-c", v ? "nmcli radio wifi on" : "nmcli radio wifi off"]; radioToggle.running = true }
            }
        }
    }

    StCard {
        title: "Networks"
        visible: page.radioOn

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(120, Math.min(420, netList.contentHeight + 12))
            color: "transparent"

            Text {
                anchors.centerIn: parent
                visible: page.networks.length === 0
                text: page.scanning ? "Scanning…" : "No networks found"
                color: Theme.primary
                opacity: 0.4
                font.pixelSize: 13
            }

            ListView {
                id: netList
                anchors.fill: parent
                anchors.margins: 4
                model: page.networks
                spacing: 4
                clip: true
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: (page.passwordTarget === modelData.ssid) ? 96 : 54
                    radius: 11
                    color: modelData.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                         : (rowHover.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06) : "transparent")
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea { id: rowHover; anchors.fill: parent; hoverEnabled: true }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        anchors.topMargin: 11
                        height: 32
                        spacing: 10

                        Text { text: page.signalIcon(modelData.signal); color: Theme.primary; opacity: modelData.active ? 1.0 : 0.6; font.pixelSize: 17 }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Text {
                                text: modelData.ssid
                                color: Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: modelData.active ? Font.Bold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.active ? "Connected"
                                    : modelData.saved ? "󰄬 Saved"
                                    : (modelData.security && modelData.security !== "--") ? "󰌆 " + modelData.security : "Open"
                                color: Theme.primary
                                opacity: modelData.active ? 0.8 : 0.45
                                font.pixelSize: 10
                            }
                        }

                        StButton {
                            text: modelData.active ? "Disconnect" : (page.connecting === modelData.ssid ? "…" : "Connect")
                            accent: !modelData.active
                            implicitHeight: 30
                            onClicked: {
                                if (modelData.active) {
                                    disconnector.command = ["bash", "-c", "nmcli con down id \"" + modelData.ssid + "\" 2>/dev/null || nmcli dev disconnect $(nmcli -t -f DEVICE,TYPE dev | grep wifi | head -1 | cut -d: -f1)"]
                                    disconnector.running = true
                                } else if (modelData.saved || !modelData.security || modelData.security === "--") {
                                    page.connecting = modelData.ssid
                                    connector.command = modelData.saved
                                        ? ["nmcli", "con", "up", "id", modelData.ssid]
                                        : ["nmcli", "dev", "wifi", "connect", modelData.ssid]
                                    connector.running = true
                                } else {
                                    page.passwordTarget = (page.passwordTarget === modelData.ssid) ? "" : modelData.ssid
                                }
                            }
                        }
                        StIconButton {
                            icon: "󰆴"
                            visible: modelData.saved
                            onClicked: { forgetter.command = ["bash", "-c", "nmcli connection delete \"" + modelData.ssid + "\" 2>/dev/null || true"]; forgetter.running = true }
                        }
                    }

                    // Inline password entry for secured networks
                    Rectangle {
                        visible: page.passwordTarget === modelData.ssid
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        height: 32
                        radius: 9
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 6
                            Text { text: "󰌆"; color: Theme.primary; opacity: 0.5; font.pixelSize: 12 }
                            TextField {
                                id: pwField
                                Layout.fillWidth: true
                                placeholderText: "Password…"
                                placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                color: Theme.primary
                                font.pixelSize: 12
                                echoMode: TextInput.Password
                                background: null
                                verticalAlignment: TextInput.AlignVCenter
                                onAccepted: joinBtn.join()
                            }
                            StButton {
                                id: joinBtn
                                text: "Join"
                                accent: true
                                implicitHeight: 26
                                function join() {
                                    page.connecting = modelData.ssid
                                    connector.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid, "password", pwField.text]
                                    connector.running = true
                                    page.passwordTarget = ""
                                }
                                onClicked: join()
                            }
                        }
                    }
                }
            }
        }
    }

    StCard {
        StRow {
            icon: "󰖟"
            title: "Advanced network settings"
            subtitle: "Open the full connection editor (nmtui)"
            clickable: true
            onClicked: Quickshell.execDetached(["kitty", "--class", "dotfiles-floating", "-e", "nmtui"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
