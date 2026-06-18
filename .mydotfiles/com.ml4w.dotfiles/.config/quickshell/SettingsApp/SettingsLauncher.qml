import QtQuick
import Quickshell
import Quickshell.Io

// Persistent, non-visual controller for the Settings window.
//
// The IpcHandler lives here (not inside the window) so it survives no matter
// what happens to the window. The window itself is created on open and fully
// destroyed on close via LazyLoader — so closing it with the window manager
// (e.g. Super+Q) leaves clean state, and the next toggle builds a fresh window.
Scope {
    id: launcher

    property string requestedPage: "wifi"

    LazyLoader {
        id: loader
        active: false

        SettingsWindow {
            initialPage: launcher.requestedPage
            onDismissed: loader.active = false   // Escape inside the window
            onClosed: loader.active = false       // closed by the compositor / WM
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void { loader.active = !loader.active }
        function open(): void { loader.active = true }
        function close(): void { loader.active = false }
        function show(page: string): void {
            launcher.requestedPage = page
            if (loader.active && loader.item) loader.item.goTo(page)
            else loader.active = true
        }
    }
}
