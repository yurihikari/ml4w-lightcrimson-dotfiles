import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

PanelWindow {
    id: root
    property bool active: false
    
    // 1. Keep window alive while the exit animation is running
    property bool isAnimating: false
    visible: active || isAnimating
    
    screen: modelData 
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    MouseArea {
        anchors.fill: parent
        onClicked: root.active = false
    }

    Process {
        id: powerExec
        function run(args) { command = args; running = true }
    }

    // --- FULLSCREEN BLUR BACKGROUND ---
    Rectangle {
        anchors.fill: parent
        color: Theme.background
        // 2. Animate background fade
        opacity: root.active ? 0.8 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    // --- REUSABLE POWER BUTTON COMPONENT ---
    component PowerButton: Rectangle {
        id: btn
        property string icon: ""
        property string label: ""
        property var action: []

        Layout.preferredWidth: 110
        Layout.preferredHeight: 120
        radius: 20
        
        // 3. Smooth color transitions
        color: mouseArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.surface_container_high
        border.color: mouseArea.containsMouse ? Theme.primary : "transparent"
        border.width: 1

        // 4. Tactile click & hover scale
        scale: mouseArea.pressed ? 0.92 : (mouseArea.containsMouse ? 1.05 : 1.0)
        
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        ColumnLayout {
            anchors.centerIn: parent; spacing: 10
            Text { text: btn.icon; color: Theme.primary; font.pixelSize: 32; Layout.alignment: Qt.AlignHCenter }
            Text { text: btn.label; color: Theme.primary; font.pixelSize: 12; font.bold: true; opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                powerExec.run(btn.action)
                root.active = false
            }
        }
    }

    // --- BUTTONS CONTAINER (Animated) ---
    Rectangle {
        id: container
        width: 5 * 110 + 4 * 15 + 60
        height: 180
        anchors.centerIn: parent
        radius: 30
        color: "transparent"

        // 5. Entrance/Exit animations for the main container
        opacity: root.active ? 1.0 : 0.0
        scale: root.active ? 1.0 : 0.85
        y: root.active ? parent.height/2 - height/2 : parent.height/2 - height/2 + 30 // Slide up effect
        
        Behavior on opacity { 
            NumberAnimation { 
                duration: 250; easing.type: Easing.OutCubic 
                onRunningChanged: if (!running && !root.active) root.isAnimating = false 
            } 
        }
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

        Rectangle {
            anchors.fill: parent; color: Theme.background; border.color: Theme.primary
            border.width: 1; radius: 30; opacity: 0.95
        }

        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent; anchors.margins: 30; spacing: 15
            PowerButton { icon: "󰌾"; label: "Lock"; action: ["hyprlock"] }
            PowerButton { icon: "󰤄"; label: "Suspend"; action: ["systemctl", "suspend"] }
            PowerButton { icon: "󰍃"; label: "Log Out"; action: ["hyprctl", "dispatch", "exit"] }
            PowerButton { icon: "󰑓"; label: "Reboot"; action: ["systemctl", "reboot"] }
            PowerButton { icon: "󰐥"; label: "Shutdown"; action: ["systemctl", "poweroff"] }
        }
    }
    
    // Trigger animation tracker
    onActiveChanged: if (active) isAnimating = true
}