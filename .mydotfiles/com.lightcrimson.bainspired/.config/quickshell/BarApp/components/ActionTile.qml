import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// A square-ish action button with an icon above a short label (capture modes).
// `accent` fills it (the primary action), `danger` tints it in the error colour.
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property bool accent: false
    property bool danger: false
    signal clicked()

    implicitHeight: 62
    implicitWidth: 80
    radius: PanelStyle.radiusCard
    readonly property color tone: danger ? Theme.error : accent ? Theme.blue : Theme.primary
    border.color: accent && enabled ? "transparent" : Theme.line
    border.width: 1
    color: !enabled ? Theme.withAlpha(tone, 0.04)
         : accent ? (mouse.containsMouse ? Qt.lighter(tone, 1.1) : tone)
         : danger ? Theme.withAlpha(tone, mouse.containsMouse ? 0.24 : 0.16)
         : mouse.containsMouse ? PanelStyle.cardHover : PanelStyle.cardFill
    Behavior on color { ColorAnimation { duration: 150 } }
    scale: mouse.pressed && enabled ? 0.95 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

    readonly property color fg: accent && enabled ? Theme.accentInk : tone

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 3
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            color: root.fg
            opacity: root.enabled ? 1 : 0.35
            font.pixelSize: 20
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: root.fg
            opacity: root.enabled ? (root.accent ? 1 : 0.85) : 0.35
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
