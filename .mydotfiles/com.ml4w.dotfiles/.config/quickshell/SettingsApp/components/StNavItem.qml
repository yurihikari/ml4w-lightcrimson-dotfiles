import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// Sidebar entry: icon + label, highlighted when selected.
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property bool selected: false
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 42
    radius: 11
    color: selected ? Theme.primary
         : (mouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent")
    Behavior on color { ColorAnimation { duration: 130 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Text {
            text: root.icon
            color: root.selected ? Theme.background : Theme.primary
            font.pixelSize: 17
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            text: root.label
            color: root.selected ? Theme.background : Theme.primary
            opacity: root.selected ? 1.0 : 0.85
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: root.selected ? Font.Bold : Font.Normal
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
