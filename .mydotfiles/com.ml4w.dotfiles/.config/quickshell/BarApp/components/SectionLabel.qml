import QtQuick
import qs.CustomTheme
import qs.BarApp.services

// Small uppercase label above a group of controls ("CURRENT", "RECENT", ...).
Text {
    color: Theme.primary
    opacity: 0.45
    font.pixelSize: PanelStyle.labelSize
    font.bold: true
    font.letterSpacing: 0.8
    font.capitalization: Font.AllUppercase
}
