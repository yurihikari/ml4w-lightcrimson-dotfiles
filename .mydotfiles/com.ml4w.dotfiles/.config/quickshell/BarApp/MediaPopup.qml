import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects 
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    visible: active
    
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

    // Convenience alias
    property var p: bar.activePlayer

    function formatTime(s) {
        if (!s || isNaN(s) || s < 0) return "0:00"
        let mins = Math.floor(s / 60)
        let secs = Math.floor(s % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

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
            onEntered: appBtn.opacity = 0.7
            onExited: appBtn.opacity = 1.0
            onClicked: executor.run(["hyprctl", "dispatch", "exec", cmd])
        }

        Process {
            running: true
            command: ["bash", "-c", "command -v " + (check !== "" ? check : cmd.split(" ")[0])]
            onExited: appBtn.visible = (exitCode === 0)
        }
    }

    // --- CAVA ENGINE ---
    property var cavaData: []
    Process {
        id: cava
        running: popup.active
        command: ["bash", "-c", "cava -p <(echo -e '[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=200\nbar_delimiter=32\nbars=100')"]
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
        onTriggered: sinkGetter.running = true
    }

    // --- POSITION TICKER (as per Quickshell docs) ---
    Timer {
        interval: 1000
        repeat: true
        running: popup.active && p !== null && p.playbackState === MprisPlaybackState.Playing
        onTriggered: { if (p) p.positionChanged() }
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

        // --- SINK SELECTOR OVERLAY ---
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
                    Layout.preferredWidth: 140; Layout.preferredHeight: 40; radius: 20
                    color: Theme.background; border.color: Theme.primary; border.width: 1; Layout.alignment: Qt.AlignHCenter
                    Text { anchors.centerIn: parent; text: "Close"; color: Theme.primary; font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: popup.selectingSink = false }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 25; spacing: 20
            opacity: popup.selectingSink ? 0.0 : 1.0
            enabled: !popup.selectingSink

            // --- PLAYER SWITCHER ---
            Row {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                visible: Mpris.players.values.length > 1

                Repeater {
                    model: Mpris.players.values
                    delegate: Rectangle {
                        required property var modelData
                        property bool isSelected: bar.activePlayer === modelData
                        height: 30
                        width: pillLabel.implicitWidth + 36
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
                                    let n = (modelData.identity || "").toLowerCase()
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
                                id: pillLabel
                                text: {
                                    let n = modelData.identity || "Unknown"
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
                            onClicked: bar.activePlayer = modelData
                        }
                    }
                }
            }

            // --- MAIN CONTENT ROW ---
            RowLayout {
                Layout.fillWidth: true; spacing: 25

                // Album art + cava
                Item {
                    Layout.preferredWidth: 160; Layout.fillHeight: true
                    Canvas {
                        id: cavaCanvas; anchors.fill: parent; renderTarget: Canvas.FramebufferObject
                        onPaint: {
                            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                            var centerX = width/2; var centerY = height/2; var innerRadius = 55; var barCount = 100
                            ctx.strokeStyle = Theme.primary; ctx.lineWidth = 2.5; ctx.lineCap = "round"
                            for (var i = 0; i < barCount; i++) {
                                var val = parseInt(popup.cavaData[i]) || 0
                                var angle = (i * (360 / barCount)) * (Math.PI / 180)
                                var h = (val / 200) * 25; if (h < 2) h = 2
                                var x1 = centerX + Math.cos(angle) * innerRadius
                                var y1 = centerY + Math.sin(angle) * innerRadius
                                var x2 = centerX + Math.cos(angle) * (innerRadius + h)
                                var y2 = centerY + Math.sin(angle) * (innerRadius + h)
                                ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
                            }
                        }
                    }
                    Rectangle {
                        id: albumArtContainer; anchors.centerIn: parent; width: 100; height: 100; radius: 50
                        layer.enabled: true
                        layer.effect: OpacityMask { maskSource: albumArtMask }
                        Image {
                            id: albumArt; anchors.fill: parent
                            source: p ? p.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            anchors.centerIn: parent; text: "󰎆"; color: Theme.primary
                            font.pixelSize: 35; opacity: 0.3
                            visible: albumArt.status !== Image.Ready
                        }
                    }
                    Rectangle { id: albumArtMask; width: 100; height: 100; radius: 50; visible: false }
                }

                // Title, artist, controls
                ColumnLayout {
                    Layout.fillWidth: true; Layout.maximumWidth: 320; spacing: 20

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: p ? (p.trackTitle || "No Media") : "No Media"
                            color: Theme.primary; font.bold: true; font.pixelSize: 22
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: p ? (p.trackArtist || "") : ""
                            color: Theme.primary; opacity: 0.7; font.pixelSize: 16
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter; spacing: 40
                        Text {
                            text: "󰒮"; color: Theme.primary; font.pixelSize: 32
                            opacity: (p && p.canGoPrevious) ? 1.0 : 0.3
                            MouseArea { anchors.fill: parent; onClicked: { if (p && p.canGoPrevious) p.previous() } }
                        }
                        Text {
                            text: (p && p.playbackState === MprisPlaybackState.Playing) ? "󰏤" : "󰐊"
                            color: Theme.primary; font.pixelSize: 48
                            opacity: (p && p.canTogglePlaying) ? 1.0 : 0.3
                            MouseArea { anchors.fill: parent; onClicked: { if (p && p.canTogglePlaying) p.togglePlaying() } }
                        }
                        Text {
                            text: "󰒭"; color: Theme.primary; font.pixelSize: 32
                            opacity: (p && p.canGoNext) ? 1.0 : 0.3
                            MouseArea { anchors.fill: parent; onClicked: { if (p && p.canGoNext) p.next() } }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; width: 2; color: Theme.primary; opacity: 0.1 }

                // Music apps
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
                    id: sliderTrack
                    Layout.fillWidth: true
                    height: 6; radius: 3
                    color: Theme.background

                    Rectangle {
                        width: (p && p.lengthSupported && p.length > 0)
                            ? parent.width * Math.min(1, p.position / p.length)
                            : 0
                        height: parent.height; radius: 3
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }

                    Rectangle {
                        id: sliderKnob
                        property bool dragging: false
                        x: (p && p.lengthSupported && p.length > 0)
                            ? (sliderTrack.width * Math.min(1, p.position / p.length)) - width / 2
                            : -width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: 7
                        color: Theme.primary
                        Behavior on x {
                            enabled: !sliderKnob.dragging
                            NumberAnimation { duration: 900; easing.type: Easing.Linear }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        preventStealing: true

                        function seek(mouse) {
                            if (!p || !p.positionSupported) return
                            let ratio = Math.max(0, Math.min(1, mouse.x / width))
                            let target = ratio * p.length
                            p.position = target
                        }

                        onPressed: {
                            sliderKnob.dragging = true
                            seek(mouse)
                        }
                        onPositionChanged: {
                            if (pressed) seek(mouse)
                        }
                        onReleased: {
                            seek(mouse)
                            sliderKnob.dragging = false
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: formatTime(p ? p.position : 0)
                        color: Theme.primary; font.pixelSize: 10; opacity: 0.6
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: formatTime(p ? p.length : 0)
                        color: Theme.primary; font.pixelSize: 10; opacity: 0.6
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: Theme.primary; opacity: 0.1 }

            // --- BOTTOM: VOLUME + SINK ---
            RowLayout {
                Layout.fillWidth: true; spacing: 20

                RowLayout {
                    spacing: 12
                    Text { 
                        text: sysInfo.isMuted ? "󰝟" : (sysInfo.volValue > 0.6 ? "󰕾" : (sysInfo.volValue > 0.2 ? "󰖀" : "󰕿"))
                        color: sysInfo.isMuted ? Theme.accent : Theme.primary
                        font.pixelSize: 22; verticalAlignment: Text.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
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
                                let pv = Math.max(0, Math.min(1, mouse.x / width))
                                sysInfo.volValue = pv
                                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pv.toFixed(2)])
                            }
                            onPressed: updateVol(mouse)
                            onPositionChanged: updateVol(mouse)
                        }
                    }
                    Text { text: Math.round(sysInfo.volValue * 100) + "%"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 200; height: 44; radius: 15
                    color: Theme.background; border.color: Theme.primary; border.width: 1
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
