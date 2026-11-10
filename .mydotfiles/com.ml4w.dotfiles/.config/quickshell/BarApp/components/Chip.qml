import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// A small pill: an option in a choice row (delay, monitor, power profile) or
// an on/off toggle (mic, system audio). Filled when `selected`.
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool selected: false
    signal clicked()

    implicitHeight: 28
    implicitWidth: row.implicitWidth + 20
    radius: height / 2
    color: selected ? Theme.primary
         : mouse.containsMouse && enabled ? Theme.withAlpha(Theme.primary, 0.16) : Theme.withAlpha(Theme.primary, 0.08)
    Behavior on color { ColorAnimation { duration: 150 } }

    readonly property color fg: selected ? Theme.background : Theme.primary

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.fg
            opacity: root.enabled ? 1 : 0.4
            font.pixelSize: 13
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.fg
            opacity: root.enabled ? 1 : 0.4
            font.pixelSize: 11; font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
