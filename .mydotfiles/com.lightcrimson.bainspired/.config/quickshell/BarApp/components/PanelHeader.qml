import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// BA Inspired: the header every popout section starts with. A slanted blue badge
// with the icon, a bold title with a line of status under it, then the
// section's actions on the right.
RowLayout {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    default property alias actions: trailing.data

    Layout.fillWidth: true
    Layout.preferredHeight: PanelStyle.headerHeight
    spacing: 12

    Item {
        Layout.preferredWidth: PanelStyle.headerHeight + 6
        Layout.preferredHeight: PanelStyle.headerHeight
        Slanted {
            anchors.fill: parent
            slant: 10
            fill: Theme.blue
            fill2: Qt.lighter(Theme.blue, 1.25)
        }
        Text {
            anchors.centerIn: parent
            text: root.icon
            color: Theme.accentInk
            font.pixelSize: 19
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 0
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.ink
            font.family: Theme.fontFamily
            font.pixelSize: PanelStyle.titleSize + 1
            font.weight: Font.Black
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.inkSoft
            font.family: Theme.fontFamily
            font.pixelSize: PanelStyle.subtitleSize
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailing
        Layout.alignment: Qt.AlignVCenter
        spacing: 8
    }
}
