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
    color: active ? Theme.withAlpha(Theme.primary, mouse.containsMouse ? 0.28 : 0.22)
         : mouse.containsMouse && enabled ? PanelStyle.cardHover : PanelStyle.cardFill
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
            color: root.active ? Theme.primary : Theme.withAlpha(Theme.primary, 0.12)
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.active ? Theme.background : Theme.primary
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
                color: Theme.primary
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
                color: Theme.primary
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
            color: moreMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "󰅂"
                rotation: root.moreOpen ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                color: Theme.primary
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
