import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// A drawer that rises out of one of the frame's bottom corners (Caelestia
// style), flush with the side frame so it takes that corner over.
//
// Hovering the corner (ScreenFrame reports it through cornerHovered) opens it
// after a short pause, and it closes a moment after the pointer has left both
// the corner and the drawer. A click on the corner or a keybinding opens it
// "sticky" (Corners): it then stays until Esc, a click outside, or the same
// keybinding again. Fill it with one item and give its height as bodyHeight.
//
// Like the hover drawer it has a layer window of its own, so Hyprland blurs it
// as frame material; while hovered its input only covers the drawer, so the
// frame and the windows around it behave as usual.
PanelWindow {
    id: win

    property string key: "quick"          // Corners key
    property string side: "left"          // "left" | "right"
    property bool cornerHovered: false
    property real panelW: 380
    property real bodyHeight: 200
    // The content can hold the drawer open (a menu or a drag in progress).
    property bool busy: false
    default property alias content: body.data

    readonly property int pad: 16
    readonly property string screenName: screen ? screen.name : ""
    readonly property bool open: Corners.isOpen(key, screenName)
    readonly property bool sticky: open && Corners.isSticky(key)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-drawer"
    WlrLayershell.keyboardFocus: sticky ? WlrLayershell.OnDemand : WlrLayershell.None

    property bool animating: false
    visible: open || animating
    onOpenChanged: if (open) animating = true

    // Hovered: just the drawer. Sticky: the whole screen but the frame, so a
    // click outside closes it while a click on the frame goes to the frame
    // (and whatever it opens takes over, see FrameState).
    mask: Region {
        x: win.sticky ? 0 : (win.open ? win.panelX : 0)
        y: win.sticky ? 0 : (win.open ? win.panelY : 0)
        width: win.sticky ? win.width : (win.open ? win.panelW : 0)
        height: win.sticky ? win.height : (win.open ? win.curH : 0)
        Region { intersection: Intersection.Subtract; x: 0; y: 0; width: win.sticky ? win.width : 0; height: 40 }
        Region { intersection: Intersection.Subtract; x: 0; y: 0; width: win.sticky ? 10 : 0; height: win.height }
        Region { intersection: Intersection.Subtract; x: win.width - 10; y: 0; width: win.sticky ? 10 : 0; height: win.height }
        Region { intersection: Intersection.Subtract; x: 0; y: win.height - 10; width: win.sticky ? win.width : 0; height: 10 }
    }

    // ── Hover ───────────────────────────────────────────────────────────────
    readonly property bool wanted: cornerHovered || panelHover.hovered || bodyHover.hovered || busy
    onWantedChanged: {
        if (wanted) { closeDelay.stop(); if (!open && cornerHovered) openDelay.restart() }
        else { openDelay.stop(); if (open && !sticky) closeDelay.restart() }
    }
    Timer {
        id: openDelay; interval: 220
        onTriggered: if (win.cornerHovered && !win.open) Corners.open(win.key, win.screenName, false)
    }
    Timer {
        id: closeDelay; interval: 450
        onTriggered: if (!win.wanted && !win.sticky) Corners.close(win.key)
    }

    Shortcut {
        sequence: "Escape"
        enabled: win.sticky
        onActivated: Corners.close(win.key)
    }
    MouseArea {
        anchors.fill: parent
        enabled: win.sticky
        onClicked: Corners.close(win.key)
    }

    // ── Geometry ────────────────────────────────────────────────────────────
    readonly property real wantH: bodyHeight + 2 * pad
    property real curH: wantH
    Behavior on curH {
        enabled: drawer.progress > 0
        NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1] }
    }
    readonly property real panelX: side === "left" ? drawer.insetSide : width - drawer.insetSide - panelW
    readonly property real panelY: height - drawer.insetBottom - curH

    // Hover over the drawer (and swallow clicks, so the backdrop only gets
    // clicks outside it)
    Item {
        visible: win.open
        x: win.panelX; y: win.panelY
        width: win.panelW; height: win.curH
        HoverHandler { id: panelHover }
        MouseArea { anchors.fill: parent }
    }

    FrameDrawer {
        id: drawer
        open: win.open
        onClosed: win.animating = false
        edge: "bottom"
        hAlign: win.side
        hMargin: insetSide
        panelWidth: win.panelW
        panelHeight: win.curH
        duration: 350
        clipContent: true

        Item {
            id: body
            x: win.pad; y: win.pad
            width: win.panelW - 2 * win.pad
            height: win.bodyHeight
            // Hover reaches the parents of the hovered control
            HoverHandler { id: bodyHover }
        }
    }
}
