import Quickshell
import Quickshell.Wayland
import QtQuick
import "../CustomTheme"

Item {
    id: root
    
    // This property will be filled by Variants in shell.qml
    property var screen
    property var modelData
    screen: modelData

    // --- BOTTOM FRAME WINDOW ---
    PanelWindow {
        screen: root.screen
        anchors { bottom: true; left: true; right: true }
        height: 30
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 10
            color: Theme.background
        }

        Canvas {
            x: 10
            y: 0
            width: 20
            height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: { requestPaint() }
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.background
                ctx.moveTo(0, 20)
                ctx.lineTo(20, 20)
                ctx.arcTo(0, 20, 0, 0, 20)
                ctx.closePath()
                ctx.fill()
            }
        }

        Canvas {
            x: parent.width - 30
            y: 0
            width: 20
            height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: { requestPaint() }
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.background
                ctx.moveTo(20, 20)
                ctx.lineTo(0, 20)
                ctx.arcTo(20, 20, 20, 0, 20)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // --- LEFT FRAME WINDOW ---
    PanelWindow {
        screen: root.screen
        anchors { top: true; bottom: true; left: true }
        width: 10
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"
        
        Rectangle {
            anchors.fill: parent
            color: Theme.background
        }
    }

    // --- RIGHT FRAME WINDOW ---
    PanelWindow {
        screen: root.screen
        anchors { top: true; bottom: true; right: true }
        width: 11
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"
        
        Rectangle {
            anchors.fill: parent
            color: Theme.background
        }
    }
}