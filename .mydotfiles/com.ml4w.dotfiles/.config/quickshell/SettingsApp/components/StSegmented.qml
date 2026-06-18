import QtQuick
import qs.CustomTheme

// Segmented choice control. `model` is an array of { value, label, icon? }.
// Bind `current` (a value) and handle `selected(value)`.
Rectangle {
    id: root
    property var model: []
    property var current: undefined
    signal selected(var value)

    implicitHeight: 38
    implicitWidth: 240
    radius: 12
    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)

    Row {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        Repeater {
            model: root.model
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: (root.width - 8 - (root.model.length - 1) * 4) / root.model.length
                height: parent.height
                radius: 9
                property bool isSel: root.current === modelData.value
                color: isSel ? Theme.primary
                     : (segMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent")
                Behavior on color { ColorAnimation { duration: 130 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        visible: modelData.icon !== undefined && modelData.icon !== ""
                        text: modelData.icon || ""
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.parent.isSel ? Theme.background : Theme.primary
                        font.pixelSize: 13
                    }
                    Text {
                        text: modelData.label
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.parent.isSel ? Theme.background : Theme.primary
                        opacity: parent.parent.isSel ? 1.0 : 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: parent.parent.isSel
                    }
                }

                MouseArea {
                    id: segMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(modelData.value)
                }
            }
        }
    }
}
