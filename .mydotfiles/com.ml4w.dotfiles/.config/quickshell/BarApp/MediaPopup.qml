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
    anchors { 
        top: true
        bottom: true
        left: true
        right: true 
    }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // --- INTERNAL COMPONENTS ---
    component AppButton: Rectangle {
        id: appBtn
        property string icon: ""
        property string cmd: ""
        property string check: ""
        width: 44
        height: 44
        radius: 12
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
            onEntered: {
                appBtn.opacity = 0.7
            }
            onExited: {
                appBtn.opacity = 1.0
            }
            onClicked: {
                executor.run(["bash", "-c", cmd])
            }
        }

        Process {
            running: true
            command: ["bash", "-c", "command -v " + (check !== "" ? check : cmd.split(" ")[0])]
            onExited: {
                appBtn.visible = (exitCode === 0)
            }
        }
    }

    // --- ORIGINAL CAVA ENGINE ---
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
    property string currentSink: "Default"
    Process {
        id: sinkGetter
        running: popup.active
        command: ["bash", "-c", "pactl get-default-sink | sed 's/.*\\.//'"]
        stdout: SplitParser { 
            onRead: { 
                popup.currentSink = data.trim() 
            } 
        }
    }

    Timer {
        interval: 2000
        running: popup.active
        repeat: true
        onTriggered: {
            sinkGetter.running = true
        }
    }

    MouseArea { 
        anchors.fill: parent
        onClicked: {
            popup.active = false
        }
    }

    Rectangle {
        id: container
        width: 550
        height: 320 
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 30
        color: "transparent"
        border.color: "transparent"
        border.width: 2
        // Background rectangle with reduced opacity for blur effect
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8 // Only the background is transparent
        }

        MouseArea { 
            anchors.fill: parent 
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 20

            // --- TOP SECTION ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 25

                Item {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    Canvas {
                        id: cavaCanvas
                        anchors.fill: parent
                        renderTarget: Canvas.FramebufferObject
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var centerX = width / 2
                            var centerY = height / 2
                            var innerRadius = 55
                            var barCount = 100
                            ctx.strokeStyle = Theme.primary
                            ctx.lineWidth = 2.5
                            ctx.lineCap = "round"
                            for (var i = 0; i < barCount; i++) {
                                var val = parseInt(popup.cavaData[i]) || 0
                                var angle = (i * (360 / barCount)) * (Math.PI / 180)
                                var h = (val / 200) * 25
                                if (h < 2) {
                                    h = 2
                                }
                                var x1 = centerX + Math.cos(angle) * innerRadius
                                var y1 = centerY + Math.sin(angle) * innerRadius
                                var x2 = centerX + Math.cos(angle) * (innerRadius + h)
                                var y2 = centerY + Math.sin(angle) * (innerRadius + h)
                                ctx.beginPath()
                                ctx.moveTo(x1, y1)
                                ctx.lineTo(x2, y2)
                                ctx.stroke()
                            }
                        }
                    }
                    Rectangle {
                        id: albumArtContainer
                        anchors.centerIn: parent
                        width: 100
                        height: 100
                        radius: 50
                        layer.enabled: true
                        layer.effect: OpacityMask { 
                            maskSource: albumArtMask 
                        }
                        Image { 
                            id: albumArt
                            anchors.fill: parent
                            source: mediaData.artUrl
                            fillMode: Image.PreserveAspectCrop 
                        }
                        Text { 
                            anchors.centerIn: parent
                            text: "󰎆"
                            color: Theme.primary
                            font.pixelSize: 35
                            opacity: 0.3
                            visible: albumArt.status !== Image.Ready 
                        }
                    }
                    Rectangle { 
                        id: albumArtMask
                        width: 100
                        height: 100
                        radius: 50
                        visible: false 
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 320
                    spacing: 20
                    ColumnLayout {
                        spacing: 2
                        Text { text: mediaData.title; color: Theme.primary; font.bold: true; font.pixelSize: 22; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: mediaData.artist; color: Theme.primary; opacity: 0.7; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 40
                        Text { text: "󰒮"; color: Theme.primary; font.pixelSize: 32; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "previous"]) } } }
                        Text { text: mediaData.status === "Playing" ? "󰏤" : "󰐊"; color: Theme.primary; font.pixelSize: 48; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "play-pause"]) } } }
                        Text { text: "󰒭"; color: Theme.primary; font.pixelSize: 32; MouseArea { anchors.fill: parent; onClicked: { executor.run(["playerctl", "-p", mediaData.playerName, "next"]) } } }
                    }
                }

                Rectangle { Layout.fillHeight: true; width: 2; color: Theme.primary; opacity: 0.1 }

                ColumnLayout {
                    Layout.preferredWidth: 80
                    spacing: 15
                    Text { text: "MUSIC APPS"; color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
                    AppButton { icon: "󰓇"; cmd: "spotify" }
                    AppButton { icon: "󰎆"; cmd: "pear-desktop" }
                    AppButton { icon: "󱍙"; cmd: "kitty ncmpcpp"; check: "ncmpcpp" }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 2; color: Theme.primary; opacity: 0.1 }

            // --- BOTTOM SECTION ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                RowLayout {
                    spacing: 12
                    Text { text: sysInfo.volValue > 0 ? "󰕾" : "󰝟"; color: Theme.primary; font.pixelSize: 22 }
                    Rectangle {
                        Layout.preferredWidth: 150
                        height: 8
                        radius: 4
                        color: Theme.background
                        Rectangle {
                            width: parent.width * sysInfo.volValue
                            height: parent.height
                            radius: 4
                            color: Theme.primary
                        }
                        MouseArea {
                            anchors.fill: parent
                            function updateVol(mouse) {
                                let p = Math.max(0, Math.min(1, mouse.x / width))
                                sysInfo.volValue = p
                                executor.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", p.toFixed(2)])
                            }
                            onPressed: {
                                updateVol(mouse)
                            }
                            onPositionChanged: {
                                updateVol(mouse)
                            }
                        }
                    }
                    Text { text: Math.round(sysInfo.volValue * 100) + "%"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 200
                    height: 44
                    radius: 15
                    color: Theme.background
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 15
                        Text { text: "󰓃"; color: Theme.primary; font.pixelSize: 18 }
                        Text { 
                            text: popup.currentSink
                            color: Theme.primary
                            font.bold: true
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true 
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            executor.run(["bash", "-c", "pactl set-default-sink $(pactl list short sinks | awk '{print $2}' | grep -v $(pactl get-default-sink) | head -n1)"])
                            sinkGetter.running = true 
                        }
                    }
                }
            }
        }
    }
}