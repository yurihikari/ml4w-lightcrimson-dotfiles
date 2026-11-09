import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// Small drawer that slides out of the frame under a bar item while it is
// hovered (Caelestia style), with quick controls for that item:
//   "vol" / "mic" / "bri"  icon (click: mute), slider, value
//   "power"                lock, suspend, log out, reboot, shut down
//   "media"                previous, play/pause, next, seek bar
// Moving to another item glides the same drawer over to it; it closes a
// moment after the pointer has left both the item and the drawer. Clicking
// the items themselves still opens their full popups.
//
// The bar reports hovers with hoverItem(kind, item, hovered, centreX).
//
// It has a window of its own, like the toasts and popups: Hyprland only
// blurs (xray) the drawer as frame material when it is its own layer surface.
// Drawn inside the frame's window, the windows behind showed through it, so it
// read as a pale cut-out rather than part of the frame. The window sits on the
// frame's layer and takes input only on the drawer body below the bar, never
// on the bar itself: the pointer stays on the bar when it maps (a window that
// covered the bar took pointer focus from it, and the bar stopped seeing
// hovers).
PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    // Slides out of the frame on its own: Hyprland's layer animation is off
    // for this namespace (hypr/conf/custom/style.lua), or it slid in twice.
    WlrLayershell.namespace: "quickshell-drawer"
    WlrLayershell.keyboardFocus: WlrLayershell.None

    // Mapped while open and until it has slid back into the frame.
    property bool animating: false
    visible: open || animating

    mask: Region { x: win.maskX; y: win.maskY; width: win.maskW; height: win.maskH }

    // Don't open while a full popup is out (they would overlap).
    property bool suppressed: false

    // ── Which item ─────────────────────────────────────────────────────────
    property string kind: "vol"
    property string hoveredKind: ""       // item under the pointer, "" = none
    property real anchorX: 0              // its centre, window coordinates

    readonly property var player: Sys.activePlayer
    function available(k) { return k !== "media" || player !== null }

    // centreX: the item's visual centre in its own coordinates (default: middle)
    function hoverItem(k, item, hovered, centreX) {
        if (hovered) {
            hoveredKind = k
            const p = item.mapToItem(null, centreX !== undefined ? centreX : item.width / 2, 0)
            anchorX = p.x
            if (open && available(k)) kind = k
        } else if (hoveredKind === k) {
            hoveredKind = ""
        }
    }

    readonly property bool panelHovered: panelHover.hovered || contentHover.hovered
    readonly property bool busy: slider.dragging || seek.dragging
    readonly property bool wanted: !suppressed
        && ((hoveredKind !== "" && available(hoveredKind)) || panelHovered || busy)

    property bool open: false
    onOpenChanged: {
        if (open) animating = true
        else armed = ""
    }

    // Input area while open (zero while closed)
    readonly property real maskX: open ? panelX : 0
    readonly property real maskY: open ? drawer.insetTop : 0
    readonly property real maskW: open ? curW : 0
    readonly property real maskH: open ? panelH : 0

    onWantedChanged: {
        if (wanted) { closeDelay.stop(); if (!open) openDelay.restart() }
        else { openDelay.stop(); closeDelay.restart() }
    }
    onSuppressedChanged: if (suppressed) { openDelay.stop(); open = false }
    Timer {
        id: openDelay; interval: 140
        onTriggered: { if (win.hoveredKind !== "" && win.available(win.hoveredKind)) win.kind = win.hoveredKind; win.open = true }
    }
    Timer { id: closeDelay; interval: 380; onTriggered: win.open = false }

    readonly property bool isLevel: kind === "vol" || kind === "mic" || kind === "bri"

    // ── Levels ──────────────────────────────────────────────────────────────
    readonly property bool muted: kind === "vol" ? Sys.isMuted : kind === "mic" ? Sys.isMicMuted : false
    readonly property real sysValue: kind === "vol" ? Sys.volValue : kind === "mic" ? Sys.micValue : Sys.briValue
    // While dragging, show what is being set (the 3s poll can't snap it back)
    property real dragValue: 0
    readonly property real value: slider.dragging ? dragValue : sysValue
    readonly property color tone: muted ? Theme.error : Theme.primary

    readonly property string levelIcon: kind === "mic" ? (Sys.isMicMuted ? "󰍭" : "󰍬")
        : kind === "bri" ? (Sys.briValue > 0.6 ? "󰃠" : (Sys.briValue > 0.3 ? "󰃟" : "󰃞"))
        : (Sys.isMuted ? "󰝟" : (Sys.volValue > 0.6 ? "󰕾" : (Sys.volValue > 0.2 ? "󰖀" : "󰕿")))

    // Applies a level, at most every 40ms while dragging.
    property real pending: -1
    property string pendingKind: ""
    function setLevel(v) {
        dragValue = v
        if (kind === "vol") Sys.volValue = v
        else if (kind === "mic") Sys.micValue = v
        else Sys.briValue = v
        pending = v; pendingKind = kind
        if (!applyTimer.running) applyTimer.start()
    }
    Timer {
        id: applyTimer
        interval: 40
        onTriggered: {
            const v = win.pending, k = win.pendingKind
            if (v < 0) return
            win.pending = -1
            if (k === "vol") Sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
            else if (k === "mic") Sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", v.toFixed(2)])
            else Sys.run(["brightnessctl", "s", Math.max(1, Math.round(v * 100)) + "%"])
        }
    }

    function toggleMute() {
        if (kind === "vol") {
            Sys.isMuted = !Sys.isMuted
            Sys.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        } else if (kind === "mic") {
            Sys.isMicMuted = !Sys.isMicMuted
            Sys.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
        }
    }

    // ── Power (same commands as PowerPopup) ────────────────────────────────
    readonly property var powerActions: [
        { id: "lock",     icon: "󰌾", action: ["hyprlock"],                             danger: false },
        { id: "suspend",  icon: "󰤄", action: ["systemctl", "suspend"],                 danger: false },
        { id: "logout",   icon: "󰍃", action: ["hyprctl", "dispatch", "hl.dsp.exit()"], danger: false },
        { id: "reboot",   icon: "󰑓", action: ["systemctl", "reboot"],                  danger: true },
        { id: "shutdown", icon: "󰐥", action: ["systemctl", "poweroff"],                danger: true }
    ]
    // Reboot / shut down need a second click: the first arms the button.
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: win.armed = "" }
    function power(a) {
        if (a.danger && armed !== a.id) { armed = a.id; disarm.restart(); return }
        armed = ""
        open = false
        Sys.run(a.action)
    }

    // ── Media ───────────────────────────────────────────────────────────────
    readonly property real mediaProgress: player && player.lengthSupported && player.length > 0
        ? Math.min(1, player.position / player.length) : 0
    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // ── Drawer ──────────────────────────────────────────────────────────────
    readonly property int panelW: kind === "power" ? 236 : kind === "media" ? 300 : 240
    readonly property int panelH: 46
    property real curW: panelW
    Behavior on curW {
        enabled: win.open && drawer.progress > 0
        NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1] }
    }

    // Glide to the hovered item while open; jump there while closed.
    // (Clamped after snapping, so at either end it sits flush with the frame.)
    property real panelX: Math.max(drawer.insetSide, Math.min(width - drawer.insetSide - curW, drawer.snap(anchorX - curW / 2)))
    Behavior on panelX {
        enabled: win.open && drawer.progress > 0
        NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1] }
    }

    // Hover over the drawer. (Moving down from an item into it, the close
    // delay covers the step from the bar's surface onto this one.)
    Item {
        id: hitArea
        visible: win.open
        x: win.panelX; y: drawer.insetTop
        width: win.curW; height: win.panelH
        HoverHandler { id: panelHover }
    }

    // One small round icon button (power, media)
    component IconBtn: Rectangle {
        id: btn
        property string icon: ""
        property bool danger: false
        property bool highlight: false
        property bool enabled: true
        signal clicked()
        implicitWidth: 34; implicitHeight: 34
        radius: 17
        readonly property color tone: danger ? Theme.error : Theme.primary
        color: highlight ? Theme.withAlpha(tone, btnMouse.containsMouse ? 0.32 : 0.24)
             : btnMouse.containsMouse && enabled ? Theme.withAlpha(tone, 0.14) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        scale: btnMouse.pressed && enabled ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            color: btn.tone
            opacity: btn.enabled ? 1.0 : 0.35
            font.pixelSize: 17
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.clicked()
        }
    }

    FrameDrawer {
        id: drawer
        open: win.open
        onClosed: win.animating = false
        hAlign: "free"
        freeX: win.panelX
        panelWidth: win.curW
        panelHeight: win.panelH
        radius: 18
        duration: 300

        Item {
            width: win.curW; height: win.panelH

            // Hover reaches parents of the hovered control
            HoverHandler { id: contentHover }

            // ── Level: icon, slider, value ──
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 10
                visible: win.isLevel

                Text {
                    text: win.levelIcon
                    color: win.tone
                    font.pixelSize: 18
                    opacity: iconMouse.containsMouse && win.kind !== "bri" ? 0.75 : 1
                    MouseArea {
                        id: iconMouse
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: win.kind !== "bri" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: win.toggleMute()
                    }
                }
                BarSlider {
                    id: slider
                    Layout.fillWidth: true
                    value: win.value
                    color: win.tone
                    onMoved: (v) => win.setLevel(v)
                }
                Text {
                    text: win.muted ? "Muted" : Math.round(win.value * 100) + "%"
                    color: win.tone
                    font.pixelSize: 12; font.bold: true
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 42
                }
            }

            // ── Power ──
            RowLayout {
                anchors.centerIn: parent
                spacing: 8
                visible: win.kind === "power"
                Repeater {
                    model: win.powerActions
                    IconBtn {
                        required property var modelData
                        icon: win.armed === modelData.id ? "󰀦" : modelData.icon
                        danger: modelData.danger
                        highlight: win.armed === modelData.id
                        onClicked: win.power(modelData)
                    }
                }
            }

            // ── Media ──
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 14
                spacing: 4
                visible: win.kind === "media"

                IconBtn {
                    icon: "󰒮"
                    enabled: win.player !== null && win.player.canGoPrevious
                    onClicked: win.player.previous()
                }
                IconBtn {
                    icon: win.player && win.player.playbackState === MprisPlaybackState.Playing ? "󰏤" : "󰐊"
                    highlight: true
                    enabled: win.player !== null && win.player.canTogglePlaying
                    onClicked: win.player.togglePlaying()
                }
                IconBtn {
                    icon: "󰒭"
                    enabled: win.player !== null && win.player.canGoNext
                    onClicked: win.player.next()
                }
                BarSlider {
                    id: seek
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    value: win.mediaProgress
                    enabled: win.player !== null && win.player.canSeek && win.player.lengthSupported
                    onMoved: (v) => { if (win.player && win.player.canSeek) win.player.position = v * win.player.length }
                }
                Text {
                    text: win.player && win.player.lengthSupported ? win.fmt(win.player.position) : ""
                    color: Theme.primary; opacity: 0.7
                    font.pixelSize: 11; font.bold: true
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 34
                }
            }
        }
    }
}
