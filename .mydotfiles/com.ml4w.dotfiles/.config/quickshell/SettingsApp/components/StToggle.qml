import QtQuick
import qs.CustomTheme

// Themed on/off switch.
//
// Two modes:
//  • default          — self-toggling. Click flips `checked` and emits toggled(checked).
//  • controlled: true — the parent owns `checked` (usually bound to real state).
//                       Click does NOT change `checked`; it only emits toggled(requestedValue).
//                       Use this when the change must be confirmed first (e.g. a polkit
//                       prompt) so the knob follows the real status, not the click.
Rectangle {
    id: root
    property bool checked: false
    property bool controlled: false
    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 26
    radius: height / 2
    color: checked ? Theme.primary : "transparent"
    border.color: Theme.primary
    border.width: 2
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
        id: knob
        width: parent.height - 8          // inset evenly from the track
        height: width
        radius: width / 2
        y: (parent.height - height) / 2   // vertically centered
        x: root.checked ? parent.width - width - 4 : 4
        color: root.checked ? Theme.background : Theme.primary
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.controlled) {
                root.toggled(!root.checked)        // request only; parent decides
            } else {
                root.checked = !root.checked
                root.toggled(root.checked)
            }
        }
    }
}
