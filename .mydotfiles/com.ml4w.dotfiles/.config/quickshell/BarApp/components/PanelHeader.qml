import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// The header every popout section starts with: icon tile, title and a line of
// status, then section-specific actions (declared as children) on the right.
//
//   PanelHeader {
//       icon: "󰅌"; title: "Clipboard"; subtitle: count + " entries"
//       PanelButton { ... }        // trailing actions
//       SectionNav { host: root.host; current: root.ipcTarget }
//   }
RowLayout {
    id: root
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    default property alias actions: trailing.data

    Layout.fillWidth: true
    Layout.preferredHeight: PanelStyle.headerHeight
    spacing: 12

    Rectangle {
        Layout.preferredWidth: PanelStyle.headerHeight
        Layout.preferredHeight: PanelStyle.headerHeight
        radius: PanelStyle.radiusControl
        color: Theme.withAlpha(Theme.primary, 0.12)
        Text {
            anchors.centerIn: parent
            text: root.icon
            color: Theme.primary
            font.pixelSize: 19
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.primary
            font.pixelSize: PanelStyle.titleSize
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.primary
            opacity: PanelStyle.dim
            font.pixelSize: PanelStyle.subtitleSize
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: trailing
        Layout.alignment: Qt.AlignVCenter
        spacing: 8
    }
}
