import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.CustomTheme
import qs.BarApp.services

// The shared popout: one surface, hanging from the bar, that every bar popup
// (BarPopup) shows its content in. Opening a popup slides it out of the frame;
// opening another while it is out morphs it — it glides to the new popup's
// place and size (detaching from / merging into the side frames on the way)
// while the content crossfades — instead of one popup closing and another
// opening.
//
// The window covers the screen below the bar: a click outside the popout
// closes it, while the bar itself stays clickable, so clicking another bar
// item switches straight to that popup.
PanelWindow {
    id: host

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    // Slides out of the frame on its own: Hyprland's layer animation is off
    // for this namespace (hypr/conf/custom/style.lua), or it slid in twice.
    WlrLayershell.namespace: "quickshell-drawer"
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: open && current ? current.keyboardFocusValue : WlrLayershell.None

    // Everything but the frame: the bar and the side and bottom strips stay
    // clickable, and whatever they open takes over (FrameState).
    mask: FrameHoleMask { window: host }
    readonly property string claimKey: "popout:" + (host.screen ? host.screen.name : "")
    Connections {
        target: FrameState
        function onClaimed(k) {
            if (k !== host.claimKey && host.current && host.current.active) host.current.active = false
        }
    }

    property var popups: []
    // The popup being shown (kept while the popout slides closed with it).
    property var current: null
    readonly property bool open: current !== null && current.active

    property bool animating: false
    visible: open || animating

    // Popups go here (BarPopup parents itself to it).
    readonly property Item slot: drawer.contentItem

    function register(p) {
        if (popups.indexOf(p) < 0) popups = popups.concat([p])
    }

    function popupActiveChanged(p) {
        if (!p.active) return   // the current one closing closes the popout (see `open`)
        const prev = current
        if (prev === p && drawer.progress > 0) return
        if (prev && prev !== p && drawer.progress > 0) {
            // Already out: glide from the previous popup to this one (also
            // from wherever a closing one got to).
            growStart.stop()
            collapsed = false
            switching = true
            switchDone.restart()
        } else {
            // From closed: start collapsed onto the popup's bar item, then
            // grow out of it (see `collapsed`).
            growFrom(p)
        }
        current = p
        if (prev && prev !== p && prev.active) prev.active = false
    }

    // ── Growing out of / back into the bar item ─────────────────────────────
    // While `collapsed`, the panel's horizontal extent is the anchor item's
    // (plus a little padding), so the drawer slides out of the frame exactly
    // as wide as the icon and widens to its real size as it opens, and narrows
    // back into the icon as it closes.
    property bool collapsed: false
    property bool morphing: false
    property real anchorX: 0
    property real anchorW: 0
    readonly property real anchorPad: 8
    readonly property bool hasAnchor: anchorW > 0

    function measureAnchor(p) {
        const a = p ? p.anchorItem : null
        if (!a || !a.visible) { anchorW = 0; return }
        // The bar lives in another full-screen window on the same screen, so
        // its window coordinates are ours.
        const pt = a.mapToItem(null, 0, 0)
        anchorX = pt.x - anchorPad
        anchorW = a.width + 2 * anchorPad
    }

    function growFrom(p) {
        measureAnchor(p)
        morphing = false        // jump (no animation) onto the anchor...
        collapsed = true
        growStart.restart()     // ...then grow out of it
    }

    // Starts the widening together with the drawer's own slide (FrameDrawer
    // waits a couple of frames before it starts moving).
    Timer {
        id: growStart
        interval: 32
        onTriggered: {
            host.morphing = true
            host.collapsed = false
            growDone.restart()
        }
    }
    Timer { id: growDone; interval: 480; onTriggered: if (host.open) host.morphing = false }

    onOpenChanged: {
        if (open) {
            FrameState.claim(claimKey)
            animating = true
            // Reopened while it was still closing: widen out again from
            // wherever it got to (a fresh open runs through growFrom instead).
            if (collapsed && !growStart.running) {
                morphing = true
                collapsed = false
                growDone.restart()
            }
            return
        }
        // Closing: narrow back into the bar item while sliding in.
        measureAnchor(current)
        growStart.stop()
        growDone.stop()
        morphing = true
        collapsed = true
    }

    // ── Geometry ────────────────────────────────────────────────────────────
    readonly property var spec: current ? current.spec : null
    readonly property real restW: spec ? spec.panelWidth : 400
    readonly property real targetW: collapsed && hasAnchor ? anchorW : restW
    readonly property real targetH: spec ? spec.panelHeight : 300
    readonly property real targetX: collapsed && hasAnchor ? anchorX : restX
    readonly property real restX: {
        if (!spec) return 0
        if (spec.hAlign === "free") return spec.freeX
        if (spec.hAlign === "left") return Math.max(drawer.snap(spec.hMargin), drawer.insetSide)
        if (spec.hAlign === "right") return width - Math.max(drawer.snap(spec.hMargin), drawer.insetSide) - restW
        return drawer.snap((width - restW) / 2)
    }

    // Glide only while switching popups. Otherwise follow the popup directly,
    // so its own size animations (tabs, hover expansion) aren't eased twice.
    property bool switching: false
    Timer { id: switchDone; interval: 480; onTriggered: host.switching = false }

    property real curX: targetX
    property real curW: targetW
    property real curH: targetH
    // Same emphasized curve as the drawers: quick to leave, long soft settle.
    readonly property var morphCurve: [0.05, 0.7, 0.1, 1.0, 1, 1]
    // Closing uses the drawer's exit curve and length, so the panel reaches
    // the icon's width just as it disappears into the frame.
    readonly property var exitCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
    readonly property bool closing: morphing && !open
    Behavior on curX { enabled: host.switching || host.morphing; NumberAnimation { duration: host.closing ? 300 : 460; easing.type: Easing.BezierSpline; easing.bezierCurve: host.closing ? host.exitCurve : host.morphCurve } }
    Behavior on curW { enabled: host.switching || host.morphing; NumberAnimation { duration: host.closing ? 300 : 460; easing.type: Easing.BezierSpline; easing.bezierCurve: host.closing ? host.exitCurve : host.morphCurve } }
    Behavior on curH { enabled: host.switching; NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: host.morphCurve } }

    // Click outside the popout
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!host.current) return
            if (host.current.closeOnBackdrop) host.current.active = false
            host.current.backdropClicked()
        }
    }

    FrameDrawer {
        id: drawer
        open: host.open
        onClosed: {
            host.animating = false
            host.morphing = false
            const c = host.current
            if (c) {
                if (c.spec) c.spec.closed()
                c.isAnimating = false
            }
        }
        hAlign: "free"
        freeX: host.curX
        panelWidth: host.curW
        panelHeight: host.curH
        radius: host.spec ? host.spec.radius : 20
        borderColor: host.spec ? host.spec.borderColor : Theme.withAlpha(Theme.primary, 0.8)
        borderWidth: host.spec ? host.spec.borderWidth : PanelStyle.outlineWidth
        duration: host.spec ? host.spec.duration : 400
        outlineSuppressed: host.switching
        clipContent: host.switching || host.morphing
    }
}
