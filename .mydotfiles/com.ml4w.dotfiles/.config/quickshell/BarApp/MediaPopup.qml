import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects 
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    visible: active
    
    // Multi-monitor support
    property var modelData
    screen: modelData

    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // --- STATE & MODELS ---
    property bool selectingSink: false
    ListModel { id: sinkModel }

    // --- INTERNAL COMPONENTS ---
    component AppButton: Rectangle {
        id: appBtn
        property string icon: ""
        property string cmd: ""
        property string check: ""
        width: 44; height: 44; radius: 12
        color: Theme.background
        visible: false 
        Layout.alignment: Qt.AlignHCenter
        
        Text { 
            anchors.centerIn: parent
            text: icon
            color: Theme.primary
            font.pixelSize: 22 
        }

        MouseArea { 
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { appBtn.opacity = 0.7 }
            onExited: { appBtn.opacity = 1.0 }
            onClicked: {
                executor.run(["hyprctl", "dispatch", "exec", cmd])
            }
        }

        Process {
            running: true
            command: ["bash", "-c", "command -v " + (check !== "" ? check : cmd.split(" ")[0])]
            onExited: { appBtn.visible = (exitCode === 0) }
        }
    }

    // --- ORIGINAL CAVA ENGINE ---
    property var cavaData: []
    Process {
        id: cava
        running: popup.active
        command: ["bash", "-c", "cava -p <(echo -e '[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=400\nbar_delimiter=32\nbars=100')"]
        stdout: SplitParser {
            onRead: {
                var clean = data.trim()
                if (clean.length > 0) {
                    var parts = clean.split(/\s+/)
                    if (parts.length >= 100) {
                        popup.cavaData = parts
                        cavaCanvas.requestPaint()
                    }
                }
            }
        }
    }

    // --- SINK ENGINE ---
    property string currentSinkFull: ""
    property string currentSinkName: "Default"

    Process {
        id: sinkGetter
        running: popup.active
        command: ["bash", "-c", "pactl get-default-sink"]
        stdout: SplitParser { 
            onRead: { 
                let full = data.trim()
                popup.currentSinkFull = full
                let readable = full.replace(/.*HiFi__/, "").replace(/__sink/, "").replace(/alsa_output\./, "")
                popup.currentSinkName = readable
            } 
        }
    }

    Process {
        id: sinkListLoader
        command: ["bash", "-c", "pactl list short sinks | awk '{print $2}'"]
        stdout: SplitParser {
            onRead: {
                let line = data.trim()
                if (line !== "") {
                    let readable = line.replace(/.*HiFi__/, "").replace(/__sink/, "").replace(/alsa_output\./, "")
                    sinkModel.append({ "fullName": line, "displayName": readable })
                }
            }
        }
    }

    Timer {
        interval: 2000; running: popup.active; repeat: true
        onTriggered: { sinkGetter.running = true }
    }

    MouseArea { 
        anchors.fill: parent
        onClicked: {
            if (popup.selectingSink) popup.selectingSink = false
            else popup.active = false
        }
    }

    Rectangle {
        id: container
        width: 550; height: 400 
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 30; color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.background; border.color: Theme.primary; border.width: 2
            radius: 30; opacity: 0.8 
        }

        Rectangle {
            anchors.fill: parent; anchors.margins: 10; z: 100
            radius: 25; color: "transparent"; visible: popup.selectingSink
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 25; spacing: 15
                Text { text: "Select Audio Output"; color: Theme.primary; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    color: "transparent"; radius: 15; clip: true
                    ListView {
                        id: sinkListView; anchors.fill: parent; anchors.margins: 10; model: sinkModel; spacing: 8
                        delegate: Rectangle {
                            width: sinkListView.width; height: 45; radius: 10
                            color: fullName === popup.currentSinkFull ? Theme.primary : Theme.background
                            border.color: Theme.primary; border.width: fullName === popup.currentSinkFull ? 0 : 1
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 15
                                Text { text: "󰓃"; color: fullName === popup.currentSinkFull ? Theme.background : Theme.primary; font.pixelSize: 16 }
                                Text { text: displayName; color: fullName === popup.currentSinkFull ? Theme.background : Theme.primary; font.bold: true; font.pixelSize: 13; Layout.fillWidth: true }
                                Text { text: "󰄬"; color: Theme.background; visible: fullName === popup.currentSinkFull }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { executor.run(["pactl", "set-default-sink", fullName]); popup.selectingSink = false; sinkGetter.running = true } }
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 140; Layout.preferredHeight: 40; radius: 20; color: Theme.surface_container_high; border.color: Theme.primary; border.width: 1; Layout.alignment: Qt.AlignHCenter
                    Text { anchors.centerIn: parent; text: "Close"; color: Theme.primary; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: popup.selectingSink = false }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 25; spacing: 20
            opacity: popup.selectingSink ? 0.0 : 1.0; enabled: !popup.selectingSink
            // --- PLAYER SWITCHER ---
            Row {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                visible: playerModel.count > 1
                

                Repeater {
                    model: playerModel
                    Rectangle {
                        property bool isSelected: name === bar.selectedPlayer
                        height: 30
                        width: nameLabel.implicitWidth + 36
                        radius: 14
                        color: isSelected ? Theme.primary : Theme.background
                        border.color: Theme.primary
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            height: parent.height
                            Text {
                                text: {
                                    let n = name.toLowerCase()
                                    if (n.includes("spotify")) return "󰓇"
                                    if (n.includes("firefox") || n.includes("chrome") || n.includes("chromium")) return "󰖟"
                                    if (n.includes("vlc")) return "󰕼"
                                    if (n.includes("mpv")) return "󰎁"
                                    if (n.includes("ncmpcpp") || n.includes("mpd")) return "󱍙"
                                    return "󰎆"
                                }
                                color: isSelected ? Theme.background : Theme.primary
                                font.pixelSize: 13
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                id: nameLabel
                                text: {
                                    let n = name
                                    // Strip instance suffix like .instance123
                                    n = n.replace(/\.[a-zA-Z0-9]+$/, "")
                                    return n.charAt(0).toUpperCase() + n.slice(1)
                                }
                                color: isSelected ? Theme.background : Theme.primary
                                font.pixelSize: 12
                                font.bold: isSelected
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                bar.selectedPlayer = name
                                // Restart watcher for new player
                                mediaWatcher.running = false
                                mediaWatcher.running = true
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 25
                Item {
                    Layout.preferredWidth: 160; Layout.fillHeight: true
                    Canvas {
                        id: cavaCanvas; anchors.fill: parent; renderTarget: Canvas.FramebufferObject
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                            var centerX = width/2; var centerY = height/2; var innerRadius = 55; var barCount = 100
                            ctx.strokeStyle = Theme.primary; ctx.lineWidth = 2.5; ctx.lineCap = "round"
                            for (var i = 0; i < barCount; i++) {
                                var val = parseInt(popup.cavaData[i]) || 0; var angle = (i * (360 / barCount)) * (Math.PI / 180)
                                var h = (val / 200) * 25; if (h < 2) h = 2
                                var x1 = centerX + Math.cos(angle) * innerRadius; var y1 = centerY + Math.sin(angle) * innerRadius
                                var x2 = centerX + Math.cos(angle) * (innerRadius + h); var y2 = centerY + Math.sin(angle) * (innerRadius + h)
                                ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
                            }
                        }
                    }
                    Rectangle {
                        id: albumArtContainer; anchors.centerIn: parent; width: 100; height: 100; radius: 50
                        layer.enabled: true; layer.effect: OpacityMask { maskSource: albumArtMask }
                        Image { id: albumArt; anchors.fill: parent; source: mediaData.artUrl; fillMode: Image.PreserveAspectCrop }
                        Text { anchors.centerIn: parent; text: "󰎆"; color: Theme.primary; font.pixelSize: 35; opacity: 0.3; visible: albumArt.status !== Image.Ready }
                    }
                    Rectangle { id: albumArtMask; width: 100; height: 100; radius: 50; visible: false }
                }

                ColumnLayout {
                    Layout.fillWidth: true; Layout.maximumWidth: 320; spacing: 20
                    ColumnLayout {
                        spacing: 2
                        Text { text: mediaData.title; color: Theme.primary; font.bold: true; font.pixelSize: 22; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: mediaData.artist; color: Theme.primary; opacity: 0.7; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter; spacing: 40
                        Text { text: "󰒮"; color: Theme.primary; font.pixelSize: 32; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "previous"]) } } }
                        Text { text: mediaData.status === "Playing" ? "󰏤" : "󰐊"; color: Theme.primary; font.pixelSize: 48; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "play-pause"]) } } }
                        Text { text: "󰒭"; color: Theme.primary; font.pixelSize: 32; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "next"]) } } }
                    }
                }

                Rectangle { Layout.fillHeight: true; width: 2; color: Theme.primary; opacity: 0.1 }

                ColumnLayout {
                    Layout.preferredWidth: 80; spacing: 15
                    Text { text: "MUSIC APPS"; color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
                    AppButton { icon: "󰓇"; cmd: "spotify" }
                    AppButton { icon: "󰎆"; cmd: "pear-desktop" }
                    AppButton { icon: "󱍙"; cmd: "kitty ncmpcpp"; check: "ncmpcpp" }
                }
            }

            // --- PROGRESS SLIDER ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Theme.background

                    // Filled portion
                    Rectangle {
                        width: mediaData.length > 0
                            ? parent.width * Math.min(1, mediaData.position / mediaData.length)
                            : 0
                        height: parent.height
                        radius: 3
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.Linear } }
                    }

                    // Draggable knob
                    Rectangle {
                        id: sliderKnob
                        property bool dragging: false
                        x: mediaData.length > 0
                            ? (parent.width * Math.min(1, mediaData.position / mediaData.length)) - width / 2
                            : -width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: Theme.primary
                        Behavior on x { enabled: !sliderKnob.dragging; NumberAnimation { duration: 800; easing.type: Easing.Linear } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8  // bigger hit area
                        preventStealing: true

                        function seek(mouse) {
                            let p = Math.max(0, Math.min(1, mouse.x / width))
                            let target = p * mediaData.length
                            mediaData.position = target
                            executor.run(["playerctl", "-p", bar.selectedPlayer, "position", target.toFixed(1)])
                        }

                        onPressed: {
                            sliderKnob.dragging = true
                            seek(mouse)
                        }
                        onPositionChanged: {
                            if (pressed) seek(mouse)
                        }
                        onReleased: {
                            sliderKnob.dragging = false
                        }
                    }
                }

                // Timestamps
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: mediaData.formatTime(mediaData.position)
                        color: Theme.primary; font.pixelSize: 10; opacity: 0.6
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: mediaData.formatTime(mediaData.length)
                        color: Theme.primary; font.pixelSize: 10; opacity: 0.6
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: Theme.primary; opacity: 0.1 }

            // --- BOTTOM SECTION ---
            RowLayout {
                Layout.fillWidth: true; spacing: 20
                RowLayout {
                    spacing: 12

                    // --- MUTEABLE VOLUME ICON ---
                    Text { 
                        text: sysInfo.isMuted ? "󰝟" : (sysInfo.volValue > 0.6 ? "󰕾" : (sysInfo.volValue > 0.2 ? "󰖀" : "󰕿"))
                        color: sysInfo.isMuted ? Theme.accent : Theme.primary
                        font.pixelSize: 22
                        verticalAlignment: Text.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 150; height: 8; radius: 4; color: Theme.background
                        Rectangle {
                            width: parent.width * sysInfo.volValue; height: parent.height; radius: 4
                            color: sysInfo.isMuted ? Theme.accent : Theme.primary 
                        }
                        MouseArea {
                            anchors.fill: parent
                            function updateVol(mouse) {
                                let p = Math.max(0, Math.min(1, mouse.x / width))
                                sysInfo.volValue = p
                                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", p.toFixed(2)])
                            }
                            onPressed: { updateVol(mouse) }
                            onPositionChanged: { updateVol(mouse) }
                        }
                    }
                    Text { text: Math.round(sysInfo.volValue * 100) + "%"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 200; height: 44; radius: 15; color: Theme.background; border.color: Theme.primary; border.width: 1
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 15
                        Text { text: "󰓃"; color: Theme.primary; font.pixelSize: 18 }
                        Text { text: popup.currentSinkName; color: Theme.primary; font.bold: true; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            sinkModel.clear()
                            sinkListLoader.running = true
                            popup.selectingSink = true
                        }
                    }
                }
            }
        }
    }
}