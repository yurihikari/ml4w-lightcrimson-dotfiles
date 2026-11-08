import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// The popout's button: tonal by default, filled when `accent` is set, dimmed
// and inert while `enabled` is false. Icon and/or text.
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property bool accent: false
    property bool danger: false
    property int fontSize: 12
    signal clicked()

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24
    radius: PanelStyle.radiusControl - 2

    readonly property color tone: danger ? "#ff6b6b" : Theme.primary
    color: !enabled ? Theme.withAlpha(tone, 0.06)
         : accent ? (mouse.containsMouse ? Qt.lighter(tone, 1.1) : tone)
         : (mouse.containsMouse ? Theme.withAlpha(tone, 0.16) : Theme.withAlpha(tone, 0.08))
    Behavior on color { ColorAnimation { duration: 150 } }
    scale: mouse.pressed && enabled ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.accent && root.enabled ? Theme.background : root.tone
            opacity: root.enabled ? 1.0 : 0.4
            font.pixelSize: root.fontSize + 2
        }
        Text {
            visible: root.text !== ""
            text: root.text
            color: root.accent && root.enabled ? Theme.background : root.tone
            opacity: root.enabled ? 1.0 : 0.4
            font.pixelSize: root.fontSize
            font.bold: true
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
