import QtQuick
import qs.CustomTheme

// Highlight behind a bar item whose popup is open: a soft tonal pill that
// grows in under the icon, marking where the popout came from. Declare it
// inside the item (it sits behind the item's own content).
Rectangle {
    property bool active: false
    property real padX: 6
    property real padY: 3

    anchors.centerIn: parent
    width: parent.width + 2 * padX
    height: parent.height + 2 * padY
    radius: height / 2
    z: -1
    color: Theme.withAlpha(Theme.primary, 0.18)

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
}
