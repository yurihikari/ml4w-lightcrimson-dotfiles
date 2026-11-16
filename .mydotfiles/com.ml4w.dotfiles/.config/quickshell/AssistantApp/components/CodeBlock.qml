import QtQuick
import Quickshell
import qs.CustomTheme
import qs.BarApp.services

// A fenced code block from a reply: its language, a Copy button, and the code
// in a monospace font that wraps instead of running off the edge.
Rectangle {
    id: root
    property string code: ""
    property string lang: ""

    implicitHeight: col.implicitHeight
    radius: PanelStyle.radiusControl
    color: Theme.withAlpha(Theme.primary, 0.08)
    border.color: Theme.withAlpha(Theme.primary, 0.14)
    border.width: 1

    property bool copied: false
    Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = false }

    Column {
        id: col
        width: parent.width

        Item {
            width: parent.width
            height: 28
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.lang || "code"
                color: Theme.primary; opacity: PanelStyle.faint
                font.family: "monospace"; font.pixelSize: PanelStyle.labelSize + 1
            }
            Rectangle {
                id: copyBtn
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: copyRow.implicitWidth + 14; height: 22
                radius: 6
                color: copyMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"
                Row {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: root.copied ? "󰄬" : "󰆏"
                        color: Theme.primary; opacity: 0.8
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.copied ? "Copied" : "Copy"
                        color: Theme.primary; opacity: 0.8
                        font.family: Theme.fontFamily; font.pixelSize: PanelStyle.labelSize + 1
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", "--", root.code])
                        root.copied = true
                        copiedTimer.restart()
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: Theme.withAlpha(Theme.primary, 0.1)
            }
        }

        TextEdit {
            x: 10
            width: parent.width - 20
            topPadding: 8; bottomPadding: 10
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            text: root.code
            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            color: Theme.primary
            selectionColor: Theme.withAlpha(Theme.primary, 0.3)
            selectedTextColor: Theme.primary
            font.family: "monospace"; font.pixelSize: PanelStyle.bodySize
        }
    }
}
