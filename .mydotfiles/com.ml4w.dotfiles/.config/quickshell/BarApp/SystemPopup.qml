import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    property string currentTab: "Network"
    visible: active

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: popup.active = false }

    // ─── WiFi network list state ───────────────────────────────────────────
    property var wifiNetworks: []       // [{ssid, signal, security, active}]
    property bool wifiScanning: false
    property string wifiConnecting: "" // ssid currently being connected
    property string wifiPassword: ""
    property string wifiPasswordTarget: ""
    property bool showPasswordFor: false

    // ─── Bluetooth device list state ───────────────────────────────────────
    property var btDevices: []          // [{mac, name, connected, paired}]
    property bool btScanning: false

    // ─── Accumulators for multi-line Process output ────────────────────────
    property string _wifiBuf: ""
    property string _btBuf: ""

    // ─── Processes ─────────────────────────────────────────────────────────

    // WiFi scan
    Process {
        id: wifiScanner
        command: ["bash", "-c", "nmcli -t -f SSID,SIGNAL,SECURITY,ACTIVE dev wifi list 2>/dev/null"]
        stdout: SplitParser {
            onRead: {
                popup._wifiBuf += data + "\n"
            }
        }
        onRunningChanged: {
            if (!running) {
                popup.wifiScanning = false
                let lines = popup._wifiBuf.trim().split("\n")
                popup._wifiBuf = ""
                let seen = {}
                let nets = []
                for (let l of lines) {
                    // nmcli -t uses : as delimiter; SSID may contain colons — split on first 3
                    let parts = l.split(":")
                    if (parts.length < 4) continue
                    let ssid = parts.slice(0, parts.length - 3).join(":")
                    let signal = parseInt(parts[parts.length - 3]) || 0
                    let security = parts[parts.length - 2]
                    let active = parts[parts.length - 1].trim() === "yes"
                    if (!ssid || ssid === "--" || seen[ssid]) continue
                    seen[ssid] = true
                    nets.push({ ssid, signal, security, active })
                }
                nets.sort((a, b) => b.signal - a.signal)
                popup.wifiNetworks = nets
            }
        }
    }

    // WiFi connect (open networks)
    Process {
        id: wifiConnector
        onRunningChanged: { if (!running) { popup.wifiConnecting = ""; wifiScanner.running = true } }
    }

    // WiFi disconnect
    Process {
        id: wifiDisconnector
        onRunningChanged: { if (!running) wifiScanner.running = true }
    }

    // WiFi forget
    Process {
        id: wifiForget
        onRunningChanged: { if (!running) wifiScanner.running = true }
    }

    // BT scan
    Process {
        id: btScanner
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read _ mac name; do " +
            "  connected=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Connected: yes'); " +
            "  paired=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Paired: yes'); " +
            "  echo \"$mac|$name|$connected|$paired\"; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: { popup._btBuf += data + "\n" }
        }
        onRunningChanged: {
            if (!running) {
                popup.btScanning = false
                let lines = popup._btBuf.trim().split("\n")
                popup._btBuf = ""
                let devs = []
                for (let l of lines) {
                    let p = l.split("|")
                    if (p.length < 4) continue
                    devs.push({ mac: p[0].trim(), name: p[1].trim(), connected: p[2].trim() === "1", paired: p[3].trim() === "1" })
                }
                popup.btDevices = devs
            }
        }
    }

    // BT connect/disconnect/remove
    Process { id: btAction; onRunningChanged: { if (!running) { btScanner.running = true } } }

    // Generic executor (passed through from bar scope via reference — redefine locally for safety)
    Process {
        id: localExec
        function run(args) { command = args; running = true }
    }

    // Re-poll timer after toggle actions
    Timer {
        id: repollTimer; interval: 800; repeat: false
        onTriggered: { wifiScanner.running = true; btScanner.running = true }
    }

    // Auto-scan when tab switches or popup opens
    onActiveChanged: {
        if (active) {
            if (currentTab === "Network") { popup._wifiBuf = ""; popup.wifiScanning = true; wifiScanner.running = true }
            if (currentTab === "Bluetooth") { popup._btBuf = ""; popup.btScanning = true; btScanner.running = true }
        }
    }
    onCurrentTabChanged: {
        if (!active) return
        if (currentTab === "Network") { popup._wifiBuf = ""; popup.wifiScanning = true; wifiScanner.running = true }
        if (currentTab === "Bluetooth") { popup._btBuf = ""; popup.btScanning = true; btScanner.running = true }
    }

    // ─── Helpers ───────────────────────────────────────────────────────────
    function signalIcon(sig) {
        if (sig >= 75) return "󰤨"
        if (sig >= 50) return "󰤥"
        if (sig >= 25) return "󰤢"
        return "󰤟"
    }

    // ─── Main container ────────────────────────────────────────────────────
    Rectangle {
        id: container
        width: 420; height: 580
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 15
        radius: 30; color: "transparent"; border.color: "transparent"; border.width: 1

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 14

            // ── Tab bar ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 36; radius: 12
                color: Theme.background

                Row {
                    anchors.fill: parent; anchors.margins: 4; spacing: 4

                    Repeater {
                        model: ["Network", "Bluetooth", "Performance"]
                        Rectangle {
                            width: (parent.width - 8) / 3; height: parent.height
                            radius: 9
                            color: popup.currentTab === modelData ? Theme.primary : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData === "Network" ? "󰤨  Network"
                                    : modelData === "Bluetooth" ? "󰂯  Bluetooth"
                                    : "󰻠  System"
                                color: popup.currentTab === modelData ? Theme.background : Theme.primary
                                font.bold: true; font.pixelSize: 11
                                opacity: popup.currentTab === modelData ? 1.0 : 0.6
                            }
                            MouseArea { anchors.fill: parent; onClicked: popup.currentTab = modelData }
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  NETWORK TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Network"
                Layout.fillWidth: true; spacing: 10

                // ── Ethernet section ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 48; radius: 14
                    color: Theme.background
                    visible: sysInfo.connType === "ethernet"

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                        Text { text: "󰈀"; color: Theme.primary; font.pixelSize: 20 }
                        Column {
                            spacing: 1
                            Text { text: "Ethernet"; color: Theme.primary; font.pixelSize: 12; font.weight: Font.Bold }
                            Text { text: "Wired connection active"; color: Theme.primary; opacity: 0.5; font.pixelSize: 10 }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#a6e3a1"
                        }
                        Text { text: "Connected"; color: Theme.primary; opacity: 0.6; font.pixelSize: 10 }
                    }
                }

                // ── WiFi header row ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true

                    Text { text: "󰤨  Wi-Fi"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }

                    // Scan button
                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        Text {
                            anchors.centerIn: parent; text: "󰑓"
                            color: Theme.primary; font.pixelSize: 14
                            opacity: popup.wifiScanning ? 0.3 : 0.8
                        }
                        MouseArea {
                            anchors.fill: parent; enabled: !popup.wifiScanning
                            onClicked: { popup._wifiBuf = ""; popup.wifiScanning = true; wifiScanner.running = true }
                        }
                    }

                    // WiFi toggle
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.wifiRadio ? Theme.primary : "transparent"
                        border.color: Theme.primary; border.width: 2
                        Rectangle {
                            x: sysInfo.wifiRadio ? parent.width - width - 3 : 3
                            y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.wifiRadio ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 180 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                localExec.run(["bash", "-c", sysInfo.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"])
                                repollTimer.restart()
                            }
                        }
                    }
                }

                // ── WiFi network list ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 300; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
                    clip: true

                    // Loading state
                    Text {
                        anchors.centerIn: parent
                        text: popup.wifiScanning ? "Scanning…" : (popup.wifiNetworks.length === 0 ? "No networks found" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.wifiScanning || popup.wifiNetworks.length === 0
                    }

                    ListView {
                        anchors.fill: parent; anchors.margins: 6
                        model: popup.wifiNetworks
                        spacing: 4
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: (popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid) ? 100 : 52
                            radius: 10
                            color: modelData.active
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.0)

                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }

                            // Main row
                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10
                                height: 32; spacing: 10

                                // Signal icon
                                Text {
                                    text: signalIcon(modelData.signal)
                                    color: modelData.active ? Theme.primary : Theme.primary
                                    opacity: modelData.active ? 1.0 : 0.6
                                    font.pixelSize: 16
                                }

                                // SSID + security
                                Column {
                                    spacing: 1; Layout.fillWidth: true
                                    Text {
                                        text: modelData.ssid
                                        color: Theme.primary
                                        font.pixelSize: 12; font.weight: modelData.active ? Font.Bold : Font.Normal
                                        elide: Text.ElideRight; width: parent.width
                                    }
                                    Text {
                                        text: modelData.active ? "Connected" : (modelData.security && modelData.security !== "--" ? "󰌆  " + modelData.security : "Open")
                                        color: Theme.primary
                                        opacity: modelData.active ? 0.8 : 0.4
                                        font.pixelSize: 9
                                    }
                                }

                                // Action buttons
                                Row {
                                    spacing: 6

                                    // Connect / Disconnect
                                    Rectangle {
                                        width: 68; height: 26; radius: 8
                                        color: modelData.active
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                            : Theme.primary
                                        visible: popup.wifiConnecting !== modelData.ssid

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.active ? "Disconnect" : "Connect"
                                            color: modelData.active ? Theme.primary : Theme.background
                                            font.pixelSize: 9; font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (modelData.active) {
                                                    wifiDisconnector.command = ["nmcli", "dev", "disconnect", "wlan0"]
                                                    wifiDisconnector.running = true
                                                } else {
                                                    // Check if we have a saved connection for this SSID
                                                    let sec = modelData.security
                                                    if (!sec || sec === "--") {
                                                        // Open network
                                                        popup.wifiConnecting = modelData.ssid
                                                        wifiConnector.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid]
                                                        wifiConnector.running = true
                                                    } else {
                                                        // Show password field
                                                        popup.wifiPasswordTarget = modelData.ssid
                                                        popup.wifiPassword = ""
                                                        popup.showPasswordFor = true
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Connecting spinner placeholder
                                    Text {
                                        visible: popup.wifiConnecting === modelData.ssid
                                        text: "…"; color: Theme.primary; opacity: 0.5
                                        font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                                    }

                                    // Forget button (only for non-active saved networks)
                                    Rectangle {
                                        width: 26; height: 26; radius: 8
                                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                        Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                wifiForget.command = ["bash", "-c",
                                                    "nmcli connection delete \"" + modelData.ssid + "\" 2>/dev/null || true"]
                                                wifiForget.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Password input row (expands when needed)
                            ColumnLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.topMargin: 54
                                anchors.margins: 10; spacing: 6
                                visible: popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid

                                Rectangle {
                                    Layout.fillWidth: true; height: 28; radius: 8
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                        Text { text: "󰌆"; color: Theme.primary; opacity: 0.5; font.pixelSize: 11 }
                                        Item {
                                            Layout.fillWidth: true; height: 28
                                            Text {
                                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                text: "Password…"; color: Theme.primary; opacity: 0.35; font.pixelSize: 11
                                                visible: pwInput.text.length === 0
                                            }
                                            TextInput {
                                                id: pwInput
                                                anchors.fill: parent
                                                color: Theme.primary; font.pixelSize: 11
                                                echoMode: TextInput.Password
                                                verticalAlignment: TextInput.AlignVCenter
                                                onTextChanged: popup.wifiPassword = text
                                                onAccepted: {
                                                    popup.wifiConnecting = modelData.ssid
                                                    popup.showPasswordFor = false
                                                    wifiConnector.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid, "password", popup.wifiPassword]
                                                    wifiConnector.running = true
                                                }
                                            }
                                        }
                                        // Connect button
                                        Rectangle {
                                            width: 50; height: 22; radius: 6; color: Theme.primary
                                            Text { anchors.centerIn: parent; text: "Join"; color: Theme.background; font.pixelSize: 10; font.weight: Font.Bold }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    popup.wifiConnecting = modelData.ssid
                                                    popup.showPasswordFor = false
                                                    wifiConnector.command = ["nmcli", "dev", "wifi", "connect", modelData.ssid, "password", popup.wifiPassword]
                                                    wifiConnector.running = true
                                                }
                                            }
                                        }
                                        // Cancel
                                        Text {
                                            text: "󰅖"; color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                                            MouseArea { anchors.fill: parent; onClicked: popup.showPasswordFor = false }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Network settings button
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                    border.width: 1; color: "transparent"
                    Text { anchors.centerIn: parent; text: "󰖟  Advanced Network Settings"; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { localExec.run(["kitty", "--class", "floating", "nmtui"]); popup.active = false }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  BLUETOOTH TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Bluetooth"
                Layout.fillWidth: true; spacing: 10

                // BT header
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }

                    // Scan button
                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 14; opacity: popup.btScanning ? 0.3 : 0.8 }
                        MouseArea {
                            anchors.fill: parent; enabled: !popup.btScanning
                            onClicked: { popup._btBuf = ""; popup.btScanning = true; btScanner.running = true }
                        }
                    }

                    // BT power toggle
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.bluetooth ? Theme.primary : "transparent"
                        border.color: Theme.primary; border.width: 2
                        Rectangle {
                            x: sysInfo.bluetooth ? parent.width - width - 3 : 3
                            y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.bluetooth ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 180 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                localExec.run(["bash", "-c", sysInfo.bluetooth ? "bluetoothctl power off" : "bluetoothctl power on"])
                                repollTimer.restart()
                            }
                        }
                    }
                }

                // BT device list
                Rectangle {
                    Layout.fillWidth: true; height: 360; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04); clip: true

                    Text {
                        anchors.centerIn: parent
                        text: popup.btScanning ? "Scanning…" : (!sysInfo.bluetooth ? "Bluetooth is off" : popup.btDevices.length === 0 ? "No paired devices" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.btScanning || !sysInfo.bluetooth || popup.btDevices.length === 0
                    }

                    ListView {
                        anchors.fill: parent; anchors.margins: 6
                        model: popup.btDevices; spacing: 4; clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: ListView.view.width; height: 56; radius: 10
                            color: modelData.connected
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                : "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10

                                // Icon
                                Text {
                                    text: "󰂯"; color: Theme.primary; font.pixelSize: 20
                                    opacity: modelData.connected ? 1.0 : 0.4
                                }

                                // Name + status
                                Column {
                                    spacing: 2; Layout.fillWidth: true
                                    Text {
                                        text: modelData.name || modelData.mac
                                        color: Theme.primary; font.pixelSize: 12
                                        font.weight: modelData.connected ? Font.Bold : Font.Normal
                                        elide: Text.ElideRight; width: parent.width
                                    }
                                    Text {
                                        text: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "")
                                        color: Theme.primary; opacity: 0.45; font.pixelSize: 10
                                    }
                                }

                                // Connect / Disconnect
                                Rectangle {
                                    width: 76; height: 26; radius: 8
                                    color: modelData.connected
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                        : Theme.primary
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.connected ? "Disconnect" : "Connect"
                                        color: modelData.connected ? Theme.primary : Theme.background
                                        font.pixelSize: 9; font.weight: Font.Bold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            let cmd = modelData.connected
                                                ? "bluetoothctl disconnect " + modelData.mac
                                                : "bluetoothctl connect " + modelData.mac
                                            btAction.command = ["bash", "-c", cmd]
                                            btAction.running = true
                                        }
                                    }
                                }

                                // Remove / forget
                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            btAction.command = ["bash", "-c", "bluetoothctl remove " + modelData.mac]
                                            btAction.running = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Bluetooth manager
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                    border.width: 1; color: "transparent"
                    Text { anchors.centerIn: parent; text: "󰂱  Bluetooth Manager"; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { localExec.run(["blueman-manager"]); popup.active = false }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  PERFORMANCE TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Performance"
                Layout.fillWidth: true; spacing: 16

                // ── Three circular gauges ─────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 16

                    component CircleGauge: Item {
                        id: gauge
                        property real value: 0.0       // 0.0–1.0
                        property string label: ""
                        property string icon: ""
                        property color trackColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        property color fillColor: value > 0.85 ? "#e06c75" : Theme.primary

                        width: 96; height: 120

                        Canvas {
                            id: gaugeCanvas
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 88; height: 88

                            property real animValue: 0.0
                            Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }
                            onAnimValueChanged: requestPaint()

                            // Drive animation from gauge.value
                            Component.onCompleted: animValue = gauge.value
                            Connections {
                                target: gauge
                                function onValueChanged() { gaugeCanvas.animValue = gauge.value }
                            }

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var cx = width / 2, cy = height / 2
                                var r = (width - 14) / 2
                                var startAngle = Math.PI * 0.75          // 135°
                                var sweepAngle = Math.PI * 1.5           // 270° arc

                                // Track
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, startAngle, startAngle + sweepAngle, false)
                                ctx.strokeStyle = gauge.trackColor
                                ctx.lineWidth = 8
                                ctx.lineCap = "round"
                                ctx.stroke()

                                // Fill
                                if (animValue > 0) {
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, startAngle, startAngle + sweepAngle * animValue, false)
                                    ctx.strokeStyle = gauge.fillColor
                                    ctx.lineWidth = 8
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }

                                // Tick dot at tip
                                if (animValue > 0.02) {
                                    var tipAngle = startAngle + sweepAngle * animValue
                                    var tx = cx + r * Math.cos(tipAngle)
                                    var ty = cy + r * Math.sin(tipAngle)
                                    ctx.beginPath()
                                    ctx.arc(tx, ty, 4, 0, Math.PI * 2)
                                    ctx.fillStyle = gauge.fillColor
                                    ctx.fill()
                                }
                            }

                            // Center content
                            Column {
                                anchors.centerIn: parent; spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: gauge.icon; color: Theme.primary; font.pixelSize: 16
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(gauge.value * 100) + "%"
                                    color: gauge.fillColor
                                    font.pixelSize: 13; font.weight: Font.Black
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: gauge.label
                            color: Theme.primary; opacity: 0.55; font.pixelSize: 11; font.weight: Font.Medium
                        }
                    }

                    CircleGauge { label: "CPU"; icon: "󰻠"; value: sysInfo.cpuUsage }
                    CircleGauge { label: "Memory"; icon: "󰍛"; value: sysInfo.ramUsage }
                    CircleGauge { label: "Disk"; icon: "󰋊"; value: sysInfo.diskUsage }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.08 }

                // ── Stat rows ─────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8

                    Repeater {
                        model: [
                            { label: "CPU Usage",  icon: "󰻠", value: sysInfo.cpuUsage },
                            { label: "Memory",     icon: "󰍛", value: sysInfo.ramUsage },
                            { label: "Disk (/)",   icon: "󰋊", value: sysInfo.diskUsage }
                        ]

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: modelData.icon + "  " + modelData.label; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(modelData.value * 100) + "%"
                                    color: modelData.value > 0.85 ? "#e06c75" : Theme.primary
                                    font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 5; radius: 3
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                Rectangle {
                                    width: parent.width * modelData.value
                                    height: parent.height; radius: 3
                                    color: modelData.value > 0.85 ? "#e06c75" : Theme.primary
                                    opacity: 0.85
                                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuart } }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.08 }

                // ── Open system monitor ───────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 38; radius: 12; color: Theme.primary
                    Text {
                        anchors.centerIn: parent
                        text: "󰓅  Open System Monitor"
                        color: Theme.background; font.bold: true; font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { localExec.run(["bash", "-c", "~/.config/ml4w/settings/system-monitor.sh"]); popup.active = false }
                    }
                }
            }
        }
    }
}
