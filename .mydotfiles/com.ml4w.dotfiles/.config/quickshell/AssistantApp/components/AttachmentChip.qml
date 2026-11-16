import QtQuick
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services

// A file attached to a message: a thumbnail for an image, else its name.
// Click to open it; `removable` adds a ✕ (before sending).
Rectangle {
    id: root
    property string path: ""
    property bool removable: false
    signal removed()

    readonly property bool image: /\.(png|jpe?g|gif|webp|bmp)$/i.test(path)
    readonly property string name: path.split("/").pop()
    readonly property string url: "file://" + path.split("/").map(encodeURIComponent).join("/")

    implicitWidth: image ? 64 : Math.min(240, row.implicitWidth + 20 + (removable ? 18 : 0))
    implicitHeight: image ? 64 : 30
    radius: PanelStyle.radiusControl
    color: Theme.withAlpha(Theme.primary, 0.1)
    border.color: Theme.withAlpha(Theme.primary, 0.18)
    border.width: 1
    clip: true

    Image {
        visible: root.image
        anchors.fill: parent
        anchors.margins: 1
        source: root.image ? root.url : ""
        sourceSize.width: 128; sourceSize.height: 128
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    Row {
        id: row
        visible: !root.image
        anchors.verticalCenter: parent.verticalCenter
        x: 10
        spacing: 6
        Text {
            text: /\.pdf$/i.test(root.path) ? "󰈦" : "󰈔"
            color: Theme.primary; opacity: 0.7; font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            width: Math.min(implicitWidth, 190)
            text: root.name
            elide: Text.ElideMiddle
            color: Theme.primary
            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.labelSize + 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: open
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Qt.openUrlExternally(root.url)
        ToolTip.visible: containsMouse; ToolTip.delay: 500; ToolTip.text: root.path
    }

    // Remove (before sending)
    Rectangle {
        visible: root.removable
        anchors.right: parent.right; anchors.top: root.image ? parent.top : undefined
        anchors.verticalCenter: root.image ? undefined : parent.verticalCenter
        anchors.margins: 3
        width: 18; height: 18; radius: 9
        color: removeMouse.containsMouse ? Theme.primary : Theme.withAlpha(Theme.background, 0.85)
        Text {
            anchors.centerIn: parent
            text: "󰅖"; font.pixelSize: 10
            color: removeMouse.containsMouse ? Theme.background : Theme.primary
        }
        MouseArea {
            id: removeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removed()
        }
    }
}
