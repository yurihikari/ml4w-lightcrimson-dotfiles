import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// A small slanted tab: an option in a choice row or an on/off toggle. Solid
// blue with white text when `selected`, misty otherwise.
Item {
    id: root
    property string icon: ""
    property string text: ""
    property bool selected: false
    signal clicked()

    implicitHeight: 28
    implicitWidth: row.implicitWidth + 30

    Slanted {
        anchors.fill: parent
        slant: 7
        fill: root.selected ? Theme.blue : mouse.containsMouse && root.enabled ? Qt.darker(Theme.mist, 1.06) : Theme.mist
        fill2: root.selected ? Qt.lighter(Theme.blue, 1.12) : fill
        stroke: root.selected ? "transparent" : Theme.line
        strokeWidth: 1
    }
    scale: mouse.pressed && enabled ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

    readonly property color fg: selected ? Theme.accentInk : Theme.ink

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
            font.family: Theme.fontFamily
            font.pixelSize: 11; font.weight: Font.ExtraBold
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
