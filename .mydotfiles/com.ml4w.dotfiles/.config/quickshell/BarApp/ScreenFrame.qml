import Quickshell
import Quickshell.Wayland
import QtQuick
import "../CustomTheme"

// This file creates 3 windows to complete the frame
ShellRoot {
    // Inside ScreenFrame.qml - Update the Bottom PanelWindow
    PanelWindow {
        anchors { bottom: true; left: true; right: true }
        height: 30 // 10px bar + 20px corners
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"

        // The Bottom Horizontal Strip
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 10
            color: Theme.background
        }

        // INSIDE CORNER: Top Left
        Canvas {
            x: 10
            y: 0
            width: 20
            height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = Theme.background;
                ctx.moveTo(0, 20);
                ctx.lineTo(20, 20);
                ctx.arcTo(0, 20, 0, 0, 20);
                ctx.closePath();
                ctx.fill();
            }
        }

        // INSIDE CORNER: Top Right
        Canvas {
            x: parent.width - 30
            y: 0
            width: 20
            height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = Theme.background;
                ctx.moveTo(20, 20);
                ctx.lineTo(0, 20);
                ctx.arcTo(20, 20, 20, 0, 20);
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    // Left Frame
    PanelWindow {
        anchors { top: true; bottom: true; left: true }
        width: 10
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.margins.top: 0 // Leave space for Top Bar
        WlrLayershell.margins.bottom: 0 // Leave space for Bottom Bar
        WlrLayershell.margins.left: 0
        exclusionMode: WlrLayershell.Ignore
        
        Rectangle {
            anchors.fill: parent
            radius: 0
            color: Theme.background
            opacity: 1
            border.color: Theme.background
            border.width: 1
        }
    }

    // Right Frame
    PanelWindow {
        anchors { top: true; bottom: true; right: true }
        width: 10
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.margins.top: 0
        WlrLayershell.margins.bottom: 0
        WlrLayershell.margins.right: 0
        exclusionMode: WlrLayershell.Ignore
        
        Rectangle {
            anchors.fill: parent
            radius: 0
            color: Theme.background
            opacity: 1
            border.color: Theme.background
            border.width: 2
        }
    }
}