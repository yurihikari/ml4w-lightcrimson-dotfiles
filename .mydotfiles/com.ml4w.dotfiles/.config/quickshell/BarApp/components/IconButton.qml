import QtQuick
import qs.CustomTheme

// Small square icon button with hover/press feedback (refresh, open-folder…).
// `busy` dims the icon; the caller disables interaction while busy if needed.
Rectangle {
    id: root
    property string icon: ""
    property real size: 28
    property real iconSize: 14
    property bool busy: false
    property real pressScale: 0.9
    property real hoverScale: 1.1
    property alias hovered: mouse.containsMouse
    property alias enabled: mouse.enabled
    signal clicked()

    width: size; height: size; radius: 8
    color: Theme.withAlpha(Theme.primary, 0.1)
    scale: mouse.pressed ? pressScale : (mouse.containsMouse ? hoverScale : 1.0)
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: Theme.primary
        font.pixelSize: root.iconSize
        opacity: root.busy ? 0.3 : 0.8
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
