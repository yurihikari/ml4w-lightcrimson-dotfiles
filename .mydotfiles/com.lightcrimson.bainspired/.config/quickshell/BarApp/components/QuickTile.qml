import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// A quick settings tile: icon, label and a line of state. Tonal when off,
// tinted with a filled icon when on. `more` adds a chevron that emits more()
// (e.g. to pick which VPN).
Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string status: ""
    property bool active: false
    property bool busy: false
    property bool more: false
    property bool moreOpen: false
    signal clicked()
    signal moreClicked()

    implicitHeight: 58
    implicitWidth: 170
    radius: PanelStyle.radiusCard
    color: active ? (mouse.containsMouse ? Qt.lighter(Theme.blue, 1.08) : Theme.blue)
         : mouse.containsMouse && enabled ? PanelStyle.cardHover : PanelStyle.cardFill
    border.color: active ? "transparent" : Theme.line
    border.width: 1
    // BA Inspired: text and icons turn white on an active (blue) tile
    readonly property color fg: active ? Theme.accentInk : Theme.ink
    Behavior on color { ColorAnimation { duration: 160 } }
    scale: mouse.pressed && enabled ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 9; anchors.rightMargin: root.more ? 4 : 12
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 40; Layout.preferredHeight: 40
            radius: PanelStyle.radiusControl
            color: Theme.paper
            border.color: root.active ? "transparent" : Theme.line
            border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.active ? Theme.blue : Theme.ink
                opacity: root.enabled ? 1 : 0.4
                font.pixelSize: 18
                SequentialAnimation on opacity {
                    running: root.busy
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.3; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: root.label
                color: root.fg
                font.family: Theme.fontFamily
                opacity: root.enabled ? 1 : 0.5
                font.pixelSize: 13; font.bold: true
                // Long labels shrink a little before they elide
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.status
                color: root.fg
                opacity: PanelStyle.dim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        // Chevron (its own hit area)
        Rectangle {
            visible: root.more
            Layout.preferredWidth: 26; Layout.preferredHeight: 40
            radius: 9
            color: moreMouse.containsMouse ? Theme.withAlpha(root.fg, 0.18) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "󰅂"
                rotation: root.moreOpen ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                color: root.fg
                font.pixelSize: 15
            }
            MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moreClicked()
            }
        }
    }
}
