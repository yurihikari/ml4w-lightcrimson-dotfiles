import Quickshell
import Quickshell.Wayland
import Quickshell.Io // THE FIX: Required for the click logic
import QtQuick
import "../CustomTheme"

Item {
    id: root
    
    // Property passed from Variants in shell.qml
    property var screen
    property var modelData
    onModelDataChanged: screen = modelData

    // Local process to trigger your other Quickshell apps
    Process { 
        id: ipcExec
        function call(target) { 
            command = ["qs", "ipc", "call", target, "toggle"]
            running = true 
        } 
    }

    // --- BOTTOM FRAME ---
    PanelWindow {
        screen: root.screen
        anchors { bottom: true; left: true; right: true }
        height: 30
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 10
            color: Theme.background; opacity: 0.8
        }

        Canvas {
            opacity: 0.8; x: 10; y: 0; width: 20; height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: { requestPaint() }
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.background
                ctx.moveTo(0, 20); ctx.lineTo(20, 20); ctx.arcTo(0, 20, 0, 0, 20)
                ctx.closePath(); ctx.fill()
            }
        }

        Canvas {
            opacity: 0.8; x: parent.width - 30; y: 0; width: 20; height: 20
            property color syncColor: Theme.background
            onSyncColorChanged: { requestPaint() }
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.background
                ctx.moveTo(20, 20); ctx.lineTo(0, 20); ctx.arcTo(20, 20, 20, 0, 20)
                ctx.closePath(); ctx.fill()
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: dockPopup.active = !dockPopup.active
        }
    }

    // --- LEFT FRAME (CLICK FOR WALLPAPER) ---
    PanelWindow {
        screen: root.screen
        anchors { top: true; bottom: true; left: true }
        width: 10
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"
        
        Rectangle { anchors.fill: parent; color: Theme.background; opacity: 0.8 }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                ipcExec.call("wallpaper")
            }
        }
    }

    // --- RIGHT FRAME (CLICK FOR SIDEBAR) ---
    PanelWindow {
        screen: root.screen
        anchors { top: true; bottom: true; right: true }
        width: 11
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"
        
        Rectangle { anchors.fill: parent; color: Theme.background; opacity: 0.8 }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                ipcExec.call("sidebar")
            }
        }
    }

    DockPopup { id: dockPopup; screen: root.screen }
}