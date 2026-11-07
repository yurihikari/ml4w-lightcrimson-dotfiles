import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.CustomTheme

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
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: open && current ? current.keyboardFocusValue : WlrLayershell.None

    mask: Region { x: 0; y: 40; width: host.width; height: Math.max(0, host.height - 40) }

    property var popups: []
    // The popup being shown (kept while the popout slides closed with it).
    property var current: null
    readonly property bool open: current !== null && current.active

    property bool animating: false
    onOpenChanged: if (open) animating = true
    visible: open || animating

    // Popups go here (BarPopup parents itself to it).
    readonly property Item slot: drawer.contentItem

    function register(p) {
        if (popups.indexOf(p) < 0) popups = popups.concat([p])
    }

    function popupActiveChanged(p) {
        if (!p.active) return   // the current one closing closes the popout (see `open`)
        const prev = current
        if (prev === p) return
        // Morph only if the popout is already out; from closed it just opens
        // at the new popup's place.
        if (prev && drawer.progress > 0) {
            switching = true
            switchDone.restart()
        }
        current = p
        if (prev && prev.active) prev.active = false
    }

    // ── Geometry ────────────────────────────────────────────────────────────
    readonly property var spec: current ? current.spec : null
    readonly property real targetW: spec ? spec.panelWidth : 400
    readonly property real targetH: spec ? spec.panelHeight : 300
    readonly property real targetX: {
        if (!spec) return 0
        if (spec.hAlign === "free") return spec.freeX
        if (spec.hAlign === "left") return Math.max(spec.hMargin, drawer.insetSide)
        if (spec.hAlign === "right") return width - Math.max(spec.hMargin, drawer.insetSide) - targetW
        return Math.round((width - targetW) / 2)
    }

    // Glide only while switching popups. Otherwise follow the popup directly,
    // so its own size animations (tabs, hover expansion) aren't eased twice.
    property bool switching: false
    Timer { id: switchDone; interval: 450; onTriggered: host.switching = false }

    property real curX: targetX
    property real curW: targetW
    property real curH: targetH
    Behavior on curX { enabled: host.switching; NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
    Behavior on curW { enabled: host.switching; NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
    Behavior on curH { enabled: host.switching; NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }

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
        borderWidth: host.spec ? host.spec.borderWidth : 2
        duration: host.spec ? host.spec.duration : 400
        outlineSuppressed: host.switching
    }
}
