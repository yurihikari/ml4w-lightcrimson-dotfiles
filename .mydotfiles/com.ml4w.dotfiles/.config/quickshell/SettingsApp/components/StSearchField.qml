import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

// Rounded search box. Exposes `text` and forwards key navigation signals.
Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: "Search settings…"
    signal accepted()
    signal escaped()
    signal downPressed()

    function clear() { input.text = "" }
    function focusInput() { input.forceActiveFocus() }

    Layout.fillWidth: true
    implicitHeight: 40
    radius: 12
    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
    border.color: input.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
    border.width: input.activeFocus ? 2 : 1
    Behavior on border.color { ColorAnimation { duration: 150 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 8

        Text { text: "󰍉"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }

        TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: root.placeholder
            color: Theme.primary
            placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
            font.family: Theme.fontFamily
            font.pixelSize: 14
            background: null
            verticalAlignment: TextInput.AlignVCenter
            onAccepted: root.accepted()
            Keys.onEscapePressed: root.escaped()
            Keys.onDownPressed: root.downPressed()
        }

        Text {
            visible: input.text.length > 0
            text: "󰅖"
            color: Theme.primary
            opacity: clearMouse.containsMouse ? 0.9 : 0.45
            font.pixelSize: 14
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clear()
            }
        }
    }
}
