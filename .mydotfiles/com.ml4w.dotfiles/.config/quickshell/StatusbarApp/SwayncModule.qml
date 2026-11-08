import Quickshell
import QtQuick
import qs.BarApp.services

// Toggles the notification center. Shows a filled bell while there are
// pending notifications.
//
// lightcrimson: notifications are handled by Quickshell (BarApp/services/
// Notifs.qml) instead of SwayNC, so this reads the count from there and opens
// the bar's notification center rather than talking to `swaync-client`.
BarButton {
    id: swaync

    readonly property bool hasNotifications: Notifs.count > 0

    iconSrc: hasNotifications
        ? "../shared/icons/bell-filled.svg"
        : "../shared/icons/bell.svg"

    onClicked: {
        Quickshell.execDetached(["qs", "ipc", "call", "bar-notifications", "toggle"])
    }
}
