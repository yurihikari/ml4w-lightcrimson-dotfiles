import QtQuick
import qs.CustomTheme

// Small square icon button (refresh, etc.) with hover/press feedback.
Rectangle {
    id: root
    property string icon: ""
    property bool busy: false
    property bool enabled: true
    signal clicked()

    implicitWidth: 30
    implicitHeight: 30
    radius: 9
    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, mouse.containsMouse ? 0.18 : 0.1)
    Behavior on color { ColorAnimation { duration: 130 } }
    scale: mouse.pressed ? 0.9 : (mouse.containsMouse ? 1.08 : 1.0)
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: Theme.primary
        font.pixelSize: 15
        opacity: root.busy ? 0.3 : 0.85
        RotationAnimation on rotation {
            running: root.busy
            from: 0; to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
