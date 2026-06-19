import QtQuick
import qs.CustomTheme

// Circular progress ring with a centered icon and a label that expands on
// hover. Used in the bar cluster for mic, brightness and volume.
Item {
    id: ctrl

    property color ringColor: Theme.primary
    property real value: 0.0
    property string icon: ""
    property string labelText: ""
    signal clicked()
    signal scrolled(real delta)

    height: 28
    width: 28 + (ctrlMouse.containsMouse ? ctrlLabel.implicitWidth + 6 : 0)
    anchors.verticalCenter: parent.verticalCenter
    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    scale: ctrlMouse.pressed ? 0.85 : (ctrlMouse.containsMouse ? 1.05 : 1.0)
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

    Item {
        id: ctrlRing
        width: 28; height: 28
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: "transparent"
            border.color: Theme.withAlpha(Theme.primary, 0.15)
            border.width: 2
        }

        Canvas {
            anchors.fill: parent
            property real arcValue: ctrl.value
            property color arcColor: ctrl.ringColor
            onArcValueChanged: requestPaint()
            onArcColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                if (arcValue > 0) {
                    ctx.beginPath()
                    ctx.arc(width/2, height/2, width/2 - 1, -Math.PI/2, -Math.PI/2 + (Math.min(1.0, arcValue) * 2 * Math.PI))
                    ctx.lineWidth = 2; ctx.strokeStyle = arcColor; ctx.lineCap = "round"; ctx.stroke()
                }
            }
        }

        Text {
            text: ctrl.icon
            color: ctrl.ringColor
            font.pixelSize: 14
            anchors.centerIn: parent
        }
    }

    Text {
        id: ctrlLabel
        text: ctrl.labelText
        color: Theme.secondary
        font.pixelSize: 11; font.bold: true
        anchors.left: ctrlRing.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        verticalAlignment: Text.AlignVCenter
        clip: true
        opacity: ctrlMouse.containsMouse ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: ctrlMouse
        anchors.fill: parent
        anchors.margins: -5
        hoverEnabled: true
        onClicked: ctrl.clicked()
        onWheel: (wheel) => ctrl.scrolled(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
    }
}
