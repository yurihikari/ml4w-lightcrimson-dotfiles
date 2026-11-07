import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// A bar popup. It doesn't own a window: all bar popups share one popout surface
// (PopoutHost) that grows out of the frame and morphs from one popup to the
// next. The popup provides the content and a PopoutContent describing where it
// sits and how big it is.
//
// Same interface as before: `active` opens/closes it, `isAnimating` stays true
// until it is fully hidden (use `active || isAnimating` to keep things running
// while visible), `ipcTarget` exposes toggle/open/close, `keyboardFocusValue`
// is the popout's keyboard focus while this popup is shown, and backdrop clicks
// close it unless `closeOnBackdrop` is false (then handle onBackdropClicked).
// Only one popup is open at a time: opening another switches the popout to it.
Item {
    id: root

    // The PopoutHost this popup lives in (set where the popup is declared).
    property var host: null

    property bool active: false
    property bool isAnimating: false
    property string ipcTarget: ""
    property var keyboardFocusValue: WlrLayershell.Exclusive
    property bool closeOnBackdrop: true

    // Set by the PopoutContent inside the popup.
    property var spec: null

    signal backdropClicked()
    signal opened()

    function open()  { active = true }
    function close() { active = false }
    function endAnimation() { if (!active) isAnimating = false }

    parent: host ? host.slot : null
    anchors.fill: parent

    // The popup the popout shows stays fully visible (it slides with the
    // popout when it closes); one it switched away from fades out.
    readonly property bool shown: host !== null && host.current === root
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
            onRunningChanged: if (!running && !root.shown && !root.active) root.isAnimating = false
        }
    }
    visible: (active || isAnimating) && opacity > 0
    // A popup fading out underneath the new one doesn't take input.
    enabled: active

    onActiveChanged: {
        if (active) {
            isAnimating = true
            opened()
        }
        if (host) host.popupActiveChanged(root)
    }

    IpcHandler {
        target: root.ipcTarget
        function toggle(): void { root.active = !root.active }
        function open(): void { root.active = true }
        function close(): void { root.active = false }
    }

    Component.onCompleted: if (host) host.register(root)
}
