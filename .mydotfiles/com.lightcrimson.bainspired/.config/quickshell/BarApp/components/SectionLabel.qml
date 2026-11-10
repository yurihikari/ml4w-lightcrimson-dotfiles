import QtQuick
import qs.CustomTheme
import qs.BarApp.services

// BA Inspired: a section title with a small slanted blue marker in front.
Row {
    id: root
    property string text: ""
    property alias font: label.font
    spacing: 7

    Slanted {
        anchors.verticalCenter: parent.verticalCenter
        width: 9; height: 12
        slant: 4
        fill: Theme.blue
        fill2: Theme.sky
    }
    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.ink
        opacity: 0.8
        font.family: Theme.fontFamily
        font.pixelSize: PanelStyle.labelSize + 1
        font.weight: Font.ExtraBold
        font.letterSpacing: 0.6
        font.capitalization: Font.AllUppercase
    }
}
