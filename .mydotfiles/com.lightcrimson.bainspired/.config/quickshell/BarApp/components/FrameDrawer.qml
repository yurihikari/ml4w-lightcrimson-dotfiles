import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.CustomTheme
import qs.BarApp.services

// BA Inspired: a floating game-style window instead of a drawer growing out of a
// screen frame (this theme has no frame).
//
// Same API as LightCrimson's FrameDrawer, so every popup, the sidebar, the
// toasts and the corner panels work unchanged: fill it like an Item sized to
// panelWidth x panelHeight, set `edge` / `hAlign` / `hMargin`, and listen for
// closed() to unmap the window. The insets are the free space kept round the
// screen (bar height plus a gap, and a gap at the sides and bottom), so
// everything that places itself with insetTop / insetSide lines up.
//
// Look: white body with a hairline border and a soft shadow, a sky-blue
// stripe along the top with a small yellow tab, and a few faint triangles in
// the far corner. It pops in (a short rise and fade) rather than sliding.
Item {
    id: root
    anchors.fill: parent

    property bool open: false
    signal closed()

    property string edge: "top"             // "top" | "bottom" | "left" | "right" | "free"
    property string hAlign: "center"        // top/bottom/free: "center" | "left" | "right" | "free"
    property real hMargin: 0
    property real freeX: 0
    // Edge "free": the window's top (window coords), for a window that isn't
    // attached to an edge, like the media player growing out of HyperBA's
    // now-playing banner. It doesn't rise from an edge, it only fades.
    property real freeY: 0
    property real panelWidth: 400
    property real panelHeight: 300

    readonly property real dpr: QsWindow.window && QsWindow.window.devicePixelRatio > 0 ? QsWindow.window.devicePixelRatio : 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    // Free space round the screen: the bar, then a gap.
    property real insetTop: snap(PanelStyle.topInsetFor(screenName,
        horizontal ? panelX : (edge === "left" ? 0 : width)))
    property real insetBottom: snap(14)
    property real insetSide: snap(14)

    // Kept for API compatibility (LightCrimson's frame geometry)
    property real radius: PanelStyle.radiusWindow
    property real fillet: 0
    property real frameCorner: 0
    property color fillColor: PanelStyle.windowFill
    property color borderColor: PanelStyle.windowBorder
    property real borderWidth: 1
    property int duration: 260
    property bool outlineSuppressed: false
    property bool clipContent: false
    property bool castsShadow: true

    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property bool horizontal: edge === "top" || edge === "bottom" || edge === "free"
    readonly property bool fromTop: edge !== "bottom"

    // Wait for the window's real size (see LightCrimson's FrameDrawer)
    readonly property bool _sized: width > 2 * insetSide && height > insetTop + insetBottom
    property bool _go: false
    function _sync() {
        if (open && _sized) startDelay.restart()
        else { startDelay.stop(); _go = false }
    }
    onOpenChanged: { _sync(); if (!open && progress <= 0) closed() }
    on_SizedChanged: _sync()
    Component.onCompleted: { _sync(); FrameState.add(root) }
    Component.onDestruction: FrameState.remove(root)
    Timer { id: startDelay; interval: 16; onTriggered: root._go = root.open && root._sized }

    property real progress: _go ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: root.open ? root.duration : Math.round(root.duration * 0.7)
            easing.type: root.open ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.2
            onRunningChanged: if (!running && !root.open) root.closed()
        }
    }
    readonly property real shown: Math.max(0, Math.min(1, progress))

    default property alias content: panelContent.data
    readonly property alias contentItem: panelContent

    // Kept for callers: how much of the panel is out (all of it, once shown)
    readonly property real revealed: (horizontal ? panelHeight : panelWidth) * shown

    // ── Placement ───────────────────────────────────────────────────────────
    readonly property real panelX: hAlign === "free" ? freeX
        : hAlign === "left" ? Math.max(snap(hMargin), insetSide)
        : hAlign === "right" ? width - Math.max(snap(hMargin), insetSide) - panelWidth
        : snap((width - panelWidth) / 2)
    readonly property real alongOffset: horizontal ? panelX - area.x : 0

    readonly property real bodyX: horizontal ? panelX : edge === "left" ? area.x : area.x + area.width - panelWidth
    readonly property real bodyY: edge === "free" ? freeY
        : edge === "top" || !horizontal ? area.y : area.y + area.height - panelHeight
    readonly property real bodyW: panelWidth
    readonly property real bodyH: horizontal ? panelHeight : area.height

    // No frame: nothing to take over, no shared shadow, no frame outline.
    function materialPath() { return "" }
    function fillPath() { return "M 0 0" }
    function outlinePath() { return "M 0 0" }

    Item {
        id: area
        x: root.insetSide
        y: root.insetTop
        width: root.width - 2 * root.insetSide
        height: root.height - root.insetTop - root.insetBottom
    }

    // ── The window ──────────────────────────────────────────────────────────
    Item {
        id: win
        x: root.bodyX
        y: root.bodyY
        width: root.bodyW
        height: root.bodyH
        visible: root.progress > 0.001
        opacity: Math.min(1, root.progress * 1.6)
        // A short rise away from the edge it belongs to
        transform: Translate {
            readonly property real d: (1 - root.progress) * 14
            x: root.edge === "left" ? -d : root.edge === "right" ? d : 0
            y: root.edge === "top" ? -d : root.edge === "bottom" ? d : 0
        }

        // Soft shadow
        RectangularShadow {
            anchors.fill: body
            visible: root.castsShadow
            radius: body.radius
            offset.y: 6
            blur: 26
            spread: -2
            color: Theme.withAlpha(Theme.shadow, 0.28)
        }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: root.radius
            color: root.fillColor
            border.color: root.borderColor
            border.width: root.borderWidth

            // Decoration, clipped to the window's rounded shape (inset by the
            // border), so it follows the corners and never covers the border
            ClippingRectangle {
                id: decoClip
                anchors.fill: parent
                anchors.margins: root.borderWidth
                radius: Math.max(0, root.radius - root.borderWidth)
                color: "transparent"

            // Faint triangles hugging the far corner (small enough to stay
            // in the window's padding, behind no content)
            Shape {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 84; height: 60
                opacity: 0.6
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.withAlpha(Theme.sky, 0.22); strokeColor: "transparent"
                    PathSvg { path: "M 84 18 L 84 60 L 26 60 Z" }
                }
                ShapePath {
                    fillColor: Theme.withAlpha(Theme.blue, 0.12); strokeColor: "transparent"
                    PathSvg { path: "M 84 38 L 84 60 L 54 60 Z" }
                }
            }

            // Top stripe: sky-blue band with a yellow tab at its end
            Item {
                id: stripe
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.leftMargin: decoClip.radius; anchors.rightMargin: decoClip.radius
                height: 4
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.blue }
                        GradientStop { position: 1; color: Theme.sky }
                    }
                }
                Shape {
                    anchors.right: parent.right
                    width: 34; height: parent.height
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.yellow; strokeColor: "transparent"
                        PathSvg { path: "M 6 0 L 34 0 L 34 4 L 2 4 Z" }
                    }
                }
            }
            }
        }

        // Content
        Item {
            id: viewport
            anchors.fill: parent
            clip: root.clipContent || root.progress < 1
            Item {
                id: panelContent
                width: root.panelWidth
                height: root.bodyH
            }
        }
    }
}
