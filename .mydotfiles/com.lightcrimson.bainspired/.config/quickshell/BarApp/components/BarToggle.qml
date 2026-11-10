import QtQuick
import qs.CustomTheme

// Controlled on/off switch (BA Inspired: blue when on). `checked` is owned by the
// caller; a click only emits clicked().
Rectangle {
    id: root
    property bool checked: false
    signal clicked()

    width: 44; height: 24; radius: 12
    color: checked ? Theme.blue : Theme.mist
    border.color: checked ? Theme.blue : Theme.line; border.width: 1
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
        x: root.checked ? parent.width - width - 3 : 3
        y: 3; width: 18; height: 18; radius: 9
        color: Theme.accentInk
        border.color: root.checked ? "transparent" : Theme.line
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
