import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.CustomTheme
import qs.BarApp.services

// A popup surface that grows out of the screen frame (Caelestia-style drawer).
//
// Instead of a floating card, the panel is attached to the frame: it shares the
// frame's fill, meets it with concave curves (the same radius as the frame's
// inner corners), and slides out of it when opened.
//
// Fill it like a plain Item, sized to `panelWidth` x `panelHeight`:
//
//   FrameDrawer {
//       open: popup.active
//       onClosed: popup.isAnimating = false
//       hAlign: "right"; hMargin: 155
//       panelWidth: card.width; panelHeight: card.height
//       Rectangle { id: card; width: 400; height: 300; color: "transparent" }
//   }
//
// Edges: "top" hangs from the bar, "bottom" rises from the bottom frame (both
// placed with hAlign/hMargin/freeX). "left"/"right" slide out of a side frame
// and always span the full height between the bar and the bottom frame; there
// panelWidth is the depth and the content is as tall as that span
// (`contentItem.height`).
//
// How a top/bottom panel meets a side frame depends on the gap between them,
// and changes continuously, so a panel can glide along the frame (the shared
// popout morphing between popups) without anything popping:
//   attached  (no gap)        flush with the side frame, takes over its corner
//   near      (gap < corner)  merges into the frame's corner curve, still
//                             taking the corner over
//   free      (further)       its own concave curve, growing from nothing
//                             to `fillet` as the gap widens
// While it takes a corner over, FrameCorners tells the frame to leave that
// corner to the drawer, so the two never stack. The fill never paints over the
// frame itself: it is clipped to the area inside the frame.
//
// The frame has no border, so a border that simply stopped at the frame looked
// cut off. While the drawer is out, its border is one continuous outline: the
// panel's edge, through the curves, into the frame's inner edge and around the
// whole screen. It fades in once the drawer has landed and fades out as it
// closes, so the frame only has a border while a popup is open. That outline
// needs the window to cover the whole screen (give small windows an input mask
// instead of shrinking them).
//
// Every drawer registers with FrameState, so the frame can cast one shadow
// around itself and all open drawers (materialPath(), in screen coordinates;
// the drawer's window must cover the screen from its top-left corner).
Item {
    id: root
    anchors.fill: parent

    property bool open: false
    // Emitted once the close animation has finished (unmap the window then).
    signal closed()

    // "top" | "bottom" | "left" | "right"
    property string edge: "top"
    // Top/bottom only: "center" | "left" | "right" | "free" (freeX, window coords)
    property string hAlign: "center"
    property real hMargin: 0
    property real freeX: 0
    // The panel's top for edge "free" (window coords). The frame only grows
    // panels out of its edges, so it ignores it; frameless themes (BA
    // Inspired) place a floating window there. PopoutHost always sets it.
    property real freeY: 0
    property real panelWidth: 400
    property real panelHeight: 300

    // Snaps a length to whole device pixels. At a fractional scale the frame's
    // 10px sides land on half a pixel (12.5px at 1.25x): the frame and the
    // drawer each half-covered that column, and the window below showed
    // through as a thin line where they meet. ScreenFrame snaps the same way.
    readonly property real dpr: QsWindow.window && QsWindow.window.devicePixelRatio > 0 ? QsWindow.window.devicePixelRatio : 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    // Frame thickness, in this window's coordinates.
    property real insetTop: snap(40)
    property real insetBottom: snap(10)
    property real insetSide: snap(10)

    property real radius: 20        // the panel's free corners (= the frame's own corners)
    property real fillet: 20        // concave curves where it meets the frame
    property real frameCorner: snap(20) // radius of the frame's own inner corners
    property color fillColor: Theme.withAlpha(Theme.background, 0.8)
    property color borderColor: PanelStyle.outline
    property real borderWidth: PanelStyle.outlineWidth
    property int duration: 400
    // Hide the outline for now (the shared popout does while it morphs).
    property bool outlineSuppressed: false
    // Clip the content to the panel even once it has landed (the shared
    // popout does while it morphs, so content of a different size than the
    // panel at that moment never spills past its edges).
    property bool clipContent: false
    // Join the frame's shared shadow.
    property bool castsShadow: true

    // The screen this drawer is on (its window's). The frame's shadow and the
    // taken-over corners are per screen, so a drawer only ever affects the
    // frame of its own monitor.
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property bool fromTop: edge !== "bottom"

    // Don't start sliding the moment the window maps: until the compositor has
    // given it its real size, the frame edges sit in the wrong place (a bottom
    // drawer showed up near the top for a frame, then jumped). Wait for a sane
    // size plus a couple of frames, so the first frame shown is the drawer
    // just leaving the frame.
    readonly property bool _sized: width > 2 * insetSide && height > insetTop + insetBottom
    property bool _go: false
    function _sync() {
        if (open && _sized) {
            startDelay.restart()
        } else {
            startDelay.stop()
            _go = false
        }
    }
    onOpenChanged: {
        _sync()
        // Closed again before it ever moved: nothing to slide back, so report
        // it done now. Only on an actual close: size changes while opening
        // also re-run _sync, and finishing early there unmapped the window
        // the moment it later closed (so it faded instead of sliding back).
        if (!open && progress <= 0) closed()
    }
    on_SizedChanged: _sync()
    Component.onCompleted: { _sync(); FrameState.add(root) }
    Timer {
        id: startDelay
        interval: 32
        onTriggered: root._go = root.open && root._sized
    }

    // Motion curves (Material 3 "emphasized"): opening shoots out and then
    // settles softly, closing eases off and then picks up speed into the frame.
    // (An exponential ease stopped abruptly; the same curve for closing did
    // nearly all of its travel in the first frame or two and read as a vanish.)
    readonly property var curveEnter: [0.05, 0.7, 0.1, 1.0, 1, 1]
    readonly property var curveExit: [0.3, 0.0, 0.8, 0.15, 1, 1]

    property real progress: _go ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: root.open ? root.duration : Math.round(root.duration * 0.75)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? root.curveEnter : root.curveExit
            onRunningChanged: if (!running && !root.open) root.closed()
        }
    }

    // The outline doesn't travel with the drawer: it fades in once the drawer
    // has (nearly) landed, and fades out quickly as soon as it starts closing.
    property real outlineOpacity: _go && !outlineSuppressed && progress > 0.97 ? 1 : 0
    Behavior on outlineOpacity {
        NumberAnimation { duration: root.outlineOpacity < 0.5 ? 220 : 120; easing.type: Easing.OutCubic }
    }

    default property alias content: panelContent.data
    readonly property alias contentItem: panelContent

    // Run along the frame / depth away from it
    readonly property real alongLength: horizontal ? panelWidth : area.height
    readonly property real depth: horizontal ? panelHeight : panelWidth
    readonly property real revealed: Math.max(0, depth * progress)

    readonly property real panelX: hAlign === "free" ? freeX
        : hAlign === "left" ? Math.max(snap(hMargin), insetSide)
        : hAlign === "right" ? width - Math.max(snap(hMargin), insetSide) - panelWidth
        : snap((width - panelWidth) / 2)
    // Panel start along the frame, in area coordinates
    readonly property real alongOffset: horizontal ? panelX - area.x : 0

    // Gap between each end of the panel and the side frame (top/bottom edges);
    // side drawers always run from the bar to the bottom frame.
    readonly property real gapStart: horizontal ? Math.max(0, panelX - insetSide) : 0
    readonly property real gapEnd: horizontal ? Math.max(0, (width - insetSide) - (panelX + panelWidth)) : 0
    function _mode(g) { return g <= 0.5 ? "attach" : (g < frameCorner ? "near" : "free") }
    readonly property string startMode: _mode(gapStart)
    readonly property string endMode: _mode(gapEnd)

    // ── Frame corners taken over ────────────────────────────────────────────
    readonly property bool _out: progress > 0
    readonly property bool _ownsStart: startMode !== "free"
    readonly property bool _ownsEnd: endMode !== "free"
    readonly property bool coversTopLeft: _out && ((edge === "top" && _ownsStart) || edge === "left")
    readonly property bool coversTopRight: _out && ((edge === "top" && _ownsEnd) || edge === "right")
    readonly property bool coversBottomLeft: _out && ((edge === "bottom" && _ownsStart) || edge === "left")
    readonly property bool coversBottomRight: _out && ((edge === "bottom" && _ownsEnd) || edge === "right")
    onCoversTopLeftChanged: FrameCorners.add(screenName, "topLeft", coversTopLeft ? 1 : -1)
    onCoversTopRightChanged: FrameCorners.add(screenName, "topRight", coversTopRight ? 1 : -1)
    onCoversBottomLeftChanged: FrameCorners.add(screenName, "bottomLeft", coversBottomLeft ? 1 : -1)
    onCoversBottomRightChanged: FrameCorners.add(screenName, "bottomRight", coversBottomRight ? 1 : -1)
    Component.onDestruction: {
        if (coversTopLeft) FrameCorners.add(screenName, "topLeft", -1)
        if (coversTopRight) FrameCorners.add(screenName, "topRight", -1)
        if (coversBottomLeft) FrameCorners.add(screenName, "bottomLeft", -1)
        if (coversBottomRight) FrameCorners.add(screenName, "bottomRight", -1)
        FrameState.remove(root)
    }

    // ── Path building ───────────────────────────────────────────────────────
    // Paths are written as if the panel hung from a frame line at v = 0, with
    // u running along the frame from the panel's start (u = 0). They are then
    // mapped onto the actual edge; mirrored edges flip the arc direction.
    // (ax, ay) shifts the result, e.g. to screen coordinates.
    function _builder(ax, ay) {
        const AW = area.width, AH = area.height
        const o = root.alongOffset
        const e = root.edge
        const flip = e === "bottom" || e === "left"
        const parts = []
        const f = v => (Math.round(v * 100) / 100).toString()
        const P = (u, v) => {
            if (e === "top") return f(ax + o + u) + " " + f(ay + v)
            if (e === "bottom") return f(ax + o + u) + " " + f(ay + AH - v)
            if (e === "left") return f(ax + v) + " " + f(ay + o + u)
            return f(ax + AW - v) + " " + f(ay + o + u)
        }
        return {
            M: (u, v) => parts.push("M " + P(u, v)),
            L: (u, v) => parts.push("L " + P(u, v)),
            // sweep 1 = clockwise on screen (in the unmirrored orientation)
            A: (r, sweep, u, v) => parts.push("A " + f(Math.max(0, r)) + " " + f(Math.max(0, r)) + " 0 0 "
                + (flip ? 1 - sweep : sweep) + " " + P(u, v)),
            Z: () => parts.push("Z"),
            str: () => parts.join(" ")
        }
    }

    // Span of the area along the frame / away from it
    function _spanAlong() { return root.horizontal ? area.width : area.height }
    function _spanAcross() { return root.horizontal ? area.height : area.width }

    function _fill(b) {
        const w = root.alongLength, h = root.revealed
        const C = root.frameCorner
        const sm = root.startMode, em = root.endMode
        const g0 = root.gapStart, g1 = root.gapEnd
        // While the panel is too short to cover a corner it has taken over,
        // draw the frame's corner shape too (it hides its own meanwhile).
        if (h < C) {
            if (sm === "attach") { b.M(0, 0); b.L(C, 0); b.A(C, 0, 0, C); b.Z() }
            if (em === "attach") { b.M(w, 0); b.L(w, C); b.A(C, 0, w - C, 0); b.Z() }
        }
        if (h < 0.5) return
        const R = Math.min(root.radius, h / 2, w / 2)
        const Fb = Math.min(root.fillet, h)                      // into a side frame
        const F0 = Math.min(root.fillet, h, Math.max(0, g0 - C)) // free curves
        const F1 = Math.min(root.fillet, h, Math.max(0, g1 - C))
        // Where the frame's corner curve meets the panel's side ("near")
        const v0 = C - Math.sqrt(Math.max(0, C * C - (C - g0) * (C - g0)))
        const v1 = C - Math.sqrt(Math.max(0, C * C - (C - g1) * (C - g1)))

        // Edge shared with the frame, from the start end to the end end
        if (sm === "attach") b.M(0, 0)
        else if (sm === "near") b.M(-g0, 0)
        else b.M(-F0, 0)
        if (em === "attach") b.L(w, 0)
        else if (em === "near") { b.L(w + g1, 0); b.L(w + g1, C); b.A(C, 0, w, v1) }
        else { b.L(w + F1, 0); b.A(F1, 0, w, F1) }
        // End side, then the far corner at the end
        if (em === "attach") { b.L(w, h + Fb); b.A(Fb, 0, w - Fb, h) }
        else { b.L(w, h - R); b.A(R, 1, w - R, h) }
        // Far edge, then the far corner at the start
        if (sm === "attach") { b.L(Fb, h); b.A(Fb, 0, 0, h + Fb) }
        else { b.L(R, h); b.A(R, 1, 0, h - R) }
        // Start side back to the frame
        if (sm === "attach") b.L(0, 0)
        else if (sm === "near") { b.L(0, v0); b.A(C, 0, -g0, C); b.L(-g0, 0) }
        else { b.L(0, F0); b.A(F0, 0, -F0, 0) }
        b.Z()
    }

    function fillPath() {
        if (root.progress <= 0) return "M 0 0"
        const b = _builder(0, 0)
        _fill(b)
        return b.str() || "M 0 0"
    }

    // The panel's shape in screen coordinates, for the frame's shared shadow.
    function materialPath() {
        if (root.progress <= 0 || !root.castsShadow) return ""
        const b = _builder(area.x, area.y)
        _fill(b)
        return b.str()
    }

    // One closed outline: the frame's inner edge all the way round, with the
    // panel's free edges in place of the stretch of frame it hangs from. It
    // runs half a border width inside the material (frame or panel), so the
    // frame part and the panel part meet exactly where they join.
    function outlinePath() {
        const w = root.alongLength, h = root.revealed
        if (h < 0.5 || root.borderWidth <= 0) return "M 0 0"
        const b = _builder(0, 0)
        const d = root.borderWidth / 2
        const C = root.frameCorner, Cd = C + d
        const R = Math.min(root.radius, h / 2, w / 2)
        const Rp = Math.max(0, R - d)
        const Fb = Math.min(root.fillet, h)
        const sm = root.startMode, em = root.endMode
        const g0 = root.gapStart, g1 = root.gapEnd
        const F0 = Math.min(root.fillet, h, Math.max(0, g0 - C))
        const F1 = Math.min(root.fillet, h, Math.max(0, g1 - C))
        // The frame's inner edge, pushed d into the frame (panel coordinates)
        const Lu = -g0 - d, Ru = w + g1 + d, Tv = -d, Bv = _spanAcross() + d
        // Where the frame's corner curve meets the panel's side line ("near")
        const dx0 = d - (C - g0), dx1 = C - g1 - d
        const vS = C - Math.sqrt(Math.max(0, Cd * Cd - dx0 * dx0))
        const vE = C - Math.sqrt(Math.max(0, Cd * Cd - dx1 * dx1))

        // Frame, clockwise from the panel's end round to its start
        if (em === "attach") b.M(w + d, h + Fb)
        else if (em === "near") { b.M(w - d, vE); b.A(Cd, 1, Ru, C) }
        else { b.M(w + F1, Tv); b.L(Ru - Cd, Tv); b.A(Cd, 1, Ru, C) }
        b.L(Ru, Bv - Cd); b.A(Cd, 1, Ru - Cd, Bv)
        b.L(Lu + Cd, Bv); b.A(Cd, 1, Lu, Bv - Cd)
        if (sm === "attach") b.L(Lu, h + Fb)
        else if (sm === "near") { b.L(Lu, C); b.A(Cd, 1, d, vS) }
        else { b.L(Lu, C); b.A(Cd, 1, Lu + Cd, Tv); b.L(-F0, Tv) }

        // Panel, from its start back round to its end
        if (sm === "attach") b.A(Fb + d, 1, Fb, h - d)
        else {
            if (sm === "free") b.A(F0 + d, 1, d, F0)
            b.L(d, h - R); b.A(Rp, 0, R, h - d)
        }
        if (em === "attach") { b.L(w - Fb, h - d); b.A(Fb + d, 1, w + d, h + Fb) }
        else {
            b.L(w - R, h - d); b.A(Rp, 0, w - d, h - R)
            if (em === "near") b.L(w - d, vE)
            else { b.L(w - d, F1); b.A(F1 + d, 1, w + F1, Tv) }
        }
        b.Z()
        return b.str()
    }

    // ── Rendering ───────────────────────────────────────────────────────────
    // Everything lives inside the frame, so nothing ever stacks on top of it.
    Item {
        id: area
        x: root.insetSide
        y: root.insetTop
        width: root.width - 2 * root.insetSide
        height: root.height - root.insetTop - root.insetBottom
        clip: true
        visible: root.progress > 0

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.fillColor
                fillRule: ShapePath.WindingFill
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: root.fillPath() }
            }
        }

        // The revealed part of the panel. Content is part of the panel and
        // slides out of the frame with it in one motion (a separate delayed
        // fade and drift read as an empty drawer followed by a second one on
        // fast monitors). It is only clipped while the drawer is moving.
        Item {
            id: viewport
            x: root.horizontal ? root.alongOffset
                : root.edge === "left" ? 0 : area.width - root.revealed
            y: root.edge === "top" ? 0
                : root.edge === "bottom" ? area.height - root.revealed : 0
            width: root.horizontal ? root.panelWidth : root.revealed
            height: root.horizontal ? root.revealed : area.height
            clip: root.progress < 1 || root.clipContent

            Item {
                id: panelContent
                width: root.panelWidth
                height: root.horizontal ? root.panelHeight : area.height
                x: root.edge === "left" ? root.revealed - root.panelWidth : 0
                y: root.edge === "top" ? root.revealed - root.panelHeight : 0
            }
        }
    }

    // The border: panel + frame as one outline (see the note at the top). Not
    // clipped, since half of it runs inside the frame material. Only shown on a
    // drawer that is out, so the frame is borderless again once it closes.
    Shape {
        x: area.x
        y: area.y
        width: area.width
        height: area.height
        visible: area.visible && root.outlineOpacity > 0
        opacity: root.outlineOpacity
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.borderColor
            strokeWidth: root.borderWidth
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.outlinePath() }
        }
    }
}
