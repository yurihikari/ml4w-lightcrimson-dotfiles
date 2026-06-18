import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// A single settings row: leading icon, title + subtitle, and a trailing
// control area (anything you nest inside <StRow> goes to the right side).
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool clickable: false
    signal clicked()

    // Trailing controls: children of <StRow> are reparented here.
    default property alias controls: trailing.data

    // implicitHeight makes the row work both inside Layouts and as a bare
    // ListView delegate (where Layout.* is ignored).
    implicitHeight: Math.max(56, contentRow.implicitHeight + 16)
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    radius: 12
    color: (clickable && rowMouse.containsMouse)
           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
           : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: root.clickable
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 12

        Rectangle {
            visible: root.icon !== ""
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: 10
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
            Text {
                anchors.centerIn: parent
                text: root.icon
                color: Theme.primary
                font.pixelSize: 17
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: root.title
                visible: root.title !== ""
                color: Theme.primary
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: root.subtitle
                visible: root.subtitle !== ""
                color: Theme.primary
                opacity: 0.5
                font.family: Theme.fontFamily
                font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        RowLayout {
            id: trailing
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
        }
    }
}
