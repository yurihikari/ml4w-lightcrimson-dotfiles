import QtQuick
import QtQuick.Shapes
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
// The fill never paints over the frame itself: it is clipped to the area inside
// the frame. A panel flush against a side frame takes over the frame's inner
// corner there; FrameCorners tells the frame to hide its own corner meanwhile,
// so the two never stack.
//
// The frame has no border, so a border that simply stopped at the frame looked
// cut off. While the drawer is out, its border is one continuous outline: the
// panel's edge, through the curves, into the frame's inner edge and around the
// whole screen. It fades in once the drawer has landed and fades out as it
// closes, so the frame only has a border while a popup is open. That outline
// needs the window to cover the whole screen (give small windows an input mask
// instead of shrinking them).
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
    property real panelWidth: 400
    property real panelHeight: 300

    // Frame thickness, in this window's coordinates.
    property real insetTop: 40
    property real insetBottom: 10
    property real insetSide: 10

    property real radius: 30        // the panel's free (convex) corners
    property real fillet: 20        // concave curves where it meets the frame
    property real frameCorner: 20   // radius of the frame's own inner corners
    property color fillColor: Theme.withAlpha(Theme.background, 0.8)
    property color borderColor: Theme.withAlpha(Theme.primary, 0.8)
    property real borderWidth: 2
    property int duration: 400

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property bool fromTop: edge !== "bottom"
    // Attached to the frame at the start / end of the panel's run along the
    // frame (left/right end for top & bottom, bar/bottom frame for the sides).
    readonly property bool attachStart: horizontal ? (hAlign === "left" && hMargin <= insetSide) : true
    readonly property bool attachEnd: horizontal ? (hAlign === "right" && hMargin <= insetSide) : true

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
    Component.onCompleted: _sync()
    Timer {
        id: startDelay
        interval: 32
        onTriggered: root._go = root.open && root._sized
    }

    property real progress: _go ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            // Opening snaps out (OutExpo). Closing with the same curve did
            // nearly all of its travel in the first frame or two, so it read as
            // a vanish; InOutCubic keeps the slide back into the frame visible.
            duration: root.open ? root.duration : Math.round(root.duration * 0.8)
            easing.type: root.open ? Easing.OutExpo : Easing.InOutCubic
            onRunningChanged: if (!running && !root.open) root.closed()
        }
    }

    // The outline doesn't travel with the drawer: it fades in once the drawer
    // has (nearly) landed, and fades out quickly as soon as it starts closing.
    property real outlineOpacity: _go && progress > 0.97 ? 1 : 0
    Behavior on outlineOpacity {
        NumberAnimation { duration: root.open ? 220 : 120; easing.type: Easing.OutCubic }
    }

    default property alias content: panelContent.data
    readonly property alias contentItem: panelContent

    // Run along the frame / depth away from it
    readonly property real alongLength: horizontal ? panelWidth : area.height
    readonly property real depth: horizontal ? panelHeight : panelWidth
    readonly property real revealed: Math.max(0, depth * progress)

    readonly property real panelX: hAlign === "free" ? freeX
        : hAlign === "left" ? Math.max(hMargin, insetSide)
        : hAlign === "right" ? width - Math.max(hMargin, insetSide) - panelWidth
        : Math.round((width - panelWidth) / 2)
    // Panel start along the frame, in area coordinates
    readonly property real alongOffset: horizontal ? panelX - area.x : 0

    // ── Frame corners taken over ────────────────────────────────────────────
    readonly property bool _out: progress > 0
    readonly property bool coversTopLeft: _out && ((edge === "top" && attachStart) || edge === "left")
    readonly property bool coversTopRight: _out && ((edge === "top" && attachEnd) || edge === "right")
    readonly property bool coversBottomLeft: _out && ((edge === "bottom" && attachStart) || edge === "left")
    readonly property bool coversBottomRight: _out && ((edge === "bottom" && attachEnd) || edge === "right")
    onCoversTopLeftChanged: FrameCorners.topLeft += coversTopLeft ? 1 : -1
    onCoversTopRightChanged: FrameCorners.topRight += coversTopRight ? 1 : -1
    onCoversBottomLeftChanged: FrameCorners.bottomLeft += coversBottomLeft ? 1 : -1
    onCoversBottomRightChanged: FrameCorners.bottomRight += coversBottomRight ? 1 : -1
    Component.onDestruction: {
        if (coversTopLeft) FrameCorners.topLeft -= 1
        if (coversTopRight) FrameCorners.topRight -= 1
        if (coversBottomLeft) FrameCorners.bottomLeft -= 1
        if (coversBottomRight) FrameCorners.bottomRight -= 1
    }

    // ── Path building ───────────────────────────────────────────────────────
    // Paths are written as if the panel hung from a frame line at v = 0, with
    // u running along the frame from the panel's start (u = 0). They are then
    // mapped onto the actual edge; mirrored edges flip the arc direction.
    function _builder() {
        const AW = area.width, AH = area.height
        const o = root.alongOffset
        const e = root.edge
        const flip = e === "bottom" || e === "left"
        const parts = []
        const f = v => (Math.round(v * 100) / 100).toString()
        const P = (u, v) => {
            if (e === "top") return f(o + u) + " " + f(v)
            if (e === "bottom") return f(o + u) + " " + f(AH - v)
            if (e === "left") return f(v) + " " + f(o + u)
            return f(AW - v) + " " + f(o + u)
        }
        return {
            M: (u, v) => parts.push("M " + P(u, v)),
            L: (u, v) => parts.push("L " + P(u, v)),
            // sweep 1 = clockwise on screen (in the unmirrored orientation)
            A: (r, sweep, u, v) => parts.push("A " + f(r) + " " + f(r) + " 0 0 "
                + (flip ? 1 - sweep : sweep) + " " + P(u, v)),
            Z: () => parts.push("Z"),
            str: () => parts.join(" ")
        }
    }

    // Span of the area along the frame / away from it
    function _spanAlong() { return root.horizontal ? area.width : area.height }
    function _spanAcross() { return root.horizontal ? area.height : area.width }

    function _cornerPieces(b, w) {
        // The frame's inner corner shape, so a panel flush with the frame's
        // corner can stand in for it while the frame's own corner is hidden.
        const C = root.frameCorner
        if (root.attachStart) { b.M(0, 0); b.L(C, 0); b.A(C, 0, 0, C); b.Z() }
        if (root.attachEnd) { b.M(w, 0); b.L(w, C); b.A(C, 0, w - C, 0); b.Z() }
    }

    function fillPath() {
        const b = _builder()
        const w = root.alongLength, h = root.revealed
        if (root.progress <= 0 && !root.open) return "M 0 0"
        // Once the panel covers the corner it is drawn by the panel itself (two
        // overlapping subpaths would leave a faint anti-aliased arc inside).
        if (h < root.frameCorner) _cornerPieces(b, w)
        if (h < 0.5) return b.str() || "M 0 0"
        const R = Math.min(root.radius, h / 2, w / 2)
        const F = Math.min(root.fillet, h)

        // Edge shared with the frame
        if (root.attachStart) b.M(0, 0); else b.M(-F, 0)
        if (root.attachEnd) b.L(w, 0)
        else { b.L(w + F, 0); b.A(F, 0, w, F) }
        // End side, then the far corner at the end
        if (root.attachEnd) { b.L(w, h + F); b.A(F, 0, w - F, h) }
        else { b.L(w, h - R); b.A(R, 1, w - R, h) }
        // Far edge, then the far corner at the start
        if (root.attachStart) { b.L(F, h); b.A(F, 0, 0, h + F) }
        else { b.L(R, h); b.A(R, 1, 0, h - R) }
        // Start side back to the frame
        if (root.attachStart) b.L(0, 0)
        else { b.L(0, F); b.A(F, 0, -F, 0) }
        b.Z()
        return b.str()
    }

    // One closed outline: the frame's inner edge all the way round, with the
    // panel's free edges in place of the stretch of frame it hangs from. It
    // runs half a border width inside the material (frame or panel), so the
    // frame part and the panel part meet exactly at the fillet tips.
    function outlinePath() {
        const w = root.alongLength, h = root.revealed
        if (h < 0.5 || root.borderWidth <= 0) return "M 0 0"
        const b = _builder()
        const d = root.borderWidth / 2
        const R = Math.min(root.radius, h / 2, w / 2)
        const F = Math.min(root.fillet, h)
        const Rp = Math.max(0, R - d)
        const o = root.alongOffset
        // The frame's inner edge, pushed d into the frame (panel coordinates)
        const Lu = -o - d, Ru = _spanAlong() - o + d, Tv = -d, Bv = _spanAcross() + d
        const C = root.frameCorner + d

        // Frame, clockwise from the panel's end round to its start
        if (root.attachEnd) b.M(w + d, h + F)
        else { b.M(w + F, Tv); b.L(Ru - C, Tv); b.A(C, 1, Ru, Tv + C) }
        b.L(Ru, Bv - C); b.A(C, 1, Ru - C, Bv)
        b.L(Lu + C, Bv); b.A(C, 1, Lu, Bv - C)
        if (root.attachStart) b.L(Lu, h + F)
        else { b.L(Lu, Tv + C); b.A(C, 1, Lu + C, Tv); b.L(-F, Tv) }

        // Panel, from its start back round to its end
        if (root.attachStart) b.A(F + d, 1, F, h - d)
        else { b.A(F + d, 1, d, F); b.L(d, h - R); b.A(Rp, 0, R, h - d) }
        if (root.attachEnd) { b.L(w - F, h - d); b.A(F + d, 1, w + d, h + F) }
        else {
            b.L(w - R, h - d); b.A(Rp, 0, w - d, h - R)
            b.L(w - d, F); b.A(F + d, 1, w + F, Tv)
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

        // The revealed part of the panel. Content slides out of the frame with
        // it, and is only clipped while the drawer is moving.
        Item {
            id: viewport
            x: root.edge === "top" || root.edge === "bottom" ? root.alongOffset
                : root.edge === "left" ? 0 : area.width - root.revealed
            y: root.edge === "top" ? 0
                : root.edge === "bottom" ? area.height - root.revealed : 0
            width: root.horizontal ? root.panelWidth : root.revealed
            height: root.horizontal ? root.revealed : area.height
            clip: root.progress < 1

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
