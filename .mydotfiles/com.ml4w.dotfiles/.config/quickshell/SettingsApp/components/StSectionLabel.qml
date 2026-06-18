import QtQuick
import QtQuick.Layouts
import qs.CustomTheme

// Small uppercase caption used to separate groups within a page.
Text {
    Layout.fillWidth: true
    Layout.topMargin: 6
    Layout.leftMargin: 4
    color: Theme.primary
    opacity: 0.45
    font.family: Theme.fontFamily
    font.pixelSize: 11
    font.bold: true
    text: text.toUpperCase()
}
