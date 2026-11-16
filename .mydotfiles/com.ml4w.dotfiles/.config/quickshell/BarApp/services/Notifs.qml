pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification daemon (replaces SwayNC). Owns org.freedesktop.Notifications
// and keeps every notification until it is dismissed, like SwayNC's control
// center. New notifications pop up as toasts (NotificationToasts) unless Do
// Not Disturb is on; the history lives in the notification center
// (NotificationsPopup).
//
// Behaviour carried over from the former ~/.config/swaync/config.json:
//   timeout 4s / timeout-low 2s / timeout-critical 6s (an app's own expire
//   timeout wins), hide-on-clear, hide-on-action. Critical notifications still
//   pop up while Do Not Disturb is on.
//
// IPC (qs ipc call notifications <fn>): toggleDnd, setDnd <bool>, getDnd,
// getCount, clear. The center itself is the bar popup "bar-notifications"
// (toggle / open / close).
Singleton {
    id: root

    // ── Settings ────────────────────────────────────────────────────────────
    readonly property int timeoutLow: 2000
    readonly property int timeoutNormal: 4000
    readonly property int timeoutCritical: 6000
    readonly property int maxToasts: 4

    // ── State ───────────────────────────────────────────────────────────────
    property bool dnd: false
    // Set by the notification center. Opening it clears the toasts (they are
    // all in the center), like SwayNC.
    property bool centerOpen: false
    onCenterOpenChanged: if (centerOpen) for (const n of toasts.slice()) hideToast(n)

    // Newest first.
    readonly property var list: Array.from(server.trackedNotifications.values).reverse()
    readonly property int count: list.length

    // Notifications grouped by app (newest group first), as the center shows
    // them: [{ app, notifs: [...] }]
    readonly property var groups: {
        const out = [], at = {}
        for (const n of list) {
            const key = n.appName || "Notification"
            if (at[key] === undefined) { at[key] = out.length; out.push({ app: key, notifs: [] }) }
            out[at[key]].notifs.push(n)
        }
        return out
    }

    // Arrival time per notification id (ms), for "5m ago".
    property var arrived: ({})

    // Toasts: the windows listen to these and keep their own models, so a new
    // toast doesn't rebuild (and restart the timers of) the others.
    signal toastShown(var notif)
    signal toastHidden(var notif)
    property var toasts: []

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        inlineReplySupported: true

        onNotification: n => {
            n.tracked = true
            const a = Object.assign({}, root.arrived)
            a[n.id] = Date.now()
            root.arrived = a
            n.closed.connect(() => root._forget(n))

            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.showToast(n)
            else if (n.transient)
                n.expire()   // nothing to show and not meant to be kept
        }
    }

    // ── Toasts ──────────────────────────────────────────────────────────────
    function showToast(n) {
        toasts = [n].concat(toasts.filter(t => t !== n))
        toastShown(n)
        // Keep the stack short; older ones stay in the center.
        while (toasts.length > maxToasts) hideToast(toasts[toasts.length - 1])
    }

    function hideToast(n) {
        if (toasts.indexOf(n) < 0) return
        toasts = toasts.filter(t => t !== n)
        toastHidden(n)
        // Transient notifications only live as long as their toast.
        if (n.transient && n.tracked) n.expire()
    }

    function timeoutFor(n) {
        if (n.expireTimeout > 0) return Math.round(n.expireTimeout * 1000)
        if (n.urgency === NotificationUrgency.Critical) return timeoutCritical
        if (n.urgency === NotificationUrgency.Low) return timeoutLow
        return timeoutNormal
    }

    function _forget(n) {
        if (toasts.indexOf(n) >= 0) {
            toasts = toasts.filter(t => t !== n)
            toastHidden(n)
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    function defaultAction(n) {
        if (!n || !n.actions) return null
        for (const a of Array.from(n.actions)) if (a.identifier === "default") return a
        return null
    }

    // Buttons to show: everything but the default action (that's a click).
    function buttonActions(n) {
        if (!n || !n.actions) return []
        return Array.from(n.actions).filter(a => a.identifier !== "default" && a.text !== "")
    }

    function invoke(n, action) {
        if (!n || !action) return
        action.invoke()
        if (n.tracked && !n.resident) n.dismiss()
    }

    // Click on a notification: run its default action (if any) and bring the
    // app forward. Returns whether something was invoked.
    function activate(n) {
        const a = defaultAction(n)
        if (!a) return false
        const win = appWindow(n)
        invoke(n, a)
        // The app asks to be focused, but Hyprland ignores such requests
        // (misc:focus_on_activate is off), so a click looked like it only
        // closed the notification: focus its window ourselves
        if (win) Sys.run(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + win + "\" })"])
        return true
    }

    // The app's window (its Hyprland address), found by desktop entry or app
    // name: "vesktop", "brave-browser" for "Brave"… "" when there's none.
    function appWindow(n) {
        if (!n) return ""
        const names = [n.desktopEntry, n.appName].filter(x => x)
            .map(x => x.toLowerCase().replace(/\.desktop$/, ""))
        if (!names.length) return ""
        const loose = names.map(x => x.replace(/[^a-z0-9]+/g, ""))
        let best = ""
        for (const c of Sys.hyprClients) {
            const cls = (c.class || "").toLowerCase(), init = (c.initialClass || "").toLowerCase()
            if (names.includes(cls) || names.includes(init)) return c.address
            const flat = cls.replace(/[^a-z0-9]+/g, "")
            if (!best && loose.some(x => x.length >= 4 && flat.startsWith(x))) best = c.address
        }
        return best
    }

    // Progress (0-100) when the app sends one (the "value" hint: copies,
    // downloads, volume…), else -1
    function progress(n) {
        const v = n && n.hints ? n.hints["value"] : undefined
        return v === undefined || v === null || isNaN(v) ? -1 : Math.max(0, Math.min(100, Number(v)))
    }

    function dismiss(n) { if (n && n.tracked) n.dismiss() }

    function dismissGroup(app) {
        for (const g of groups) if (g.app === app) for (const n of g.notifs.slice()) dismiss(n)
    }

    function clearAll() {
        for (const n of Array.from(server.trackedNotifications.values)) n.dismiss()
    }

    // ── Do Not Disturb (persisted, so a reload or restart keeps it) ─────────
    function setDnd(on) {
        dnd = on
        dndFile.setText(on ? "1\n" : "0\n")
        // Toasts already on screen go away when it is switched on.
        if (on) for (const n of toasts.slice()) if (n.urgency !== NotificationUrgency.Critical) hideToast(n)
    }
    function toggleDnd() { setDnd(!dnd) }

    FileView {
        id: dndFile
        path: Quickshell.env("HOME") + "/.cache/ml4w/notifications-dnd"
        printErrors: false
        onLoaded: root.dnd = text().trim() === "1"
    }

    // ── Presentation helpers ────────────────────────────────────────────────
    // The app's icon as an image source ("" if none can be found).
    function appIconSource(n) {
        if (!n) return ""
        const i = n.appIcon || ""
        if (i !== "") {
            if (i.startsWith("/")) return "file://" + i
            if (i.startsWith("file://") || i.startsWith("image://")) return i
            const p = Quickshell.iconPath(i, true)
            if (p) return p
        }
        if (n.desktopEntry) {
            const e = DesktopEntries.byId(n.desktopEntry)
            if (e && e.icon) {
                const p = Quickshell.iconPath(e.icon, true)
                if (p) return p
            }
        }
        return ""
    }

    // The notification's own image (avatar, screenshot, album art).
    function imageSource(n) {
        if (!n || !n.image) return ""
        const i = n.image
        return i.startsWith("/") ? "file://" + i : i
    }

    function timeAgo(n, now) {
        const t = arrived[n.id]
        if (!t) return ""
        const s = Math.max(0, Math.floor((now - t) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Qt.formatDateTime(new Date(t), "d MMM")
    }

    // Ticks once a minute so "5m" labels stay current.
    property real now: Date.now()
    Timer { interval: 30000; running: root.count > 0; repeat: true; onTriggered: root.now = Date.now() }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { root.toggleDnd() }
        function setDnd(on: bool): void { root.setDnd(on) }
        function getDnd(): bool { return root.dnd }
        function getCount(): int { return root.count }
        function clear(): void { root.clearAll() }
    }
}
