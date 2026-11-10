import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// Screen capture, in the bottom-right corner drawer: screenshots (region,
// window, this screen, all screens; optional delay and annotation), screen
// recording and instant replay, text from the screen (OCR), the colour picker
// with its recent colours, and the latest captures.
ColumnLayout {
    id: root
    property string screenName: ""
    property bool shown: false

    spacing: 12
    onShownChanged: if (shown) { Capture.checkTools(); Capture.refreshRecent() }

    // ── Header ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: "Capture"
                color: Theme.primary
                font.pixelSize: PanelStyle.titleSize; font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: "Screenshots are copied and saved"
                color: Theme.primary; opacity: PanelStyle.dim
                font.pixelSize: PanelStyle.subtitleSize
                elide: Text.ElideRight
            }
        }
        IconButton {
            icon: "󰉋"; size: 30; iconSize: 15
            onClicked: { Corners.closeAll(); Capture.openFolder(Capture.shotDir) }
        }
    }

    // ── Screenshot ──────────────────────────────────────────────────────────
    SectionLabel { text: "Screenshot" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [
                { id: "region", icon: "󰩭", label: "Region" },
                { id: "window", icon: "󰖯", label: "Window" },
                { id: "screen", icon: "󰍹", label: "Screen" },
                { id: "all", icon: "󰍺", label: "All" }
            ]
            ActionTile {
                required property var modelData
                Layout.fillWidth: true
                icon: modelData.icon; label: modelData.label
                accent: modelData.id === "region"
                enabled: !Capture.shooting
                onClicked: Capture.screenshot(modelData.id, root.screenName)
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            text: "Delay"
            color: Theme.primary; opacity: PanelStyle.dim
            font.pixelSize: 11; font.bold: true
            Layout.rightMargin: 2
        }
        Repeater {
            model: [0, 3, 5, 10]
            Chip {
                required property int modelData
                text: modelData === 0 ? "Off" : modelData + "s"
                selected: Capture.delay === modelData
                onClicked: Capture.delay = modelData
            }
        }
        Item { Layout.fillWidth: true }
        Chip {
            visible: Capture.editor !== ""
            icon: "󰏫"; text: "Annotate"
            selected: Capture.annotate
            onClicked: Capture.annotate = !Capture.annotate
        }
    }

    // ── Record ──────────────────────────────────────────────────────────────
    SectionLabel { text: "Record" }

    // While recording: time, pause, stop
    Rectangle {
        Layout.fillWidth: true
        visible: Capture.recording
        implicitHeight: 56
        radius: PanelStyle.radiusCard
        color: Theme.withAlpha(Theme.error, 0.14)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16; anchors.rightMargin: 8
            spacing: 10
            Rectangle {
                width: 10; height: 10; radius: 5
                color: Theme.error
                SequentialAnimation on opacity {
                    running: Capture.recording && !Capture.paused
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.25; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: Capture.paused ? "Paused" : "Recording"
                    color: Theme.error
                    font.pixelSize: 13; font.bold: true
                }
                Text {
                    text: Capture.clock(Capture.elapsed)
                    color: Theme.primary; opacity: PanelStyle.dim
                    font.pixelSize: 11; font.family: "monospace"
                }
            }
            Chip {
                icon: Capture.paused ? "󰐊" : "󰏤"
                text: Capture.paused ? "Resume" : "Pause"
                onClicked: Capture.togglePause()
            }
            Chip {
                icon: "󰓛"; text: "Stop"
                selected: true
                onClicked: Capture.stopRecording()
            }
        }
    }

    // Otherwise: what to record, with which sound
    RowLayout {
        Layout.fillWidth: true
        visible: !Capture.recording
        spacing: 8
        ActionTile {
            Layout.preferredWidth: (root.width - 24) / 4
            icon: "󰩭"; label: "Region"
            enabled: Capture.hasRecorder && !Capture.preparing
            onClicked: Capture.record("region", root.screenName)
        }
        ActionTile {
            Layout.preferredWidth: (root.width - 24) / 4
            icon: "󰍹"; label: "Screen"
            enabled: Capture.hasRecorder && !Capture.preparing
            onClicked: Capture.record("screen", root.screenName)
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Chip {
                Layout.fillWidth: true
                icon: Capture.recSystem ? "󰕾" : "󰖁"; text: "System sound"
                selected: Capture.recSystem
                onClicked: Capture.recSystem = !Capture.recSystem
            }
            Chip {
                Layout.fillWidth: true
                icon: Capture.recMic ? "󰍬" : "󰍭"; text: "Microphone"
                selected: Capture.recMic
                onClicked: Capture.recMic = !Capture.recMic
            }
        }
    }

    // Instant replay
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 50
        radius: PanelStyle.radiusCard
        color: PanelStyle.cardFill
        opacity: Capture.hasRecorder ? 1 : 0.5
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 10
            spacing: 10
            Text { text: "󰕧"; color: Theme.primary; font.pixelSize: 17 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Instant replay"
                    color: Theme.primary
                    font.pixelSize: 12; font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: !Capture.hasRecorder ? "Needs gpu-screen-recorder"
                        : Capture.replayOn ? "Keeping the last " + Capture.replaySeconds + " seconds" : "Off"
                    color: Theme.primary; opacity: PanelStyle.dim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            Chip {
                visible: Capture.replayOn
                icon: "󰆓"; text: "Save clip"
                onClicked: Capture.saveReplay()
            }
            BarToggle {
                checked: Capture.replayOn
                enabled: Capture.hasRecorder
                onClicked: Capture.toggleReplay(root.screenName)
            }
        }
    }

    // ── Tools ───────────────────────────────────────────────────────────────
    SectionLabel { text: "Tools" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ActionTile {
            Layout.preferredWidth: (root.width - 24) / 4
            icon: "󰗊"; label: "Text"
            onClicked: Capture.ocr()
        }
        ActionTile {
            Layout.preferredWidth: (root.width - 24) / 4
            icon: "󰈊"; label: "Colour"
            enabled: !Capture.picking
            onClicked: Capture.pickColor()
        }
        // Recent colours (click: copy again)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            Text {
                anchors.centerIn: parent
                visible: Capture.colors.length === 0
                text: "Picked colours\nshow up here"
                horizontalAlignment: Text.AlignHCenter
                color: Theme.primary; opacity: PanelStyle.faint
                font.pixelSize: 11
            }
            Grid {
                anchors.centerIn: parent
                columns: 4
                spacing: 7
                Repeater {
                    model: Capture.colors
                    Rectangle {
                        id: swatch
                        required property string modelData
                        width: 24; height: 24; radius: 8
                        color: modelData
                        border.width: swatchMouse.containsMouse ? 2 : 1
                        border.color: Theme.withAlpha(Theme.primary, swatchMouse.containsMouse ? 0.9 : 0.25)
                        scale: swatchMouse.pressed ? 0.88 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Capture.copyColor(swatch.modelData)
                        }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.topMargin: -6
        visible: Capture.colors.length > 0
        text: "Click a colour to copy it again"
        horizontalAlignment: Text.AlignRight
        color: Theme.primary; opacity: PanelStyle.faint
        font.pixelSize: 10
    }

    // ── Recent captures ─────────────────────────────────────────────────────
    SectionLabel { text: "Recent"; visible: Capture.recent.length > 0 }
    RowLayout {
        Layout.fillWidth: true
        visible: Capture.recent.length > 0
        spacing: 8
        Repeater {
            model: Capture.recent
            ClippingRectangle {
                id: thumb
                required property var modelData
                Layout.preferredWidth: (root.width - 24) / 4
                Layout.preferredHeight: 56
                radius: PanelStyle.radiusControl
                color: PanelStyle.cardFill
                Image {
                    anchors.fill: parent
                    source: "file://" + thumb.modelData.thumb
                    sourceSize.width: 200
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: thumbMouse.containsMouse ? 0.8 : 1
                }
                Rectangle {
                    visible: thumb.modelData.video
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: 20; height: 20; radius: 6
                    color: Theme.withAlpha(Theme.background, 0.8)
                    Text { anchors.centerIn: parent; text: "󰐊"; color: Theme.primary; font.pixelSize: 11 }
                }
                MouseArea {
                    id: thumbMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Corners.closeAll(); Capture.openFile(thumb.modelData.path) }
                }
            }
        }
        // Keep thumbnails left-aligned when there are fewer than four
        Item { Layout.fillWidth: true }
    }
}
