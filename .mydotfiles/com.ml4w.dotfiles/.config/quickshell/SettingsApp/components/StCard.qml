import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// A rounded "section" container with an optional title, matching the
// surface-container look used across the shell. Put rows/controls inside it.
ColumnLayout {
    id: root

    property string title: ""
    property string icon: ""

    // Children declared inside <StCard> land in `body` (see default alias).
    default property alias body: inner.data

    Layout.fillWidth: true
    spacing: 8

    // Optional section title above the card
    RowLayout {
        visible: root.title !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 8
        Text {
            visible: root.icon !== ""
            text: root.icon
            color: Theme.primary
            font.pixelSize: 13
            opacity: 0.7
        }
        Text {
            text: root.title.toUpperCase()
            color: Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            opacity: 0.45
        }
    }

    Rectangle {
        Layout.fillWidth: true
        radius: 18
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
        border.width: 1
        implicitHeight: inner.implicitHeight + 12

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2
        }
    }
}
