import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

BarPopup {
    id: root
    ipcTarget: "bar-power"
    onOpened: root.selectedIndex = 0

    // Keyboard selection state
    property int selectedIndex: 0
    property var powerActions: [
        { icon: "󰌾", label: "Lock",     action: ["hyprlock"] },
        { icon: "󰤄", label: "Suspend",  action: ["systemctl", "suspend"] },
        { icon: "󰍃", label: "Log Out",  action: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { icon: "󰑓", label: "Reboot",   action: ["systemctl", "reboot"] },
        { icon: "󰐥", label: "Shutdown", action: ["systemctl", "poweroff"] }
    ]

    function activate(i) {
        Sys.run(root.powerActions[i].action)
        root.active = false
    }

    // Keyboard navigation + activation
    FocusScope {
        anchors.fill: parent
        focus: root.active
        Keys.onPressed: (event) => {
            let n = root.powerActions.length
            if (event.key === Qt.Key_Escape) {
                root.active = false; event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.selectedIndex = (root.selectedIndex - 1 + n) % n; event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) {
                root.selectedIndex = (root.selectedIndex + 1) % n; event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.activate(root.selectedIndex); event.accepted = true
            }
        }
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
        property int idx: 0
        // Highlighted by either mouse hover or keyboard selection
        property bool highlighted: mouseArea.containsMouse || root.selectedIndex === idx

        Layout.preferredWidth: 110
        Layout.preferredHeight: 120
        radius: 20

        // 3. Smooth color transitions
        color: highlighted ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.surface_container_high
        border.color: highlighted ? Theme.primary : "transparent"
        border.width: 1

        // 4. Tactile click & hover scale
        scale: mouseArea.pressed ? 0.92 : (highlighted ? 1.05 : 1.0)

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
            // Keep keyboard selection in sync when hovering with the mouse
            onContainsMouseChanged: if (containsMouse) root.selectedIndex = btn.idx
            onClicked: root.activate(btn.idx)
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

        Shadow {}

        Rectangle {
            anchors.fill: parent; color: Theme.background; border.color: Theme.withAlpha(Theme.primary, 0.8)
            border.width: 2; radius: 30; opacity: 0.95
        }

        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent; anchors.margins: 30; spacing: 15
            Repeater {
                model: root.powerActions
                PowerButton {
                    required property int index
                    required property var modelData
                    idx: index
                    icon: modelData.icon
                    label: modelData.label
                    action: modelData.action
                }
            }
        }
    }
    
}