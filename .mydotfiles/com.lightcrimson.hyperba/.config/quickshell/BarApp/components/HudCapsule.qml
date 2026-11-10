import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// HyperBA's HUD counter (BA Inspired's, scaled up): a slanted white capsule with a coloured icon tab on
// the left, a bold value, and an optional small blue "+" box at the right end
// (game-style resource counter). The whole capsule is one click target for
// whoever owns it; `plus` only draws the box.
Item {
    id: root
    property string icon: ""
    property string value: ""
    property string sub: ""             // small text after the value (e.g. "/100")
    property color tone: Theme.blue     // icon tab colour
    property bool plus: true
    property bool hot: false            // hovered / its popup open
    property real fill: -1              // 0..1 draws a thin meter under the value
    property real maxValueWidth: 140    // longer values elide
    property real flat: 0               // 1: flattened into the bar band (no fill, no shadow)

    // The slanted edges eat into the ends: keep content clear of them
    // (left edge ~slant/2 in at mid-height, right edge ~slant at the bottom).
    readonly property real slant: 12
    implicitHeight: 38
    implicitWidth: row.implicitWidth + slant * 0.6 + 4 + slant + 8

    Slanted {
        anchors.fill: parent
        slant: root.slant
        shadow: PanelStyle.floatingPlates && root.flat < 0.5
        fill: Theme.mix(Theme.plate, Theme.plateFlat, root.flat)
        stroke: root.hot ? Theme.blue : Theme.line
        strokeWidth: 1
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.leftMargin: root.slant * 0.6 + 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Icon, bare and in its own colour (no box)
        Text {
            Layout.preferredWidth: 30
            Layout.leftMargin: 2
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.tone
            font.pixelSize: 24
            style: Text.Raised; styleColor: Theme.withAlpha(Theme.shadow, 0.5)
        }

        Column {
            visible: root.value !== ""
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            Row {
                id: valueRow
                spacing: 1
                Text {
                    id: valueText
                    text: root.value
                    width: Math.min(implicitWidth, root.maxValueWidth)
                    elide: Text.ElideRight
                    color: Theme.ink
                    font.family: Theme.fontFamily
                    font.pixelSize: 17; font.weight: Font.Black
                }
                Text {
                    visible: root.sub !== ""
                    anchors.baseline: valueText.baseline
                    text: root.sub
                    color: Theme.inkSoft
                    font.family: Theme.fontFamily
                    font.pixelSize: 12; font.weight: Font.Bold
                }
            }
            // Meter
            Rectangle {
                visible: root.fill >= 0
                width: Math.max(36, valueRow.width); height: 3; radius: 1.5
                color: Theme.mist
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.fill)); height: parent.height; radius: 1.5
                    color: root.tone
                }
            }
        }

        // "+" box
        Item {
            visible: root.plus
            Layout.preferredWidth: 24; Layout.preferredHeight: 24
            Rectangle {
                anchors.fill: parent; radius: 4
                color: root.hot ? Theme.blueDeep : Theme.blue
                Text { anchors.centerIn: parent; text: "+"; color: Theme.accentInk; font.family: Theme.fontFamily; font.pixelSize: 19; font.weight: Font.Black }
            }
        }
    }
}
