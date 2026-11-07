import QtQuick
import qs.CustomTheme

// Where a bar popup sits in the shared popout and how it looks, plus its
// content. Declared directly inside the popup (a BarPopup), sized to
// panelWidth x panelHeight. The property names match FrameDrawer, so a popup
// describes itself the same way either way.
//
// The popout (PopoutHost) reads these from the popup it currently shows, and
// glides to the new placement/size when it switches popups. `closed` is
// emitted once the popout has fully slid away with this popup in it.
Item {
    id: root

    property bool open: false   // informational; the popup's `active` drives the popout
    signal closed()

    property string hAlign: "center"   // "center" | "left" | "right" | "free"
    property real hMargin: 0
    property real freeX: 0
    property real panelWidth: 400
    property real panelHeight: 300
    property real radius: 20
    property color borderColor: Theme.withAlpha(Theme.primary, 0.8)
    property real borderWidth: 2
    property int duration: 400

    width: panelWidth
    height: panelHeight

    Component.onCompleted: if (parent && parent.spec !== undefined) parent.spec = root
}
