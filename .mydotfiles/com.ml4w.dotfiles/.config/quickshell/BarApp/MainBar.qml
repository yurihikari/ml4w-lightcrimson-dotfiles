import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io 
import Quickshell.Services.Mpris
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
        property bool isDragging: false 
        property string bat: "0%"
        property string wifi: ""
        property bool wifiRadio: false
        property string connType: "none"
        property bool bluetooth: false
        property bool hasBattery: true 
        property real cpuUsage: 0.0
        property real ramUsage: 0.0
        property real diskUsage: 0.0
    }

    Process {
        id: volGetter
        running: true
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: {
                if (!sysInfo.isDragging) {
                    let output = data.trim()
                    sysInfo.isMuted = output.includes("[MUTED]")
                    let match = output.match(/[0-9.]+/)
                    if (match) sysInfo.volValue = parseFloat(match[0])
                }
            }
        }
    }

    Process {
        id: batGetter
        running: true
        command: ["bash", "-c", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 'none'"]
        stdout: SplitParser {
            onRead: {
                if (data.trim() === "none") sysInfo.hasBattery = false
                else sysInfo.bat = data.trim() + "%"
            }
        }
    }

    Process {
        id: wifiGetter
        running: true
        command: ["bash", "-c", 
            "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected' | head -1); " +
            "wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2); " +
            "if [ -n \"$eth\" ]; then connType=\"ethernet\"; elif [ -n \"$wifi\" ]; then connType=\"wifi\"; else connType=\"none\"; fi; " +
            "echo \"$connType:$wifi\""
        ]
        stdout: SplitParser {
            onRead: {
                let parts = data.trim().split(":")
                sysInfo.connType = parts[0]
                sysInfo.wifi = parts[1] || ""
            }
        }
    }

    Process {
        id: wifiRadioGetter
        running: true
        command: ["bash", "-c", "nmcli radio wifi"]
        stdout: SplitParser {
            onRead: { sysInfo.wifiRadio = data.trim() === "enabled" }
        }
    }

    Process {
        id: btGetter
        running: true
        command: ["bash", "-c", "bluetoothctl show | grep -q 'Powered: yes' && echo 'on' || echo 'off'"]
        stdout: SplitParser {
            onRead: { sysInfo.bluetooth = (data.trim() === "on") }
        }
    }

    Process {
        id: perfGetter
        running: true
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
            batGetter.running = true
            wifiGetter.running = true
            btGetter.running = true
            perfGetter.running = true
            volGetter.running = true
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { 
            wifiRadioGetter.running = true
        }
    }

    // --- MEDIA (native MPRIS) ---
    property var activePlayer: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    Connections {
        target: Mpris.players
        function onValuesChanged() {
            if (Mpris.players.values.length > 0) {
                let found = Mpris.players.values.some(p => p === bar.activePlayer)
                if (!found) bar.activePlayer = Mpris.players.values[0]
            } else {
                bar.activePlayer = null
            }
        }
    }

    // Position ticker — keeps p.position reactive while playing
    Timer {
        interval: 1000; repeat: true
        running: bar.activePlayer !== null && bar.activePlayer.playbackState === MprisPlaybackState.Playing
        onTriggered: { if (bar.activePlayer) bar.activePlayer.positionChanged() }
    }

    // --- EXECUTOR ---
    Process { 
        id: executor
        function run(args) { command = args; running = true } 
    }

    // --- SWAYNC ---
    property string swayncState: "none"
    Process {
        id: swayncWatcher
        running: true
        command: ["swaync-client", "-swb"]
        stdout: SplitParser {
            onRead: {
                try {
                    let json = JSON.parse(data.trim())
                    bar.swayncState = json.alt
                } catch (e) {}
            }
        }
    }

    function getNotificationIcon(state) {
        if (state.includes("notification")) return "󰂠"
        return state.includes("dnd") ? "󰂛" : "󰂚"
    }

    // --- UI LAYOUT ---
    Rectangle { anchors.top: parent.top; width: parent.width; height: 40; color: Theme.background; opacity: 0.8 }

    // Center pill — media info
    Rectangle {
        id: centerPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 5
        height: 30
        width: Math.min(centerRow.implicitWidth + 30, 450)
        radius: 15
        color: Theme.background
        z: 5
        Row {
            id: centerRow
            anchors.centerIn: parent
            spacing: 8
            Text { text: "󰎆"; color: Theme.primary; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
            Text { 
                text: {
                    let title = bar.activePlayer ? (bar.activePlayer.trackTitle || "No Media") : "No Media"
                    let artist = bar.activePlayer ? (bar.activePlayer.trackArtist || "") : ""
                    return title + (artist ? " - " + artist : "")
                }
                color: Theme.primary; font.pixelSize: 14; font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight; width: Math.min(implicitWidth, 350)
            }
        }
        MouseArea { 
            anchors.fill: parent
            onClicked: mediaPopup.active = !mediaPopup.active 
        }
    }

    RowLayout {
        anchors.top: parent.top; width: parent.width; height: 40
        anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 0

        // Left: logo + workspaces
        Row {
            Layout.alignment: Qt.AlignLeft; spacing: 8
            Text { 
                text: "   󰣇"; color: Theme.primary; font.pixelSize: 24
                anchors.verticalCenter: parent.verticalCenter 
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        // if (mouse.button === Qt.LeftButton) executor.run(["bash", "-c", "~/.config/hypr/scripts/launcher.sh"])
                        // else executor.run(["bash", "-c", "~/.config/hypr/scripts/keybindings.sh"])
                        onClicked: dashPopup.active = !dashPopup.active
                    }
                }
            }
            Rectangle {
                height: 30; width: wsRow.width + 20; radius: 15
                color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 12
                    Repeater {
                        model: Hyprland.workspaces
                        Item {
                            width: 16; height: 16
                            Text {
                                anchors.centerIn: parent
                                text: modelData.active ? "󰮯" : "󰊠"
                                color: modelData.active ? Theme.on_primary_container : Theme.primary
                                font.pixelSize: 16; verticalAlignment: Text.AlignVCenter
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: executor.run(["hyprctl", "dispatch", "workspace", modelData.name])
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Right: volume, clipboard, notifications, clock, system pill, power
        Row {
            Layout.alignment: Qt.AlignRight; spacing: 15

            // VOLUME
            Row {
                spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Text { 
                    text: sysInfo.isMuted ? "󰝟" : (sysInfo.volValue > 0.6 ? "󰕾" : (sysInfo.volValue > 0.2 ? "󰖀" : "󰕿"))
                    color: sysInfo.isMuted ? Theme.accent : Theme.primary
                    font.pixelSize: 18; verticalAlignment: Text.AlignVCenter 
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                            volGetter.running = true
                        }
                    }
                }
                Rectangle {
                    width: 80; height: 6; radius: 3
                    color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                    Rectangle { 
                        width: parent.width * sysInfo.volValue; height: parent.height; radius: 3
                        color: sysInfo.isMuted ? Theme.accent : Theme.primary 
                    }
                    MouseArea {
                        anchors.fill: parent
                        function update(mouse) {
                            sysInfo.isDragging = true
                            let p = Math.max(0, Math.min(1, mouse.x / width))
                            sysInfo.volValue = p
                            executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", p.toFixed(2)])
                        }
                        onPressed: update(mouse)
                        onPositionChanged: update(mouse)
                        onReleased: { sysInfo.isDragging = false; volGetter.running = true }
                        onWheel: (wheel) => {
                            let delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                            let newValue = Math.max(0, Math.min(1, sysInfo.volValue + delta))
                            sysInfo.volValue = newValue
                            executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", newValue.toFixed(2)])
                            volGetter.running = true
                        }
                    }
                }
            }

            // CLIPBOARD
            Text {
                text: "󰅌"; color: Theme.primary; font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; onClicked: clipboardPopup.active = !clipboardPopup.active }
            }

            // NOTIFICATIONS
            Text {
                text: getNotificationIcon(bar.swayncState)
                color: Theme.primary; font.pixelSize: 20
                anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) executor.run(["swaync-client", "-t", "-sw"])
                        else executor.run(["swaync-client", "-d", "-sw"])
                    }
                }
            }

            // CLOCK
            Item {
                width: clockCol.implicitWidth; height: 32
                anchors.verticalCenter: parent.verticalCenter
                Column {
                    id: clockCol
                    anchors.centerIn: parent; spacing: -2
                    property var time: new Date()
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: clockCol.time = new Date() }
                    Text { 
                        text: Qt.formatDateTime(clockCol.time, "HH:mm")
                        color: Theme.primary; font.pixelSize: 12; font.weight: Font.Black
                        horizontalAlignment: Text.AlignHCenter 
                    }
                    Text { 
                        text: Qt.formatDateTime(clockCol.time, "AP")
                        color: Theme.primary; font.pixelSize: 10; font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter 
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: calendarPopup.active = !calendarPopup.active }
            }

            // SYSTEM PILL (network, bt, battery)
            Rectangle {
                height: 30; width: sysRow.implicitWidth + 24; radius: 15
                color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                RowLayout {
                    id: sysRow; anchors.centerIn: parent; spacing: 10
                    Row { 
                        spacing: 4; Layout.alignment: Qt.AlignVCenter
                        visible: sysInfo.connType !== "none"
                        Text {
                            text: sysInfo.connType === "ethernet" ? "󰈀" : "󰤨"
                            color: Theme.primary; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            text: sysInfo.wifi
                            color: Theme.primary; font.pixelSize: 13; font.weight: Font.Bold
                            visible: sysInfo.connType === "wifi" && sysInfo.wifi !== ""
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Text { 
                        text: "󰂯"; color: Theme.primary; font.pixelSize: 14
                        visible: sysInfo.bluetooth
                        Layout.alignment: Qt.AlignVCenter; verticalAlignment: Text.AlignVCenter
                    }
                    Row { 
                        spacing: 4; visible: sysInfo.hasBattery; Layout.alignment: Qt.AlignVCenter
                        Text { text: "󰂄"; color: Theme.primary; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                        Text { text: sysInfo.bat; color: Theme.primary; font.pixelSize: 13; font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: systemPopup.active = !systemPopup.active }
            }

            // POWER
            Text { 
                text: "󰐥    "; color: Theme.primary; font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                MouseArea { anchors.fill: parent; onClicked: powerPopup.active = !powerPopup.active }
            }
        }
    }

    MediaPopup { id: mediaPopup; screen: bar.screen }
    SystemPopup { id: systemPopup }
    CalendarPopup { id: calendarPopup }
    ClipboardPopup { id: clipboardPopup; screen: bar.screen }
    PowerPopup { id: powerPopup; screen: bar.screen }
    DashboardPopup { id: dashPopup; screen: root.screen }

    Canvas { 
        opacity: 0.8; id: leftCorner; x: 10; y: 40; width: 20; height: 20
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { 
            var ctx = getContext("2d"); ctx.reset()
            ctx.fillStyle = Theme.background
            ctx.moveTo(0, 0); ctx.lineTo(20, 0)
            ctx.arcTo(0, 0, 0, 20, 20); ctx.fill()
        }
    }
    Canvas { 
        opacity: 0.8; id: rightCorner; x: parent.width - 30; y: 40; width: 20; height: 20
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { 
            var ctx = getContext("2d"); ctx.reset()
            ctx.fillStyle = Theme.background
            ctx.moveTo(20, 0); ctx.lineTo(0, 0)
            ctx.arcTo(20, 0, 20, 20, 20); ctx.fill()
        }
    }
}
