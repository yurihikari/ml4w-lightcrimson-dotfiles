import QtQuick
import qs.CustomTheme
import qs.BarApp.services

// The container every text field in the popout sits in (search boxes, the
// variant input, city lookups): a tonal fill that brightens with a soft ring
// while focused. Put the row with the icon and TextField inside, and bind
// `focused` to the field's activeFocus.
Rectangle {
    property bool focused: false

    implicitHeight: PanelStyle.controlHeight
    radius: PanelStyle.radiusControl
    color: focused ? PanelStyle.fieldFocus : PanelStyle.fieldFill
    border.width: 1
    border.color: focused ? PanelStyle.fieldRing : "transparent"
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
}
