import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services

// A field's label in the assistant form
Text {
    Layout.fillWidth: true
    Layout.topMargin: 4
    color: Theme.primary
    opacity: PanelStyle.dim
    font.pixelSize: PanelStyle.labelSize + 1
    font.bold: true
}
