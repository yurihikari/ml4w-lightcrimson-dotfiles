import QtQuick
import qs.CustomTheme
import qs.BarApp.services

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
    // "top": hangs from the bar. "free": a floating panel whose top is freeY
    // (window coords); only frameless themes (BA Inspired, HyperBA) draw it
    // there. With "free", the popout grows out of the anchor item's whole
    // rectangle instead of just its width, and the content is pinned to the
    // panel's bottom so it is revealed upward.
    property string edge: "top"
    property real freeY: 0
    property real panelWidth: 400
    property real panelHeight: 300
    property real radius: 20
    property color borderColor: PanelStyle.outline
    property real borderWidth: PanelStyle.outlineWidth
    property int duration: 400

    width: panelWidth
    height: panelHeight
    // Pin the content to the panel's anchored side, so while the popout morphs
    // to another popup (and is momentarily narrower or wider than this one)
    // the content stays where it will land instead of riding the moving edge.
    x: !parent ? 0
        : hAlign === "right" ? parent.width - width
        : hAlign === "center" ? Math.round((parent.width - width) / 2)
        : 0
    y: parent && edge === "free" ? parent.height - height : 0

    Component.onCompleted: if (parent && parent.spec !== undefined) parent.spec = root
}
