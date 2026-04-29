import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    visible: active
    
    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    
    // Set to None to fix keyboard issues
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: popup.active = false
    }

    Rectangle {
        width: 350
        height: 120
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.horizontalCenter: parent.horizontalCenter
        
        radius: 20
        color: Theme.background
        border.color: Theme.primary
        border.width: 1

        // Block internal clicks from closing
        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 15

            // Album Art
            Rectangle {
                width: 90; height: 90; radius: 10
                color: Theme.surface_variant; clip: true
                Text { anchors.centerIn: parent; text: "󰎆"; color: Theme.primary; font.pixelSize: 30; opacity: 0.3; visible: albumArt.status !== Image.Ready }
                Image { id: albumArt; anchors.fill: parent; source: mediaData.artUrl; fillMode: Image.PreserveAspectCrop }
            }

            // Info and Controls
            ColumnLayout {
                Layout.fillWidth: true; spacing: 5

                Text {
                    text: mediaData.title
                    color: Theme.primary; font.bold: true; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true
                }

                Text {
                    text: mediaData.artist
                    color: Theme.primary; opacity: 0.8; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: 25
                    Text { text: "󰒮"; color: Theme.primary; font.pixelSize: 20; MouseArea { anchors.fill: parent; onClicked: executor.run(["playerctl", "previous"]) } }
                    Text { text: mediaData.status === "Playing" ? "󰏤" : "󰐊"; color: Theme.primary; font.pixelSize: 28; MouseArea { anchors.fill: parent; onClicked: executor.run(["playerctl", "play-pause"]) } }
                    Text { text: "󰒭"; color: Theme.primary; font.pixelSize: 20; MouseArea { anchors.fill: parent; onClicked: executor.run(["playerctl", "next"]) } }
                }
            }
        }
    }
}