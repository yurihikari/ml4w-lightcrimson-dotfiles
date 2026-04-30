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
    visible: active
    
    // Multi-monitor support
    screen: modelData 

    // Fullscreen Overlay
    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // Click outside/on the background to close
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.active = false
        }
    }

    // Local Executor for power actions
    Process {
        id: powerExec
        function run(args) {
            command = args
            running = true
        }
    }

    // --- FULLSCREEN BLUR BACKGROUND ---
    Rectangle {
        anchors.fill: parent
        color: Theme.background
        opacity: 0.8 // Deep blur base
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
        color: Theme.surface_container_high
        border.color: mouseArea.containsMouse ? Theme.primary : "transparent"
        border.width: 1
        

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: btn.icon
                color: Theme.primary
                font.pixelSize: 32
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: btn.label
                color: Theme.primary
                font.pixelSize: 12
                font.bold: true
                opacity: 0.8
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                btn.opacity = 0.9
            }
            onExited: {
                btn.opacity = 1.0
            }
            onClicked: {
                powerExec.run(btn.action)
                root.active = false
            }
        }
    }

    // --- BUTTONS CONTAINER ---
    Rectangle {
        // wifdth takes the size of its content
        width: 5 * 110 + 4 * 15 + 60 // 5 buttons * button width + 4 spaces * spacing + margins
        height: 180
        anchors.centerIn: parent
        radius: 30
        color: "transparent"

        // Inner frosted container
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 1
            radius: 30
            opacity: 0.95
        }

        MouseArea { anchors.fill: parent } // Prevent clicking container from closing menu

        RowLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 15

            PowerButton {
                icon: "󰌾"
                label: "Lock"
                action: ["hyprlock"]
            }

            PowerButton {
                icon: "󰤄"
                label: "Suspend"
                action: ["systemctl", "suspend"]
            }

            PowerButton {
                icon: "󰍃"
                label: "Log Out"
                action: ["hyprctl", "dispatch", "exit"]
            }

            PowerButton {
                icon: "󰑓"
                label: "Reboot"
                action: ["systemctl", "reboot"]
            }

            PowerButton {
                icon: "󰐥"
                label: "Shutdown"
                action: ["systemctl", "poweroff"]
            }
        }
    }
}