import QtQuick
import qs.CustomTheme

// Horizontal slider for the bar's level drawer: drag, click or scroll.
// `value` (0..1) is shown as given; `moved(v)` reports what the user picks.
Item {
    id: root
    property real value: 0
    property color color: Theme.primary
    readonly property bool dragging: area.pressed
    signal moved(real v)

    implicitHeight: 20
    implicitWidth: 140

    readonly property real shown: Math.max(0, Math.min(1, value))

    function pick(x) { root.moved(Math.max(0, Math.min(1, x / width))) }

    // Track
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3
        color: Theme.withAlpha(root.color, 0.2)

        // Fill
        Rectangle {
            width: Math.max(height, parent.width * root.shown)
            height: parent.height; radius: 3
            color: root.color
            Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }

    // Knob
    Rectangle {
        width: area.pressed || area.containsMouse ? 16 : 12
        height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.width * root.shown - width / 2))
        color: root.color
        border.color: Theme.background
        border.width: 2
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6; anchors.bottomMargin: -6
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => root.pick(mouse.x)
        onPositionChanged: (mouse) => { if (pressed) root.pick(mouse.x) }
        onWheel: (wheel) => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
