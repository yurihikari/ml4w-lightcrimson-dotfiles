import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.components
import qs.BarApp.services

// A one-line text field in the assistant form, in the theme's field style
PanelField {
    property alias text: tf.text
    property alias placeholder: tf.placeholderText
    property alias field: tf

    Layout.fillWidth: true
    focused: tf.activeFocus

    TextField {
        id: tf
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        color: Theme.primary
        placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
        font.family: Theme.fontFamily
        font.pixelSize: PanelStyle.bodySize + 1
        background: null
        verticalAlignment: TextInput.AlignVCenter
    }
}
