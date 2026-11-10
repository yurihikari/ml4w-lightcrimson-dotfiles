import QtQuick
import qs.CustomTheme

// BA Inspired: small square icon button, misty with a hairline, blue on hover.
Rectangle {
    id: root
    property string icon: ""
    property real size: 28
    property real iconSize: 14
    property bool busy: false
    property real pressScale: 0.9
    property real hoverScale: 1.05
    property alias hovered: mouse.containsMouse
    property alias enabled: mouse.enabled
    signal clicked()

    width: size; height: size; radius: 6
    color: mouse.containsMouse ? Theme.blue : Theme.mist
    border.color: mouse.containsMouse ? Theme.blue : Theme.line
    border.width: 1
    Behavior on color { ColorAnimation { duration: 140 } }
    scale: mouse.pressed ? pressScale : (mouse.containsMouse ? hoverScale : 1.0)
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: mouse.containsMouse ? Theme.accentInk : Theme.ink
        font.pixelSize: root.iconSize
        opacity: root.busy ? 0.3 : 0.9
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
