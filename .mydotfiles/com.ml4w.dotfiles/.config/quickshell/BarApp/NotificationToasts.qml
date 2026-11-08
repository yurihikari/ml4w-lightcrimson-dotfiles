import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// Notification toasts (replaces SwayNC's popups): a stack in the top-right
// corner under the bar, newest on top, on the focused monitor. Each toast
// closes after its timeout (Notifs.timeoutFor); hovering pauses it. Toasts
// are hidden while the notification center is open, and while Do Not Disturb
// is on only critical ones appear (Notifs decides).
PanelWindow {
    id: win

    anchors { top: true; right: true }
    // Bar (40) + gap, side frame (10) + gap
    margins { top: 50; right: 20 }
    implicitWidth: 380
    implicitHeight: Math.max(1, list.contentHeight)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // Focus only when clicked (an inline reply field), never grabbed.
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand

    readonly property bool onFocusedScreen: !Hyprland.focusedMonitor || !screen
        || Hyprland.focusedMonitor.name === screen.name
    visible: toastModel.count > 0 && !Notifs.centerOpen && onFocusedScreen

    // Only the toasts themselves take input.
    mask: Region { item: list }

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

    ListView {
        id: list
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: contentHeight
        interactive: false
        spacing: 10
        model: toastModel

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: 70; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: win.curveEnter }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: 90; duration: 240; easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: win.curveEnter }
        }

        delegate: Item {
            id: toastItem
            required property int nid
            readonly property var notif: win.byId[nid] ?? null
            width: list.width
            height: surface.height

            // Same material as the frame drawers: frame fill, outline.
            Rectangle {
                id: surface
                width: parent.width
                height: card.implicitHeight
                radius: 20
                color: Theme.withAlpha(Theme.background, 0.8)
                border.width: 2
                border.color: card.critical ? Theme.withAlpha(Theme.error, 0.8) : PanelStyle.outline

                NotificationCard {
                    id: card
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    notif: toastItem.notif
                    toast: true
                    onActionInvoked: if (toastItem.notif) Notifs.hideToast(toastItem.notif)
                }
            }

            Timer {
                interval: toastItem.notif ? Notifs.timeoutFor(toastItem.notif) : 4000
                running: toastItem.notif !== null && !card.hovered && win.visible
                onTriggered: Notifs.hideToast(toastItem.notif)
            }
        }
    }
}
