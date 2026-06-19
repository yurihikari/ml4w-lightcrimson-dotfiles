import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Shared scaffold for the bar's full-screen overlay popups.
//
// Handles the boilerplate every popup repeated: the Wayland overlay window, the
// `active`/`isAnimating`/`visible` lifecycle, the IPC handler, and a click-to-
// close backdrop. The popup's own animated container goes inside as content and
// is drawn above the backdrop.
//
// Wayland-safe exit: keep `isAnimating` true while the outro animation plays,
// then call endAnimation() from the container's opacity Behavior so the window
// stays mapped until the fade-out finishes.
PanelWindow {
    id: root

    property bool active: false
    property bool isAnimating: false

    // IPC target name, e.g. "bar-media". Exposes toggle/open/close.
    property string ipcTarget: ""

    // Keyboard focus mode while open. Most popups grab Exclusive focus (which is
    // what actually gives the window keyboard input for FocusScope-based Esc);
    // some (media, keyboard, dock) want OnDemand or release focus when inactive.
    property var keyboardFocusValue: WlrLayershell.Exclusive

    // When true the backdrop click closes the popup. Set false to handle the
    // click yourself via onBackdropClicked (e.g. to dismiss a sub-overlay first).
    property bool closeOnBackdrop: true

    signal backdropClicked()
    signal opened()

    // Content (the animated container) is reparented above the backdrop.
    default property alias content: holder.data

    function open()  { active = true }
    function close() { active = false }
    // Call from the container's exit-opacity Behavior when it finishes.
    function endAnimation() { if (!active) isAnimating = false }

    visible: active || isAnimating
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: root.keyboardFocusValue

    onActiveChanged: if (active) {
        isAnimating = true
        opened()
    }

    IpcHandler {
        target: root.ipcTarget
        function toggle(): void { root.active = !root.active }
        function open(): void { root.active = true }
        function close(): void { root.active = false }
    }

    // Click-outside-to-close backdrop (below the content).
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.closeOnBackdrop) root.active = false
            root.backdropClicked()
        }
    }

    Item { id: holder; anchors.fill: parent }
}
