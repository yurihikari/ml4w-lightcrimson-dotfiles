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
    
    // 1. Wayland-safe exit animation state
    property bool isAnimating: false
    visible: active || isAnimating
    
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

    property var p: bar.activePlayer

    function formatTime(s) {
        if (!s || isNaN(s) || s < 0) return "0:00"
        let mins = Math.floor(s / 60)
        let secs = Math.floor(s % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    // Local executor just in case
    Process {
        id: executor
        function run(args) { command = args; running = true }
    }

    // --- STATE & MODELS ---
    property bool selectingSink: false
    ListModel { id: sinkModel }

    // --- INTERNAL COMPONENTS ---
    // Glass-style App Button
    component AppButton: Rectangle {
        id: appBtn
        property string icon: ""
        property string cmd: ""
        property string check: ""
        width: 44; height: 44; radius: 14
        visible: false 
        Layout.alignment: Qt.AlignHCenter
        
        // Soft glass styling
        color: btnMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
        border.width: 1

        scale: btnMouse.pressed ? 0.9 : (btnMouse.containsMouse ? 1.08 : 1.0)
        
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Text { 
            anchors.centerIn: parent
            text: icon
            color: Theme.primary
            font.pixelSize: 20
            opacity: 0.9
        }

        MouseArea { 
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                executor.run([
                    "hyprctl",
                    "dispatch",
                    "hl.dsp.exec_cmd(\"" + cmd + "\")"
                ])
                popup.active = false
            }
        }

        Process {
            running: true
            command: ["bash", "-c", "command -v " + (check !== "" ? check : cmd.split(" ")[0])]
            onExited: appBtn.visible = (exitCode === 0)
        }
    }

    // --- CAVA ENGINE ---
    property var cavaData: []
    property string cavaConfigPath: "/tmp/qs_cava_bar.ini"

    Process {
        id: cavaConfigWriter
        command: ["bash", "-c",
            "cat > /tmp/qs_cava_bar.ini << 'EOF'\n" +
            "[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=200\nbar_delimiter=32\nbars=100\nEOF"
        ]
        running: true
    }

    Process {
        id: cava
        running: (popup.active || popup.isAnimating) && cavaConfigWriter.running === false
        command: ["cava", "-p", popup.cavaConfigPath]
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
        running: popup.active || popup.isAnimating
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
        interval: 5000; running: popup.active; repeat: true
        onTriggered: sinkGetter.running = true
    }

    Timer {
        interval: 1000; repeat: true
        running: (popup.active || popup.isAnimating) && p !== null && p.playbackState === MprisPlaybackState.Playing
        onTriggered: { if (p) p.positionChanged() }
    }

    // 2. Track animation state
    onActiveChanged: if (active) isAnimating = true

    // Click outside to close
    MouseArea { 
        anchors.fill: parent
        onClicked: {
            if (popup.selectingSink) popup.selectingSink = false
            else popup.active = false
        }
    }

    // --- MAIN POPUP CONTAINER ---
    Rectangle {
        id: container
        width: 560; height: 410 // Slightly expanded for breathing room
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 30; color: "transparent"

        // 3. Smooth Entrance / Exit Animations
        transformOrigin: Item.Top
        opacity: popup.active ? 1.0 : 0.0
        scale: popup.active ? 1.0 : 0.90
        y: popup.active ? 45 : 25 

        Behavior on opacity { 
            NumberAnimation { 
                duration: 250; easing.type: Easing.OutCubic 
                onRunningChanged: if (!running && !popup.active) popup.isAnimating = false 
            } 
        }
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

        // Blur-friendly background
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
            border.width: 2
            radius: 30
            opacity: 0.8 // Standardized Hyprland blur opacity
        }
        
        MouseArea { anchors.fill: parent } // Prevent click-through

        // --- SINK SELECTOR OVERLAY ---
        Rectangle {
            anchors.fill: parent; anchors.margins: 10; z: 100
            radius: 25; color: "transparent"
            
            visible: opacity > 0
            opacity: popup.selectingSink ? 1.0 : 0.0
            scale: popup.selectingSink ? 1.0 : 0.95
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

            // Backdrop for overlay readability
            Rectangle { anchors.fill: parent; radius: 25; color: Theme.background; opacity: 0.95 }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 25; spacing: 15
                Text { text: "Select Audio Output"; color: Theme.primary; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
                
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    color: "transparent"; radius: 15; clip: true
                    ListView {
                        id: sinkListView; anchors.fill: parent; anchors.margins: 10; model: sinkModel; spacing: 8
                        delegate: Rectangle {
                            width: sinkListView.width; height: 48; radius: 14
                            
                            property bool isCurrent: fullName === popup.currentSinkFull
                            // Glass card look for items
                            color: isCurrent ? Theme.primary : (sinkDelegateMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.03))
                            border.color: isCurrent ? "transparent" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                            border.width: 1
                            
                            scale: sinkDelegateMouse.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                                Text { text: "󰓃"; color: isCurrent ? Theme.background : Theme.primary; font.pixelSize: 16; opacity: isCurrent ? 1.0 : 0.8 }
                                Text { text: displayName; color: isCurrent ? Theme.background : Theme.primary; font.bold: isCurrent; font.pixelSize: 13; Layout.fillWidth: true; opacity: isCurrent ? 1.0 : 0.9 }
                                Text { text: "󰄬"; color: Theme.background; visible: isCurrent; font.bold: true }
                            }
                            MouseArea { 
                                id: sinkDelegateMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: { executor.run(["pactl", "set-default-sink", fullName]); popup.selectingSink = false; sinkGetter.running = true } 
                            }
                        }
                    }
                }
                
                // Glass style close button
                Rectangle {
                    Layout.preferredWidth: 140; Layout.preferredHeight: 40; radius: 20
                    color: closeSinkMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2); border.width: 1; Layout.alignment: Qt.AlignHCenter
                    
                    scale: closeSinkMouse.pressed ? 0.95 : (closeSinkMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text { anchors.centerIn: parent; text: "Close"; color: Theme.primary; font.bold: true; opacity: 0.9 }
                    MouseArea { 
                        id: closeSinkMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: popup.selectingSink = false 
                    }
                }
            }
        }

        // --- MAIN CONTENT ---
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 25; spacing: 20
            
            // Fade out when overlay is open
            opacity: popup.selectingSink ? 0.0 : 1.0
            enabled: !popup.selectingSink
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

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
                        height: 32
                        width: pillLabel.implicitWidth + 36
                        radius: 16
                        
                        // Glass pill styling
                        color: isSelected ? Theme.primary : (pillMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05))
                        border.color: isSelected ? "transparent" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        
                        scale: pillMouse.pressed ? 0.95 : (pillMouse.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 200 } }

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
                                opacity: isSelected ? 1.0 : 0.8
                                Behavior on color { ColorAnimation { duration: 200 } }
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
                                opacity: isSelected ? 1.0 : 0.8
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: bar.activePlayer = modelData
                        }
                    }
                }
            }

            // --- MEDIA DISPLAY ROW ---
            RowLayout {
                Layout.fillWidth: true; spacing: 25

                // Album art + cava
                Item {
                    Layout.preferredWidth: 160; Layout.fillHeight: true
                    Canvas {
                        id: cavaCanvas; anchors.fill: parent
                        renderTarget: Canvas.FramebufferObject
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
                            font.pixelSize: 35; opacity: 0.2
                            visible: albumArt.status !== Image.Ready
                        }
                    }
                    Rectangle { id: albumArtMask; width: 100; height: 100; radius: 50; visible: false }
                }

                // Title, artist, controls
                ColumnLayout {
                    Layout.fillWidth: true; Layout.maximumWidth: 320; spacing: 22

                    ColumnLayout {
                        spacing: 4
                        Text {
                            text: p ? (p.trackTitle || "No Media") : "No Media"
                            color: Theme.primary; font.bold: true; font.pixelSize: 22
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: p ? (p.trackArtist || "") : ""
                            color: Theme.primary; opacity: 0.6; font.pixelSize: 15
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                    }

                    // --- MEDIA CONTROLS ---
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter; spacing: 15
                        
                        // Previous
                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: prevMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                            opacity: (p && p.canGoPrevious) ? 1.0 : 0.3
                            scale: prevMouse.pressed ? 0.85 : (prevMouse.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            Text { anchors.centerIn: parent; text: "󰒮"; color: Theme.primary; font.pixelSize: 28; opacity: 0.9 }
                            MouseArea { 
                                id: prevMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { if (p && p.canGoPrevious) p.previous() } 
                            }
                        }
                        
                        // Play/Pause (Prominent solid button)
                        Rectangle {
                            width: 60; height: 60; radius: 30
                            color: (p && p.canTogglePlaying) ? (playMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9) : Theme.primary) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                            scale: playMouse.pressed ? 0.85 : (playMouse.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: (p && p.playbackState === MprisPlaybackState.Playing) ? "󰏤" : "󰐊"
                                color: Theme.background; font.pixelSize: 32
                            }
                            MouseArea { 
                                id: playMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { if (p && p.canTogglePlaying) p.togglePlaying() } 
                            }
                        }
                        
                        // Next
                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: nextMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                            opacity: (p && p.canGoNext) ? 1.0 : 0.3
                            scale: nextMouse.pressed ? 0.85 : (nextMouse.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            Text { anchors.centerIn: parent; text: "󰒭"; color: Theme.primary; font.pixelSize: 28; opacity: 0.9 }
                            MouseArea { 
                                id: nextMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { if (p && p.canGoNext) p.next() } 
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; width: 1; color: Theme.primary; opacity: 0.1 }

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
                spacing: 6

                Rectangle {
                    id: sliderTrack
                    Layout.fillWidth: true
                    height: 10; radius: 5 // Slightly thicker for modern look
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)

                    Rectangle {
                        width: (p && p.lengthSupported && p.length > 0)
                            ? parent.width * Math.min(1, p.position / p.length)
                            : 0
                        height: parent.height; radius: 5
                        color: Theme.primary
                        opacity: 0.9
                        Behavior on width { 
                            enabled: !sliderKnob.dragging
                            NumberAnimation { duration: 900; easing.type: Easing.Linear } 
                        }
                    }

                    Rectangle {
                        id: sliderKnob
                        property bool dragging: false
                        x: (p && p.lengthSupported && p.length > 0)
                            ? (sliderTrack.width * Math.min(1, p.position / p.length)) - width / 2
                            : -width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18; radius: 9
                        
                        scale: (sliderMouse.containsMouse || dragging) ? 1.3 : 1.0
                        color: Theme.primary
                        
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        Behavior on x {
                            enabled: !sliderKnob.dragging
                            NumberAnimation { duration: 900; easing.type: Easing.Linear }
                        }
                    }

                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        anchors.margins: -12 
                        hoverEnabled: true
                        preventStealing: true

                        function seek(mouse) {
                            if (!p || !p.positionSupported) return
                            let ratio = Math.max(0, Math.min(1, mouse.x / width))
                            let target = ratio * p.length
                            p.position = target
                        }

                        onPressed: { sliderKnob.dragging = true; seek(mouse) }
                        onPositionChanged: { if (pressed) seek(mouse) }
                        onReleased: { seek(mouse); sliderKnob.dragging = false }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: formatTime(p ? p.position : 0)
                        color: Theme.primary; font.pixelSize: 11; opacity: 0.5
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: formatTime(p ? p.length : 0)
                        color: Theme.primary; font.pixelSize: 11; opacity: 0.5
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // --- BOTTOM: VOLUME + SINK ---
            RowLayout {
                Layout.fillWidth: true; spacing: 20

                RowLayout {
                    spacing: 12
                    
                    // Circular Volume Button
                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: muteMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                        scale: muteMouse.pressed ? 0.8 : (muteMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text { 
                            anchors.centerIn: parent
                            text: sysInfo.isMuted ? "󰝟" : (sysInfo.volValue > 0.6 ? "󰕾" : (sysInfo.volValue > 0.2 ? "󰖀" : "󰕿"))
                            color: sysInfo.isMuted ? Theme.accent : Theme.primary
                            font.pixelSize: 22
                            opacity: 0.9
                        }
                        
                        MouseArea {
                            id: muteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: executor.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 150; height: 10; radius: 5; 
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        
                        Rectangle {
                            width: parent.width * sysInfo.volValue; height: parent.height; radius: 5
                            color: sysInfo.isMuted ? Theme.accent : Theme.primary 
                            opacity: 0.9
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10 
                            cursorShape: Qt.PointingHandCursor
                            function updateVol(mouse) {
                                let pv = Math.max(0, Math.min(1, mouse.x / width))
                                sysInfo.volValue = pv
                                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pv.toFixed(2)])
                            }
                            onPressed: updateVol(mouse)
                            onPositionChanged: updateVol(mouse)
                        }
                    }
                    Text { text: Math.round(sysInfo.volValue * 100) + "%"; color: Theme.primary; font.bold: true; font.pixelSize: 13; opacity: 0.9 }
                }

                Item { Layout.fillWidth: true }

                // --- SINK SELECT BUTTON (Glass Card) ---
                Rectangle {
                    Layout.preferredWidth: 220; height: 44; radius: 22
                    
                    color: sinkBtnMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1
                    
                    scale: sinkBtnMouse.pressed ? 0.96 : (sinkBtnMouse.containsMouse ? 1.03 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                        Text { text: "󰓃"; color: Theme.primary; font.pixelSize: 18; opacity: 0.8 }
                        Text { text: popup.currentSinkName; color: Theme.primary; font.bold: true; font.pixelSize: 12; opacity: 0.9; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    MouseArea {
                        id: sinkBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
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