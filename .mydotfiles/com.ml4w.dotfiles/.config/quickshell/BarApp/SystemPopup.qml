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

    // ─── WiFi ──────────────────────────────────────────────────────────────
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string wifiConnecting: ""
    property string wifiPassword: ""
    property string wifiPasswordTarget: ""
    property bool showPasswordFor: false

    // ─── Bluetooth ─────────────────────────────────────────────────────────
    property var btDevices: []
    property bool btScanning: false

    // ─── Gamemode ──────────────────────────────────────────────────────────
    // No file writes — just hyprctl dispatches at runtime.
    property bool gamemodeActive: false

    // ─── Power profile ─────────────────────────────────────────────────────
    property string powerProfile: "balanced"   // balanced | performance | power-saver
    property bool tuxedoInstalled: false

    // ─── Accumulators ──────────────────────────────────────────────────────
    property string _wifiBuf: ""
    property string _btBuf: ""

    // ═══════════════════════════════════════════════════════════════════════
    //  PROCESSES
    // ═══════════════════════════════════════════════════════════════════════

    Process {
        id: wifiScanner
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
        stdout: SplitParser { onRead: { popup._wifiBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                popup.wifiScanning = false
                let lines = popup._wifiBuf.trim().split("\n")
                popup._wifiBuf = ""
                let seen = {}, nets = []
                for (let l of lines) {
                    let p = l.split("\x1f")
                    if (p.length < 5) continue
                    let ssid = p[0].trim()
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    nets.push({ ssid, signal: parseInt(p[1])||0, security: p[2].trim(),
                                active: p[3].trim()==="yes", saved: p[4].trim()==="yes" })
                }
                nets.sort((a,b) => b.signal - a.signal)
                popup.wifiNetworks = nets
            }
        }
    }

    Process { id: wifiConnector;   onRunningChanged: { if (!running) { popup.wifiConnecting=""; wifiScanner.running=true } } }
    Process { id: wifiDisconnector; onRunningChanged: { if (!running) wifiScanner.running=true } }
    Process { id: wifiForget;       onRunningChanged: { if (!running) wifiScanner.running=true } }

    Process {
        id: btScanner
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read _ mac name; do\n" +
            "  connected=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Connected: yes')\n" +
            "  paired=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Paired: yes')\n" +
            "  echo \"$mac|$name|$connected|$paired\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: { popup._btBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                popup.btScanning = false
                let lines = popup._btBuf.trim().split("\n"); popup._btBuf = ""
                let devs = []
                for (let l of lines) {
                    let p = l.split("|")
                    if (p.length < 4) continue
                    devs.push({ mac: p[0].trim(), name: p[1].trim(),
                                connected: p[2].trim()==="1", paired: p[3].trim()==="1" })
                }
                popup.btDevices = devs
            }
        }
    }

    Process { id: btAction; onRunningChanged: { if (!running) btScanner.running=true } }

    Process {
        id: localExec
        function run(args) { command = args; running = true }
    }

    // Gamemode: toggle blur and animations via hyprctl keyword (no file writes)
    Process {
        id: gamemodeExec
        function apply(enable) {
            // enable = true  → GAME MODE ON  → disable blur + animations
            // enable = false → GAME MODE OFF → restore blur + animations
            let blur     = enable ? "0" : "1"
            let anim     = enable ? "0" : "1"
            let rounding = enable ? "0" : "12"
            command = ["bash", "-c",
                "hyprctl keyword decoration:blur:enabled "      + blur     + "\n" +
                "hyprctl keyword animations:enabled "           + anim     + "\n" +
                "hyprctl keyword decoration:rounding "          + rounding + "\n" +
                "hyprctl keyword decoration:drop_shadow "       + blur     + "\n"
            ]
            running = true
        }
    }

    // Power profile: read current profile on open
    Process {
        id: powerProfileReader
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo balanced"]
        stdout: SplitParser {
            onRead: {
                let p = data.trim()
                if (p === "performance" || p === "power-saver" || p === "balanced") popup.powerProfile = p
            }
        }
    }

    Process {
        id: powerProfileSetter
        function set(profile) {
            command = ["bash", "-c", "powerprofilesctl set " + profile + " 2>/dev/null || true"]
            running = true
        }
    }

    // Detect tuxedo-control-center
    Process {
        id: tuxedoDetector
        running: true
        command: ["bash", "-c", "command -v tuxedo-control-center &>/dev/null && echo yes || echo no"]
        stdout: SplitParser {
            onRead: { popup.tuxedoInstalled = data.trim() === "yes" }
        }
    }

    Timer { id: repollTimer; interval: 800; repeat: false; onTriggered: { wifiScanner.running=true; btScanner.running=true } }

    onActiveChanged: {
        if (active) {
            if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
            if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
            if (currentTab === "Performance") { powerProfileReader.running=true }
        }
    }
    onCurrentTabChanged: {
        if (!active) return
        if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
        if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
        if (currentTab === "Performance") { powerProfileReader.running=true }
    }

    function signalIcon(sig) {
        if (sig >= 75) return "󰤨"
        if (sig >= 50) return "󰤥"
        if (sig >= 25) return "󰤢"
        return "󰤟"
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONTAINER
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: container
        width: 420; height: 580
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 15
        radius: 30; color: "transparent"

        Rectangle {
            anchors.fill: parent; color: Theme.background; border.color: Theme.primary
            border.width: 2; radius: 30; opacity: 0.8
        }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 14

            // ── Tab bar ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 36; radius: 12; color: Theme.background
                Row {
                    anchors.fill: parent; anchors.margins: 4; spacing: 4
                    Repeater {
                        model: ["Network", "Bluetooth", "Performance"]
                        Rectangle {
                            width: (parent.width - 8) / 3; height: parent.height; radius: 9
                            color: popup.currentTab === modelData ? Theme.primary : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData === "Network"   ? "󰤨  Network"
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

                Rectangle {
                    Layout.fillWidth: true; height: 48; radius: 14; color: Theme.background
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
                        Rectangle { width: 8; height: 8; radius: 4; color: "#a6e3a1" }
                        Text { text: "Connected"; color: Theme.primary; opacity: 0.6; font.pixelSize: 10 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰤨  Wi-Fi"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 14; opacity: popup.wifiScanning ? 0.3 : 0.8 }
                        MouseArea {
                            anchors.fill: parent; enabled: !popup.wifiScanning
                            onClicked: { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
                        }
                    }
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.wifiRadio ? Theme.primary : "transparent"
                        border.color: Theme.primary; border.width: 2
                        Rectangle {
                            x: sysInfo.wifiRadio ? parent.width - width - 3 : 3; y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.wifiRadio ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 180 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { localExec.run(["bash", "-c", sysInfo.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"]); repollTimer.restart() }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 300; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04); clip: true

                    Text {
                        anchors.centerIn: parent
                        text: popup.wifiScanning ? "Scanning…" : (popup.wifiNetworks.length === 0 ? "No networks found" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.wifiScanning || popup.wifiNetworks.length === 0
                    }

                    ListView {
                        anchors.fill: parent; anchors.margins: 6
                        model: popup.wifiNetworks; spacing: 4; clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: (popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid) ? 100 : 52
                            radius: 10
                            color: modelData.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }

                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10; height: 32; spacing: 10

                                Text { text: signalIcon(modelData.signal); color: Theme.primary; opacity: modelData.active ? 1.0 : 0.6; font.pixelSize: 16 }
                                Column {
                                    spacing: 1; Layout.fillWidth: true
                                    Text { text: modelData.ssid; color: Theme.primary; font.pixelSize: 12; font.weight: modelData.active ? Font.Bold : Font.Normal; elide: Text.ElideRight; width: parent.width }
                                    Text {
                                        text: modelData.active ? "Connected" : modelData.saved ? "󰄬  Saved" : (modelData.security && modelData.security !== "--") ? "󰌆  " + modelData.security : "Open"
                                        color: Theme.primary; opacity: modelData.active ? 0.8 : 0.4; font.pixelSize: 9
                                    }
                                }
                                Row {
                                    spacing: 6
                                    Rectangle {
                                        width: 68; height: 26; radius: 8
                                        color: modelData.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Theme.primary
                                        visible: popup.wifiConnecting !== modelData.ssid
                                        Text { anchors.centerIn: parent; text: modelData.active ? "Disconnect" : "Connect"; color: modelData.active ? Theme.primary : Theme.background; font.pixelSize: 9; font.weight: Font.Bold }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (modelData.active) {
                                                    wifiDisconnector.command = ["nmcli","dev","disconnect","wlan0"]; wifiDisconnector.running = true
                                                } else if (modelData.saved) {
                                                    popup.wifiConnecting = modelData.ssid; wifiConnector.command = ["nmcli","con","up",modelData.ssid]; wifiConnector.running = true
                                                } else if (!modelData.security || modelData.security === "--") {
                                                    popup.wifiConnecting = modelData.ssid; wifiConnector.command = ["nmcli","dev","wifi","connect",modelData.ssid]; wifiConnector.running = true
                                                } else {
                                                    popup.wifiPasswordTarget = modelData.ssid; popup.wifiPassword = ""; popup.showPasswordFor = true
                                                }
                                            }
                                        }
                                    }
                                    Text { visible: popup.wifiConnecting === modelData.ssid; text: "…"; color: Theme.primary; opacity: 0.5; font.pixelSize: 12 }
                                    Rectangle {
                                        width: 26; height: 26; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                        Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                        MouseArea { anchors.fill: parent; onClicked: { wifiForget.command=["bash","-c","nmcli connection delete \""+modelData.ssid+"\" 2>/dev/null||true"]; wifiForget.running=true } }
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.topMargin: 54; anchors.margins: 10; spacing: 6
                                visible: popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid
                                Rectangle {
                                    Layout.fillWidth: true; height: 28; radius: 8
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                        Text { text: "󰌆"; color: Theme.primary; opacity: 0.5; font.pixelSize: 11 }
                                        Item {
                                            Layout.fillWidth: true; height: 28
                                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Password…"; color: Theme.primary; opacity: 0.35; font.pixelSize: 11; visible: pwInput.text.length === 0 }
                                            TextInput {
                                                id: pwInput; anchors.fill: parent; color: Theme.primary; font.pixelSize: 11
                                                echoMode: TextInput.Password; verticalAlignment: TextInput.AlignVCenter
                                                onTextChanged: popup.wifiPassword = text
                                                onAccepted: { popup.wifiConnecting=modelData.ssid; popup.showPasswordFor=false; wifiConnector.command=["nmcli","dev","wifi","connect",modelData.ssid,"password",popup.wifiPassword]; wifiConnector.running=true }
                                            }
                                        }
                                        Rectangle {
                                            width: 50; height: 22; radius: 6; color: Theme.primary
                                            Text { anchors.centerIn: parent; text: "Join"; color: Theme.background; font.pixelSize: 10; font.weight: Font.Bold }
                                            MouseArea { anchors.fill: parent; onClicked: { popup.wifiConnecting=modelData.ssid; popup.showPasswordFor=false; wifiConnector.command=["nmcli","dev","wifi","connect",modelData.ssid,"password",popup.wifiPassword]; wifiConnector.running=true } }
                                        }
                                        Text { text: "󰅖"; color: Theme.primary; opacity: 0.4; font.pixelSize: 12; MouseArea { anchors.fill: parent; onClicked: popup.showPasswordFor=false } }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1; color: "transparent"
                    Text { anchors.centerIn: parent; text: "󰖟  Advanced Network Settings"; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                    MouseArea { anchors.fill: parent; onClicked: { localExec.run(["kitty","--class","floating","nmtui"]); popup.active=false } }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  BLUETOOTH TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Bluetooth"
                Layout.fillWidth: true; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 28; height: 28; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 14; opacity: popup.btScanning ? 0.3 : 0.8 }
                        MouseArea { anchors.fill: parent; enabled: !popup.btScanning; onClicked: { popup._btBuf=""; popup.btScanning=true; btScanner.running=true } }
                    }
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.bluetooth ? Theme.primary : "transparent"; border.color: Theme.primary; border.width: 2
                        Rectangle {
                            x: sysInfo.bluetooth ? parent.width - width - 3 : 3; y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.bluetooth ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 180 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { localExec.run(["bash","-c",sysInfo.bluetooth?"bluetoothctl power off":"bluetoothctl power on"]); repollTimer.restart() } }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 360; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04); clip: true
                    Text {
                        anchors.centerIn: parent
                        text: popup.btScanning ? "Scanning…" : (!sysInfo.bluetooth ? "Bluetooth is off" : popup.btDevices.length===0 ? "No paired devices" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.btScanning || !sysInfo.bluetooth || popup.btDevices.length===0
                    }
                    ListView {
                        anchors.fill: parent; anchors.margins: 6; model: popup.btDevices; spacing: 4; clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            width: ListView.view.width; height: 56; radius: 10
                            color: modelData.connected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                Text { text: "󰂯"; color: Theme.primary; font.pixelSize: 20; opacity: modelData.connected ? 1.0 : 0.4 }
                                Column {
                                    spacing: 2; Layout.fillWidth: true
                                    Text { text: modelData.name||modelData.mac; color: Theme.primary; font.pixelSize: 12; font.weight: modelData.connected?Font.Bold:Font.Normal; elide: Text.ElideRight; width: parent.width }
                                    Text { text: modelData.connected?"Connected":(modelData.paired?"Paired":""); color: Theme.primary; opacity: 0.45; font.pixelSize: 10 }
                                }
                                Rectangle {
                                    width: 76; height: 26; radius: 8
                                    color: modelData.connected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Theme.primary
                                    Text { anchors.centerIn: parent; text: modelData.connected?"Disconnect":"Connect"; color: modelData.connected?Theme.primary:Theme.background; font.pixelSize: 9; font.weight: Font.Bold }
                                    MouseArea { anchors.fill: parent; onClicked: { btAction.command=["bash","-c",(modelData.connected?"bluetoothctl disconnect ":"bluetoothctl connect ")+modelData.mac]; btAction.running=true } }
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                    MouseArea { anchors.fill: parent; onClicked: { btAction.command=["bash","-c","bluetoothctl remove "+modelData.mac]; btAction.running=true } }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1; color: "transparent"
                    Text { anchors.centerIn: parent; text: "󰂱  Bluetooth Manager"; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                    MouseArea { anchors.fill: parent; onClicked: { localExec.run(["blueman-manager"]); popup.active=false } }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  PERFORMANCE TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Performance"
                Layout.fillWidth: true; spacing: 16

                // ── Circle gauges only (no duplicate bars below) ──────────
                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 16

                    component CircleGauge: Item {
                        id: gauge
                        property real value: 0.0
                        property string label: ""
                        property string icon: ""
                        property color trackColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        property color fillColor: value > 0.85 ? "#e06c75" : Theme.primary
                        width: 96; height: 120

                        Canvas {
                            id: gaugeCanvas
                            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                            width: 88; height: 88
                            property real animValue: 0.0
                            Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }
                            onAnimValueChanged: requestPaint()
                            Component.onCompleted: animValue = gauge.value
                            Connections { target: gauge; function onValueChanged() { gaugeCanvas.animValue = gauge.value } }
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset()
                                var cx=width/2, cy=height/2, r=(width-14)/2
                                var s=Math.PI*0.75, sw=Math.PI*1.5
                                ctx.beginPath(); ctx.arc(cx,cy,r,s,s+sw,false); ctx.strokeStyle=gauge.trackColor; ctx.lineWidth=8; ctx.lineCap="round"; ctx.stroke()
                                if (animValue>0) { ctx.beginPath(); ctx.arc(cx,cy,r,s,s+sw*animValue,false); ctx.strokeStyle=gauge.fillColor; ctx.lineWidth=8; ctx.lineCap="round"; ctx.stroke() }
                                if (animValue>0.02) { var ta=s+sw*animValue; ctx.beginPath(); ctx.arc(cx+r*Math.cos(ta),cy+r*Math.sin(ta),4,0,Math.PI*2); ctx.fillStyle=gauge.fillColor; ctx.fill() }
                            }
                            Column {
                                anchors.centerIn: parent; spacing: 1
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.icon; color: Theme.primary; font.pixelSize: 16 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(gauge.value*100)+"%"; color: gauge.fillColor; font.pixelSize: 13; font.weight: Font.Black }
                            }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; text: gauge.label; color: Theme.primary; opacity: 0.55; font.pixelSize: 11; font.weight: Font.Medium }
                    }

                    CircleGauge { label: "CPU";    icon: "󰻠"; value: sysInfo.cpuUsage }
                    CircleGauge { label: "Memory"; icon: "󰍛"; value: sysInfo.ramUsage }
                    CircleGauge { label: "Disk";   icon: "󰋊"; value: sysInfo.diskUsage }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                // ── Game Mode toggle ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 48; radius: 14
                    color: popup.gamemodeActive
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        : Theme.background
                    border.color: popup.gamemodeActive ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                    border.width: popup.gamemodeActive ? 1.5 : 1

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12

                        Text {
                            text: "󰊴"
                            color: popup.gamemodeActive ? Theme.primary : Theme.primary
                            font.pixelSize: 20; opacity: popup.gamemodeActive ? 1.0 : 0.5
                            Layout.alignment: Qt.AlignVCenter
                        }
                        ColumnLayout {
                            spacing: 1; Layout.fillWidth: true
                            Text { text: "Game Mode"; color: Theme.primary; font.pixelSize: 13; font.bold: true }
                            Text {
                                text: popup.gamemodeActive ? "Blur, shadows & animations off" : "Blur, shadows & animations on"
                                color: Theme.primary; opacity: 0.45; font.pixelSize: 10
                            }
                        }
                        // Toggle switch
                        Rectangle {
                            width: 44; height: 24; radius: 12
                            color: popup.gamemodeActive ? Theme.primary : "transparent"
                            border.color: Theme.primary; border.width: 2
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                x: popup.gamemodeActive ? parent.width - width - 3 : 3; y: 3
                                width: 18; height: 18; radius: 9
                                color: popup.gamemodeActive ? Theme.background : Theme.primary
                                Behavior on x { NumberAnimation { duration: 180 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    popup.gamemodeActive = !popup.gamemodeActive
                                    gamemodeExec.apply(popup.gamemodeActive)
                                }
                            }
                        }
                    }
                }

                // ── Power profile ─────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "󱐋  Power Profile"; color: Theme.primary; font.pixelSize: 13; font.bold: true }
                        Item { Layout.fillWidth: true }
                        // Show tuxedo button if installed, else show current profile label
                        Rectangle {
                            visible: popup.tuxedoInstalled
                            width: tuxLbl.implicitWidth + 24; height: 26; radius: 8
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                            border.color: Theme.primary; border.width: 1
                            Text { id: tuxLbl; anchors.centerIn: parent; text: "Open Tuxedo CC"; color: Theme.primary; font.pixelSize: 10; font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: { localExec.run(["tuxedo-control-center"]); popup.active=false } }
                        }
                    }

                    // Three profile pills — hidden when tuxedo is installed
                    // (user manages profiles from tuxedo cc instead)
                    Row {
                        Layout.fillWidth: true; spacing: 8
                        visible: !popup.tuxedoInstalled

                        Repeater {
                            model: [
                                { id: "power-saver",  icon: "󰁾", label: "Saver"       },
                                { id: "balanced",     icon: "󰁿", label: "Balanced"    },
                                { id: "performance",  icon: "󱐋", label: "Performance" }
                            ]
                            Rectangle {
                                property bool sel: popup.powerProfile === modelData.id
                                width: (parent.width - 16) / 3; height: 52; radius: 14
                                color: sel ? Theme.primary : Theme.background
                                border.color: Theme.primary
                                border.width: sel ? 0 : 1

                                Column {
                                    anchors.centerIn: parent; spacing: 4
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: sel ? Theme.background : Theme.primary; font.pixelSize: 18; opacity: sel ? 1.0 : 0.6 }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: sel ? Theme.background : Theme.primary; font.pixelSize: 10; font.bold: sel; opacity: sel ? 1.0 : 0.6 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        popup.powerProfile = modelData.id
                                        powerProfileSetter.set(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.08 }

                // ── System monitor button ─────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 38; radius: 12; color: Theme.primary
                    Text { anchors.centerIn: parent; text: "󰓅  Open System Monitor"; color: Theme.background; font.bold: true; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; onClicked: { localExec.run(["bash","-c","~/.config/ml4w/settings/system-monitor.sh"]); popup.active=false } }
                }
            }
        }
    }
}
