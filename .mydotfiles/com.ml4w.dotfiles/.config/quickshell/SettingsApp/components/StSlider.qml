import QtQuick
import QtQuick.Controls
import qs.CustomTheme

// Themed horizontal slider. Emits `moved(value)` live while dragging.
Slider {
    id: control
    from: 0
    to: 100
    value: 50
    implicitWidth: 160
    implicitHeight: 24

    signal movedTo(real value)
    onMoved: movedTo(value)

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: 6
        radius: 3
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: 3
            color: Theme.primary
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 18
        height: 18
        radius: 9
        color: control.pressed ? Qt.lighter(Theme.primary, 1.15) : Theme.primary
        border.color: Theme.background
        border.width: 2
    }
}
