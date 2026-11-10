pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Which corner drawer is open, and on which screen.
//
// The bottom corners of the frame each hold a drawer (CornerDrawer):
//   "quick"    bottom left: quick settings
//   "capture"  bottom right: screenshots, recording, OCR, colour picker
// Hovering a corner opens its drawer until the pointer leaves ("hover"); a
// click on the corner or a keybinding opens it until dismissed ("sticky":
// Esc, a click outside, or the same keybinding again).
Singleton {
    id: root

    // key → screen name it is open on ("" = closed)
    property var screens: ({ quick: "", capture: "" })
    // key → opened sticky
    property var sticky: ({ quick: false, capture: false })

    function focusedScreen() { return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "" }

    function screenOf(key) { return screens[key] || "" }
    function isOpen(key, screen) { return screen !== "" && screenOf(key) === screen }
    function isSticky(key) { return sticky[key] === true }

    function open(key, screen, isSticky) {
        const s = Object.assign({}, screens); s[key] = screen; screens = s
        const k = Object.assign({}, sticky); k[key] = isSticky; sticky = k
        // One drawer at a time: whatever else is open slides away
        if (screen !== "") FrameState.claim(key)
    }
    Connections {
        target: FrameState
        function onClaimed(k) {
            if (k !== "quick") root.close("quick")
            if (k !== "capture") root.close("capture")
        }
    }
    function close(key) {
        if (screenOf(key) === "") return
        open(key, "", false)
    }
    // Sticky toggle (keybinding / corner click), on the given or focused screen.
    function toggle(key, screen) {
        const s = screen || focusedScreen()
        if (screenOf(key) === s && isSticky(key)) close(key)
        else open(key, s, true)
    }
    function closeAll() { close("quick"); close("capture") }

    IpcHandler {
        target: "capture"
        function toggle(): void { root.toggle("capture") }
        function open(): void { root.open("capture", root.focusedScreen(), true) }
        function close(): void { root.close("capture") }
        // mode: region | window | screen | all
        function screenshot(mode: string): void { Capture.screenshot(mode || "region") }
        function ocr(): void { Capture.ocr() }
        function pickColor(): void { Capture.pickColor() }
        // mode: region | screen; stops a running recording instead
        function record(mode: string): void {
            if (Capture.recording) Capture.stopRecording()
            else Capture.record(mode || "screen")
        }
        function stop(): void { Capture.stopRecording() }
        function saveReplay(): void { Capture.saveReplay() }
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void { root.toggle("quick") }
        function open(): void { root.open("quick", root.focusedScreen(), true) }
        function close(): void { root.close("quick") }
        function present(): void { QuickSettings.togglePresentation() }
        function keepAwake(): void { QuickSettings.keepAwake = !QuickSettings.keepAwake }
    }
}
