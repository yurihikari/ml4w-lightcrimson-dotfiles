import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// Notification toasts (replaces SwayNC's popups), integrated into the frame
// like Caelestia: one drawer that slides out of the top-right corner under
// the bar, with the toasts stacked inside it (newest on top) as the same
// tonal cards as the notification center. It grows and shrinks as toasts come
// and go, and slides back into the frame when the last one leaves.
//
// Each toast closes after its timeout (Notifs.timeoutFor); hovering pauses
// it. Toasts wait (timers paused) while a bar popup is open, since popups use
// the same corner, and are cleared when the notification center opens. While
// Do Not Disturb is on only critical ones appear (Notifs decides). They show
// on the focused monitor.
PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // Focus only when clicked (an inline reply field), never grabbed.
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand

    // A bar popup is out: wait until it closes.
    property bool suppressed: false

    readonly property bool onFocusedScreen: !Hyprland.focusedMonitor || !screen
        || Hyprland.focusedMonitor.name === screen.name
    readonly property bool shown: toastModel.count > 0 && !Notifs.centerOpen && !suppressed && onFocusedScreen

    property bool animating: false
    visible: shown || animating
    onShownChanged: if (shown) animating = true

    // Input only on the drawer (the window covers the screen so the drawer's
    // outline can run round the frame).
    mask: Region {
        x: win.shown ? win.width - win.inset - win.panelW : 0
        y: win.shown ? drawer.insetTop : 0
        width: win.shown ? win.panelW : 0
        height: win.shown ? win.curH : 0
    }

    ListModel { id: toastModel }
    property var byId: ({})

    Connections {
        target: Notifs
        function onToastShown(n) {
            win.byId[n.id] = n
            for (let i = 0; i < toastModel.count; i++) {
                if (toastModel.get(i).nid === n.id) { toastModel.move(i, 0, 1); return }
            }
            toastModel.insert(0, { nid: n.id })
        }
        function onToastHidden(n) {
            for (let i = 0; i < toastModel.count; i++) {
                if (toastModel.get(i).nid === n.id) { toastModel.remove(i); break }
            }
        }
    }

    readonly property var curveEnter: [0.05, 0.7, 0.1, 1.0, 1, 1]

    // ── Drawer geometry ─────────────────────────────────────────────────────
    readonly property int inset: 10          // flush with the right frame (attached)
    readonly property int panelW: 400
    readonly property int pad: 12
    // Content height; kept at its last size while the drawer slides away empty.
    readonly property real wantH: list.contentHeight + 2 * pad
    property real curH: 120
    onWantHChanged: if (toastModel.count > 0) curH = wantH
    Behavior on curH {
        enabled: drawer.progress > 0
        NumberAnimation { duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: win.curveEnter }
    }

    FrameDrawer {
        id: drawer
        open: win.shown
        onClosed: win.animating = false
        hAlign: "right"
        hMargin: win.inset
        panelWidth: win.panelW
        panelHeight: win.curH
        borderColor: PanelStyle.outline
        // Cards slide in and out within the drawer, never past its edges
        clipContent: true

        ListView {
            id: list
            x: win.pad; y: win.pad
            width: win.panelW - 2 * win.pad
            height: contentHeight
            interactive: false
            spacing: 8
            model: toastModel

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: 60; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: win.curveEnter }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { property: "x"; to: 80; duration: 240; easing.type: Easing.InCubic }
                }
            }
            // Also finishes an interrupted fade-in: a card pushed down by the
            // next one before its own add transition ended stayed half faded.
            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: win.curveEnter }
                NumberAnimation { property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: toastItem
                required property int nid
                readonly property var notif: win.byId[nid] ?? null
                width: list.width
                height: card.implicitHeight

                NotificationCard {
                    id: card
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    notif: toastItem.notif
                    toast: true
                    onActionInvoked: if (toastItem.notif) Notifs.hideToast(toastItem.notif)
                }

                Timer {
                    interval: toastItem.notif ? Notifs.timeoutFor(toastItem.notif) : 4000
                    running: toastItem.notif !== null && !card.hovered && win.shown
                    onTriggered: Notifs.hideToast(toastItem.notif)
                }
            }
        }
    }
}
