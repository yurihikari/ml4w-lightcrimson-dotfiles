import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io 
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import "../CustomTheme"

PanelWindow {
    id: bar
    anchors { top: true; left: true; right: true }
    property var modelData
    screen: modelData
    
    height: 60 
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: WlrLayershell.Exclusive
    exclusiveZone: height - 30 
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // --- SYSTEM DATA ENGINE ---
    QtObject {
        id: sysInfo
        property real volValue: 0.0
        property bool isMuted: false
        property real micValue: 0.0
        property bool isMicMuted: false
        property real briValue: 0.0
        
        property string bat: "0%"
        property int batLevel: 0
        property bool batCharging: false
        property string wifi: ""
        property bool wifiRadio: false
        property string connType: "none"
        property bool bluetooth: false
        property bool hasBattery: true 
        property real cpuUsage: 0.0
        property real ramUsage: 0.0
        property real diskUsage: 0.0
        
        property string kbLayout: "US"
        property string kbVariant: ""
        property string activeOSD: ""
    }

    // --- HYPRLAND CLIENTS (for workspace app icons) ---
    property var hyprClients: []
    property string _clientsBuf: ""

    Process {
        id: clientsGetter; running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: SplitParser { onRead: bar._clientsBuf += data }
        onRunningChanged: {
            if (running) {
                bar._clientsBuf = ""
            } else {
                try { bar.hyprClients = JSON.parse(bar._clientsBuf) }
                catch(e) {}
                bar._clientsBuf = ""
            }
        }
    }

    // --- PROCESSES ---
    Process { 
        id: executor
        function run(args) { command = args; running = true } 
    }

    Process {
        id: volGetter; running: true
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: {
                if (sysInfo.activeOSD !== "vol") {
                    let out = data.trim(); sysInfo.isMuted = out.includes("[MUTED]")
                    let m = out.match(/[0-9.]+/)
                    if (m) sysInfo.volValue = parseFloat(m[0])
                }
            }
        }
    }

    Process {
        id: micGetter; running: true
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@"]
        stdout: SplitParser {
            onRead: {
                if (sysInfo.activeOSD !== "mic") {
                    let out = data.trim(); sysInfo.isMicMuted = out.includes("[MUTED]")
                    let m = out.match(/[0-9.]+/)
                    if (m) sysInfo.micValue = parseFloat(m[0])
                }
            }
        }
    }

    Process {
        id: briGetter; running: true
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{print $4}' | tr -d % || echo '0'"]
        stdout: SplitParser {
            onRead: {
                if (sysInfo.activeOSD !== "bri") {
                    sysInfo.briValue = (parseFloat(data.trim()) || 0) / 100
                }
            }
        }
    }

    // KB Getter
    Process {
        id: kbGetter; running: true
        command: ["bash", "-c", "l=$(grep -E 'kb_layout\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); v=$(grep -E 'kb_variant\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); echo \"${l:-US}|${v}\""]
        stdout: SplitParser { 
            onRead: { 
                let parts = data.trim().split("|")
                sysInfo.kbLayout = (parts[0] || "US").toUpperCase()
                sysInfo.kbVariant = parts[1] || ""
            } 
        }
    }

    Process {
        id: batGetter; running: true
        command: ["bash", "-c", "cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null); st=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null); if [ -z \"$cap\" ]; then echo 'none'; else echo \"$cap|$st\"; fi"]
        stdout: SplitParser {
            onRead: {
                let out = data.trim()
                if (out === "none") { sysInfo.hasBattery = false }
                else {
                    let parts = out.split("|")
                    sysInfo.batLevel = parseInt(parts[0]) || 0
                    sysInfo.bat = (parseInt(parts[0]) || 0) + "%"
                    sysInfo.batCharging = (parts[1] === "Charging" || parts[1] === "Full")
                }
            }
        }
    }
    
    Process {
        id: wifiGetter; running: true
        command: ["bash", "-c", "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected' | head -1); wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2); if [ -n \"$eth\" ]; then connType=\"ethernet\"; elif [ -n \"$wifi\" ]; then connType=\"wifi\"; else connType=\"none\"; fi; echo \"$connType:$wifi\""]
        stdout: SplitParser { onRead: { let parts = data.trim().split(":"); sysInfo.connType = parts[0]; sysInfo.wifi = parts[1] || "" } }
    }
    
    Process {
        id: wifiRadioGetter; running: true
        command: ["bash", "-c", "nmcli radio wifi"]
        stdout: SplitParser { onRead: { sysInfo.wifiRadio = data.trim() === "enabled" } }
    }

    Process {
        id: btGetter; running: true
        command: ["bash", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo 'on' || echo 'off'"]
        stdout: SplitParser { onRead: { sysInfo.bluetooth = (data.trim() === "on") } }
    }

    Process {
        id: perfGetter; running: true
        command: ["bash", "-c", "cpu=$(top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8}'); mem=$(free | grep Mem | awk '{print $3/$2 * 100.0}'); disk=$(df / --output=pcent | tail -1 | tr -dc '0-9'); echo \"$cpu|$mem|$disk\""]
        stdout: SplitParser {
            onRead: {
                let parts = data.trim().split("|")
                if (parts.length >= 3) {
                    sysInfo.cpuUsage = (parseFloat(parts[0]) || 0) / 100
                    sysInfo.ramUsage = (parseFloat(parts[1]) || 0) / 100
                    sysInfo.diskUsage = (parseFloat(parts[2]) || 0) / 100
                }
            }
        }
    }

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

    // --- MEDIA (native MPRIS) ---
    property var activePlayer: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    Connections {
        target: Mpris.players
        function onValuesChanged() {
            if (Mpris.players.values.length > 0) {
                let found = Mpris.players.values.some(p => p === bar.activePlayer)
                if (!found) bar.activePlayer = Mpris.players.values[0]
            } else { bar.activePlayer = null }
        }
    }
    Timer { interval: 1000; repeat: true; running: bar.activePlayer !== null && bar.activePlayer.playbackState === MprisPlaybackState.Playing; onTriggered: { if (bar.activePlayer) bar.activePlayer.positionChanged() } }

    // --- SWAYNC ---
    property string swayncState: "none"
    Process {
        id: swayncWatcher; running: true
        command: ["swaync-client", "-swb"]
        stdout: SplitParser { onRead: { try { let json = JSON.parse(data.trim()); bar.swayncState = json.alt } catch (e) {} } }
    }
    function getNotificationIcon(state) {
        if (state.includes("notification")) return "󰂠"
        return state.includes("dnd") ? "󰂛" : "󰂚"
    }

    // --- BATTERY HELPER --- 
    function getBatteryIcon(level, charging) {
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

    // ── INSTANT OSD HANDLER ──
    function triggerOSD(type, delta) {
        sysInfo.activeOSD = type
        osdPopup.active = true
        osdTimer.restart()
        
        if (delta !== 0) {
            if (type === "vol") {
                let nv = Math.max(0, Math.min(1, sysInfo.volValue + delta))
                sysInfo.volValue = nv
                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", nv.toFixed(2)])
            } else if (type === "mic") {
                let nv = Math.max(0, Math.min(1, sysInfo.micValue + delta))
                sysInfo.micValue = nv
                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", nv.toFixed(2)])
            } else if (type === "bri") {
                let nv = Math.max(0, Math.min(1, sysInfo.briValue + delta))
                sysInfo.briValue = nv
                let sign = delta > 0 ? "+" : "-"
                executor.run(["bash", "-c", "brightnessctl s 5%" + sign])
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // UI LAYOUT
    // ══════════════════════════════════════════════════════════════════════════
    Rectangle { anchors.top: parent.top; width: parent.width; height: 40; color: Theme.background; opacity: 0.8 }

    // Center pill — media info
    Rectangle {
        id: centerPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 5
        height: 30; width: Math.min(centerRow.implicitWidth + 30, 450); radius: 15; z: 5
        scale: centerMouse.pressed ? 0.96 : (centerMouse.containsMouse ? 1.02 : 1.0)
        color: centerMouse.containsMouse ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.95) : Theme.background
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: centerRow; anchors.centerIn: parent; spacing: 8
            Text { text: "󰎆"; color: Theme.primary; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
            Text { 
                text: { let title = bar.activePlayer ? (bar.activePlayer.trackTitle || "No Media") : "No Media"; let artist = bar.activePlayer ? (bar.activePlayer.trackArtist || "") : ""; return title + (artist ? " - " + artist : "") }
                color: Theme.primary; font.pixelSize: 14; font.weight: Font.Medium; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; width: Math.min(implicitWidth, 350)
            }
        }
        MouseArea { id: centerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: mediaPopup.active = !mediaPopup.active }
    }

    RowLayout {
        anchors.top: parent.top; width: parent.width; height: 40
        anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 0

        // ── LEFT: logo + workspaces + tray ──
        Row {
            Layout.alignment: Qt.AlignLeft; spacing: 8

            // Logo
            Text { 
                text: "   󰣇"; color: Theme.primary; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter 
                opacity: 1; scale: logoMouse.pressed ? 0.85 : (logoMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: logoMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: dashPopup.active = !dashPopup.active }
            }

            // Workspaces pill
            Rectangle {
                height: 30; width: wsRow.width + 20; radius: 15
                color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: wsRow; anchors.centerIn: parent; spacing: 12
                    Repeater {
                        model: Hyprland.workspaces
                        Item {
                            id: wsItem
                            property var wsClients: {
                                let name = modelData.name
                                return bar.hyprClients.filter(function(c) {
                                    return c.workspace && c.workspace.name === name
                                })
                            }
                            property bool showIcons: wsMouse.containsMouse && wsClients.length > 0

                            width: 16 + (showIcons ? wsIconsRow.implicitWidth + 6 : 0)
                            height: 16
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            scale: wsMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            Text {
                                id: wsText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.active ? "󰮯" : "󰊠"
                                
                                // Explicitly bind both colors to prevent ternary loss on theme switch
                                property color _primary: Theme.primary
                                property color _onPrimary: Theme.on_primary_container
                                color: modelData.active ? _onPrimary : _primary
                                
                                font.pixelSize: 16; verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Row {
                                id: wsIconsRow
                                anchors.left: wsText.right
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                opacity: wsItem.showIcons ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                Repeater {
                                    model: wsItem.wsClients
                                    delegate: Item {
                                        width: 14; height: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        // Resolve a real icon path; "" means not found (no broken texture)
                                        property string resolvedIcon: {
                                            let cls = modelData.class || ""
                                            if (cls === "") return ""
                                            let candidates = [cls, cls.toLowerCase()]
                                            for (let i = 0; i < candidates.length; i++) {
                                                let p = Quickshell.iconPath(candidates[i], true)
                                                if (p && p.length > 0 && !p.includes("image-missing")) return p
                                            }
                                            return ""
                                        }

                                        Image {
                                            anchors.fill: parent
                                            source: parent.resolvedIcon
                                            sourceSize: Qt.size(14, 14)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            visible: parent.resolvedIcon !== ""
                                        }

                                        // Fallback glyph when no icon found
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰣆"
                                            color: Theme.primary
                                            font.pixelSize: 12
                                            visible: parent.resolvedIcon === ""
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: wsMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: executor.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + modelData.name + "\" })"])
                            }
                        }
                    }
                }
            }

            // System tray pill
            Rectangle {
                height: 30; width: trayRow.width + 20; radius: 15
                color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                visible: SystemTray.items.values.length > 0

                Row {
                    id: trayRow; anchors.centerIn: parent; spacing: 10

                    Repeater {
                        model: SystemTray.items.values

                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            width: 16; height: 16
                            anchors.verticalCenter: parent.verticalCenter

                            scale: trayMouse.pressed ? 0.85 : (trayMouse.containsMouse ? 1.15 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            Image {
                                anchors.fill: parent
                                source: trayItem.modelData.icon
                                sourceSize.width: 16
                                sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    let item = trayItem.modelData
                                    if (mouse.button === Qt.LeftButton) {
                                        if (item.onlyMenu) {
                                            trayMenu.openFor(trayItem, item)
                                        } else {
                                            item.activate()
                                        }
                                    } else if (mouse.button === Qt.MiddleButton) {
                                        item.secondaryActivate()
                                    } else if (mouse.button === Qt.RightButton) {
                                        if (item.hasMenu) trayMenu.openFor(trayItem, item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // ── RIGHT: controls + status ──
        Row {
            Layout.alignment: Qt.AlignRight; spacing: 15
            anchors.verticalCenter: parent.verticalCenter

            // Compact Cluster (Mic, Brightness, Volume, Layout)
            Row {
                spacing: 12; anchors.verticalCenter: parent.verticalCenter
                
                // Mic
                Item {
                    id: micContainer
                    height: 28
                    width: 28 + (micMouse.containsMouse ? micLabel.implicitWidth + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    scale: micMouse.pressed ? 0.85 : (micMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    // Explicit property definitions to track both branches consistently
                    property color _primary: Theme.primary
                    property color _accent: Theme.accent
                    property color activeColor: sysInfo.isMicMuted ? _accent : _primary

                    Item {
                        id: micRing
                        width: 28; height: 28
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(micContainer._primary.r, micContainer._primary.g, micContainer._primary.b, 0.15)
                            border.width: 2
                        }

                        Canvas {
                            anchors.fill: parent
                            property real value: sysInfo.micValue
                            property color ringColor: micContainer.activeColor
                            onValueChanged: requestPaint(); onRingColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                if (value > 0) {
                                    ctx.beginPath();
                                    ctx.arc(width/2, height/2, width/2 - 1, -Math.PI/2, -Math.PI/2 + (Math.min(1.0, value) * 2 * Math.PI));
                                    ctx.lineWidth = 2; ctx.strokeStyle = ringColor; ctx.lineCap = "round"; ctx.stroke();
                                }
                            }
                        }

                        Text {
                            text: sysInfo.isMicMuted ? "󰍭" : "󰍬"
                            color: micContainer.activeColor
                            font.pixelSize: 14
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        id: micLabel
                        text: sysInfo.isMicMuted ? "Muted" : (Math.round(sysInfo.micValue * 100) + "%")
                        color: micContainer._primary
                        font.pixelSize: 11; font.bold: true
                        anchors.left: micRing.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        clip: true
                        opacity: micMouse.containsMouse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: micMouse; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                        onClicked: {
                            sysInfo.isMicMuted = !sysInfo.isMicMuted
                            executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"])
                        }
                        onWheel: (wheel) => triggerOSD("mic", wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                }

                // Brightness
                Item {
                    id: briContainer
                    height: 28
                    width: 28 + (briMouse.containsMouse ? briLabel.implicitWidth + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    scale: briMouse.pressed ? 0.85 : (briMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    property color _primary: Theme.primary

                    Item {
                        id: briRing
                        width: 28; height: 28
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(briContainer._primary.r, briContainer._primary.g, briContainer._primary.b, 0.15)
                            border.width: 2
                        }

                        Canvas {
                            anchors.fill: parent
                            property real value: sysInfo.briValue
                            property color ringColor: briContainer._primary
                            onValueChanged: requestPaint(); onRingColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                if (value > 0) {
                                    ctx.beginPath();
                                    ctx.arc(width/2, height/2, width/2 - 1, -Math.PI/2, -Math.PI/2 + (Math.min(1.0, value) * 2 * Math.PI));
                                    ctx.lineWidth = 2; ctx.strokeStyle = ringColor; ctx.lineCap = "round"; ctx.stroke();
                                }
                            }
                        }

                        Text {
                            text: sysInfo.briValue > 0.6 ? "󰃠" : (sysInfo.briValue > 0.3 ? "󰃟" : "󰃞")
                            color: briContainer._primary
                            font.pixelSize: 14
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        id: briLabel
                        text: Math.round(sysInfo.briValue * 100) + "%"
                        color: briContainer._primary
                        font.pixelSize: 11; font.bold: true
                        anchors.left: briRing.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        clip: true
                        opacity: briMouse.containsMouse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: briMouse; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                        onClicked: triggerOSD("bri", 0)
                        onWheel: (wheel) => triggerOSD("bri", wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                }

                // Volume
                Item {
                    id: volContainer
                    height: 28
                    width: 28 + (volIconMouse.containsMouse ? volLabel.implicitWidth + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    scale: volIconMouse.pressed ? 0.85 : (volIconMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    property color _primary: Theme.primary
                    property color _accent: Theme.accent
                    property color activeColor: sysInfo.isMuted ? _accent : _primary

                    Item {
                        id: volRing
                        width: 28; height: 28
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(volContainer._primary.r, volContainer._primary.g, volContainer._primary.b, 0.15)
                            border.width: 2
                        }

                        Canvas {
                            anchors.fill: parent
                            property real value: sysInfo.volValue
                            property color ringColor: volContainer.activeColor
                            onValueChanged: requestPaint(); onRingColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                if (value > 0) {
                                    ctx.beginPath();
                                    ctx.arc(width/2, height/2, width/2 - 1, -Math.PI/2, -Math.PI/2 + (Math.min(1.0, value) * 2 * Math.PI));
                                    ctx.lineWidth = 2; ctx.strokeStyle = ringColor; ctx.lineCap = "round"; ctx.stroke();
                                }
                            }
                        }

                        Text {
                            text: sysInfo.isMuted ? "󰝟" : (sysInfo.volValue > 0.6 ? "󰕾" : (sysInfo.volValue > 0.2 ? "󰖀" : "󰕿"))
                            color: volContainer.activeColor
                            font.pixelSize: 14
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        id: volLabel
                        text: sysInfo.isMuted ? "Muted" : (Math.round(sysInfo.volValue * 100) + "%")
                        color: volContainer._primary
                        font.pixelSize: 11; font.bold: true
                        anchors.left: volRing.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        clip: true
                        opacity: volIconMouse.containsMouse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: volIconMouse; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                        onClicked: {
                            sysInfo.isMuted = !sysInfo.isMuted
                            executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                        }
                        onWheel: (wheel) => triggerOSD("vol", wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                    }
                }

                Rectangle { width: 1; height: 16; color: Theme.primary; opacity: 0.2; anchors.verticalCenter: parent.verticalCenter }

                // KB Layout
                Item {
                    id: kbContainer
                    height: 28
                    width: 28 + (kbMouse.containsMouse ? kbLabel.implicitWidth + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    scale: kbMouse.pressed ? 0.95 : (kbMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    property color _primary: Theme.primary

                    Item {
                        id: kbIconWrapper
                        width: 28; height: 28
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "󰌌"
                            color: kbContainer._primary
                            font.pixelSize: 16
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        id: kbLabel
                        text: sysInfo.kbLayout + (sysInfo.kbVariant !== "" ? " (" + sysInfo.kbVariant.split(",")[0].substring(0,2) + ")" : "")
                        color: kbContainer._primary
                        font.pixelSize: 11
                        font.bold: true
                        anchors.left: kbIconWrapper.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter

                        clip: true
                        opacity: kbMouse.containsMouse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: kbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: keyboardPopup.active = !keyboardPopup.active
                    }
                }
            }

            // CLIPBOARD
            Text {
                text: "󰅌"; color: Theme.primary; font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                opacity: 1; scale: clipMouse.pressed ? 0.85 : (clipMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: clipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: clipboardPopup.active = !clipboardPopup.active }
            }

            // NOTIFICATIONS
            Item {
                id: notifContainer
                height: 28
                width: 28 + (notifMouse.containsMouse ? notifLabel.implicitWidth + 6 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                scale: notifMouse.pressed ? 0.85 : (notifMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                property color _primary: Theme.primary

                Item {
                    id: notifIconWrapper
                    width: 28; height: 28
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: getNotificationIcon(bar.swayncState)
                        color: notifContainer._primary
                        font.pixelSize: 18
                        anchors.centerIn: parent
                    }
                }

                Text {
                    id: notifLabel
                    text: bar.swayncState.includes("dnd") ? "DND" : (bar.swayncState.includes("notification") ? "New" : "Clear")
                    color: notifContainer._primary
                    font.pixelSize: 11; font.bold: true
                    anchors.left: notifIconWrapper.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    opacity: notifMouse.containsMouse ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: notifMouse; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) executor.run(["swaync-client", "-t", "-sw"])
                        else executor.run(["swaync-client", "-d", "-sw"])
                    }
                }
            }

            // CLOCK
            Item {
                id: clockContainer
                height: 32
                width: clockCol.implicitWidth + (clockMouse.containsMouse ? dateLabel.implicitWidth + 6 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                opacity: 1; scale: clockMouse.pressed ? 0.95 : (clockMouse.containsMouse ? 1.05 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                property var time: new Date()
                property color _primary: Theme.primary
                Timer { interval: 1000; running: true; repeat: true; onTriggered: clockContainer.time = new Date() }

                Column {
                    id: clockCol
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2
                    Text { text: Qt.formatDateTime(clockContainer.time, "HH:mm"); color: clockContainer._primary; font.pixelSize: 12; font.weight: Font.Black; horizontalAlignment: Text.AlignHCenter }
                    Text { text: Qt.formatDateTime(clockContainer.time, "AP"); color: clockContainer._primary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter }
                }

                Text {
                    id: dateLabel
                    text: Qt.formatDateTime(clockContainer.time, "ddd, MMM d")
                    color: clockContainer._primary
                    font.pixelSize: 11; font.bold: true
                    anchors.left: clockCol.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    opacity: clockMouse.containsMouse ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    onClicked: calendarPopup.active = !calendarPopup.active
                }
            }

            // SYSTEM PILL
            Rectangle {
                height: 30; width: sysRow.implicitWidth + 24; radius: 15
                color: sysMouse.containsMouse ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.95) : Theme.background
                anchors.verticalCenter: parent.verticalCenter
                scale: sysMouse.pressed ? 0.96 : (sysMouse.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 200 } }
                RowLayout {
                    id: sysRow; anchors.centerIn: parent; spacing: 10
                    Row { 
                        spacing: 4; Layout.alignment: Qt.AlignVCenter; visible: sysInfo.connType !== "none"
                        Text { text: sysInfo.connType === "ethernet" ? "󰈀" : "󰤨"; color: Theme.primary; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                        Text { text: sysInfo.wifi; color: Theme.primary; font.pixelSize: 13; font.weight: Font.Bold; visible: sysInfo.connType === "wifi" && sysInfo.wifi !== ""; verticalAlignment: Text.AlignVCenter }
                    }
                    Text { text: "󰂯"; color: Theme.primary; font.pixelSize: 14; visible: sysInfo.bluetooth; Layout.alignment: Qt.AlignVCenter; verticalAlignment: Text.AlignVCenter }
                    Row { 
                        spacing: 4; visible: sysInfo.hasBattery; Layout.alignment: Qt.AlignVCenter
                        Text { text: getBatteryIcon(sysInfo.batLevel, sysInfo.batCharging); color: Theme.primary; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                        Text { text: sysInfo.bat; color: Theme.primary; font.pixelSize: 13; font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }
                    }
                }
                MouseArea { id: sysMouse; anchors.fill: parent; hoverEnabled: true; onClicked: systemPopup.active = !systemPopup.active }
            }

            // POWER
            Text { 
                text: "󰐥    "; color: Theme.primary; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                opacity: 1; scale: powerMouse.pressed ? 0.85 : (powerMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: powerPopup.active = !powerPopup.active }
            }
        }
    }

    // --- CANVAS CORNERS ---
    Canvas { 
        opacity: 0.8; id: leftCorner; x: 10; y: 40; width: 20; height: 20
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = Theme.background; ctx.moveTo(0, 0); ctx.lineTo(20, 0); ctx.arcTo(0, 0, 0, 20, 20); ctx.fill() }
    }
    Canvas { 
        opacity: 0.8; id: rightCorner; x: parent.width - 30; y: 40; width: 20; height: 20
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = Theme.background; ctx.moveTo(20, 0); ctx.lineTo(0, 0); ctx.arcTo(20, 0, 20, 20, 20); ctx.fill() }
    }

    // --- NATIVE WINDOWS ---
    MediaPopup { id: mediaPopup; screen: bar.screen }
    SystemPopup { id: systemPopup }
    CalendarPopup { id: calendarPopup }
    ClipboardPopup { id: clipboardPopup; screen: bar.screen }
    PowerPopup { id: powerPopup; screen: bar.screen }
    DashboardPopup { id: dashPopup; screen: bar.screen }
    KbLayoutPopup { id: keyboardPopup; screen: bar.screen }

    // ══════════════════════════════════════════════════════════════════════════
    // SYSTEM TRAY MENU (renders SNI DBusMenu with recursive submenus)
    // ══════════════════════════════════════════════════════════════════════════

    Component {
        id: menuEntryComponent

        Column {
            id: entryRoot
            property var entryData
            property int depth: 0
            property bool expanded: false
            width: parent ? parent.width : 200

            QsMenuOpener {
                id: subOpener
                menu: entryRoot.entryData
            }

            property var subItems: {
                try { return subOpener.children ? subOpener.children.values : [] }
                catch(e) { return [] }
            }
            property bool hasChildren: subItems.length > 0

            Item {
                width: parent.width
                height: entryRoot.entryData && entryRoot.entryData.isSeparator ? 9 : 32

                Rectangle {
                    visible: entryRoot.entryData && entryRoot.entryData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 12 - entryRoot.depth * 14
                    height: 1
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                }

                Rectangle {
                    visible: entryRoot.entryData && !entryRoot.entryData.isSeparator
                    anchors.fill: parent
                    anchors.leftMargin: 2; anchors.rightMargin: 2
                    radius: 8
                    color: eMouse.containsMouse
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10 + entryRoot.depth * 14
                        anchors.rightMargin: 10
                        spacing: 6

                        Text {
                            text: (entryRoot.entryData ? entryRoot.entryData.text : "") || ""
                            color: Theme.primary
                            opacity: (entryRoot.entryData && entryRoot.entryData.enabled) ? 1.0 : 0.4
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            visible: entryRoot.hasChildren
                            text: entryRoot.expanded ? "󰅃" : "󰅀"
                            color: Theme.primary; opacity: 0.4
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: eMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: entryRoot.entryData && entryRoot.entryData.enabled && !entryRoot.entryData.isSeparator
                        onClicked: {
                            if (entryRoot.hasChildren) {
                                entryRoot.expanded = !entryRoot.expanded
                            } else {
                                entryRoot.entryData.triggered()
                                trayMenu.shown = false
                            }
                        }
                    }
                }
            }

            Column {
                visible: entryRoot.expanded && entryRoot.hasChildren
                width: parent.width
                spacing: 0

                Repeater {
                    model: entryRoot.expanded ? entryRoot.subItems : []
                    delegate: Loader {
                        width: parent ? parent.width : 200
                        sourceComponent: menuEntryComponent
                        onLoaded: {
                            item.entryData = modelData
                            item.depth = entryRoot.depth + 1
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: trayMenu
        screen: bar.screen
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        visible: shown
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive so Escape key is always captured when menu is open
        WlrLayershell.keyboardFocus: shown ? WlrLayershell.Exclusive : WlrLayershell.None
        exclusionMode: WlrLayershell.Ignore

        property bool shown: false
        property real anchorX: 0

        function openFor(itemUi, item) {
            opener.menu = item.menu
            let pos = itemUi.mapToItem(null, 0, 0)
            anchorX = pos.x + itemUi.width / 2
            shown = true
        }

        Shortcut { sequence: "Escape"; onActivated: trayMenu.shown = false }

        QsMenuOpener { id: opener }

        MouseArea { anchors.fill: parent; onClicked: trayMenu.shown = false }

        Rectangle {
            id: menuBox
            x: Math.min(Math.max(10, trayMenu.anchorX - width / 2), parent.width - width - 10)
            y: 46
            width: 250
            height: Math.min(menuCol.implicitHeight + 16, parent.height - 60)
            radius: 16
            clip: true

            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
            border.width: 2

            opacity: trayMenu.shown ? 1.0 : 0.0
            scale: trayMenu.shown ? 1.0 : 0.95
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Flickable {
                anchors.fill: parent; anchors.margins: 8
                clip: true; boundsBehavior: Flickable.StopAtBounds
                contentWidth: width; contentHeight: menuCol.implicitHeight

                Column {
                    id: menuCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: opener.children ? opener.children.values : []
                        delegate: Loader {
                            width: menuCol.width
                            sourceComponent: menuEntryComponent
                            onLoaded: {
                                item.entryData = modelData
                                item.depth = 0
                            }
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // OSD OVERLAY
    // ══════════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: osdPopup
        screen: bar.screen
        anchors { top: true; right: true }
        margins { top: 45; right: 290 }
        width: 230; height: 46
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: WlrLayershell.Ignore

        property bool active: false
        property bool isAnimating: false
        visible: active || isAnimating
        onActiveChanged: if(active) isAnimating = true

        Item {
            anchors.fill: parent
            transformOrigin: Item.Top
            opacity: osdPopup.active ? 1.0 : 0.0
            scale: osdPopup.active ? 1.0 : 0.95
            
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic; onRunningChanged: if(!running && !osdPopup.active) osdPopup.isAnimating = false } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

            Rectangle {
                anchors.fill: parent; radius: 23
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5); border.width: 2

                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    Text { text: sysInfo.activeOSD === "vol" ? "󰕾" : (sysInfo.activeOSD === "mic" ? "󰍬" : "󰃠"); color: Theme.primary; font.pixelSize: 18 }
                    
                    Rectangle {
                        Layout.fillWidth: true; height: 6; radius: 3; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        Rectangle {
                            width: parent.width * (sysInfo.activeOSD === "vol" ? sysInfo.volValue : (sysInfo.activeOSD === "mic" ? sysInfo.micValue : sysInfo.briValue))
                            height: parent.height; radius: 3; color: Theme.primary
                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                    }
                    
                    Text {
                        text: Math.round((sysInfo.activeOSD === "vol" ? sysInfo.volValue : (sysInfo.activeOSD === "mic" ? sysInfo.micValue : sysInfo.briValue)) * 100) + "%"
                        color: Theme.primary; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 35
                    }
                }
            }
        }
        Timer { id: osdTimer; interval: 2000; onTriggered: osdPopup.active = false }
    }
}