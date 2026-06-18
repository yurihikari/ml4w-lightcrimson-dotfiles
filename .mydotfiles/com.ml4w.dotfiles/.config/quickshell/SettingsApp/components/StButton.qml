import QtQuick
import qs.CustomTheme

// Pill button. `accent: true` => filled primary; otherwise outlined.
Rectangle {
    id: root
    property string text: ""
    property string icon: ""
    property bool accent: false
    property bool dangerous: false
    property bool enabled: true
    signal clicked()

    readonly property color tone: dangerous ? "#e06c75" : Theme.primary

    implicitHeight: 38
    implicitWidth: label.implicitWidth + (icon !== "" ? 30 : 0) + 36
    radius: 11

    color: !enabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
         : accent ? (mouse.containsMouse ? Qt.lighter(tone, 1.12) : tone)
                  : (mouse.containsMouse ? Qt.rgba(tone.r, tone.g, tone.b, 0.14) : "transparent")
    border.color: accent ? "transparent" : Qt.rgba(tone.r, tone.g, tone.b, 0.4)
    border.width: accent ? 0 : 1
    opacity: enabled ? 1.0 : 0.5
    scale: (enabled && mouse.pressed) ? 0.97 : 1.0
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

    Row {
        anchors.centerIn: parent
        spacing: 8
        Text {
            visible: root.icon !== ""
            text: root.icon
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent ? Theme.background : root.tone
            font.pixelSize: 14
        }
        Text {
            id: label
            text: root.text
            anchors.verticalCenter: parent.verticalCenter
            color: root.accent ? Theme.background : root.tone
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
