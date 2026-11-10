import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// BA Inspired's button: slanted. `accent` is the bright blue primary action,
// `danger` coral; otherwise misty with a hairline. Icon and/or text.
Item {
    id: root
    property string icon: ""
    property string text: ""
    property bool accent: false
    property bool danger: false
    property int fontSize: 12
    signal clicked()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 36

    readonly property bool filled: (accent || danger) && enabled
    readonly property color base: danger ? Theme.coral : Theme.blue

    Slanted {
        anchors.fill: parent
        fill: !root.enabled ? Theme.withAlpha(Theme.mist, 0.6)
            : root.filled ? (mouse.containsMouse ? Qt.lighter(root.base, 1.08) : root.base)
            : mouse.containsMouse ? Qt.darker(Theme.mist, 1.06) : Theme.mist
        fill2: root.filled ? Qt.lighter(root.base, 1.18) : fill
        stroke: root.filled ? "transparent" : Theme.line
        strokeWidth: 1
    }
    scale: mouse.pressed && enabled ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

    readonly property color fg: root.filled ? Theme.accentInk : danger ? Theme.coral : Theme.ink

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.fg
            opacity: root.enabled ? 1.0 : 0.4
            font.pixelSize: root.fontSize + 2
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.fg
            opacity: root.enabled ? 1.0 : 0.4
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            font.weight: Font.ExtraBold
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
