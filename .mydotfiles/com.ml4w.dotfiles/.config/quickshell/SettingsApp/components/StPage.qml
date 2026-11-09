import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

// Standard page scaffold: a title header + a vertically scrolling body.
// Content declared inside <StPage> is laid out in a full-width column.
Item {
    id: root
    property string heading: ""
    property string subheading: ""
    property string icon: ""

    default property alias body: contentCol.data

    // Scrolls so `item` (anything inside the page) is near the top.
    function scrollTo(item) {
        if (!item) return
        const y = item.mapToItem(column, 0, 0).y - 12
        flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: 6
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 14

            // ── Page header ──
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 12

                Rectangle {
                    visible: root.icon !== ""
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 13
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                    Text { anchors.centerIn: parent; text: root.icon; color: Theme.primary; font.pixelSize: 22 }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: root.heading
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.bold: true
                    }
                    Text {
                        text: root.subheading
                        visible: root.subheading !== ""
                        color: Theme.primary
                        opacity: 0.5
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                id: contentCol
                Layout.fillWidth: true
                spacing: 18
            }

            // Trailing breathing room so the last card isn't flush to the edge
            Item { Layout.preferredHeight: 8 }
        }
    }
}
