import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

// Themed single-line text input. Exposes `text`, `placeholder`, `password`
// (masked, with a show/hide eye) and `accepted()` on Return.
Rectangle {
    id: root
    property alias text: inp.text
    property string placeholder: ""
    property bool password: false
    property bool revealed: false
    property alias field: inp
    signal accepted()

    implicitHeight: 34
    Layout.fillWidth: true
    Layout.preferredWidth: 220
    radius: 9
    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
    border.color: inp.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
    border.width: 1

    TextField {
        id: inp
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: root.password ? 30 : 10
        placeholderText: root.placeholder
        placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
        color: Theme.primary
        font.pixelSize: 13
        echoMode: root.password && !root.revealed ? TextInput.Password : TextInput.Normal
        verticalAlignment: TextInput.AlignVCenter
        background: null
        onAccepted: root.accepted()
    }

    Text {
        visible: root.password
        anchors.right: parent.right; anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: root.revealed ? "󰈉" : "󰈈"
        color: Theme.primary; opacity: eyeMouse.containsMouse ? 0.9 : 0.5
        font.pixelSize: 15
        MouseArea { id: eyeMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.revealed = !root.revealed }
    }
}
