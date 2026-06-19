import QtQuick
import qs.CustomTheme

// Controlled on/off switch: `checked` is owned by the caller (bound to real
// state) and the knob follows it. Click only emits clicked(); the caller runs
// the action and the state updates on the next poll.
Rectangle {
    id: root
    property bool checked: false
    signal clicked()

    width: 44; height: 24; radius: 12
    color: checked ? Theme.primary : "transparent"
    border.color: Theme.primary; border.width: 2
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
        x: root.checked ? parent.width - width - 3 : 3
        y: 3; width: 18; height: 18; radius: 9
        color: root.checked ? Theme.background : Theme.primary
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
