import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// The screen frame: bar, side strips and bottom strip as ONE shape in one
// window, with the bar's content on top of it.
//
// Drawing the frame as a single shape (instead of four windows plus corner
// pieces) means no seams anywhere, and lets the frame and every open drawer
// share one soft shadow: the union of the frame and the drawers (FrameState)
// is blurred and only kept outside that union, so it falls on the windows but
// never darkens the glass itself.
Item {
    id: root

    property var screen
    property var modelData
    onModelDataChanged: screen = modelData

    // Frame geometry (FrameDrawer's insets match these), snapped to whole
    // device pixels like FrameDrawer's, so at fractional scales the frame and
    // a drawer meet on a pixel edge instead of both half-covering one column.
    readonly property real dpr: frameWindow.devicePixelRatio > 0 ? frameWindow.devicePixelRatio : 1
    function snap(v) { return Math.round(v * dpr) / dpr }
    readonly property real frameBar: snap(40)
    readonly property real frameSide: snap(10)
    readonly property real frameBottom: snap(10)
    readonly property real frameCorner: snap(20)
    readonly property string screenName: screen ? screen.name : ""

    // Reserves the bar's space for windows. The frame window itself covers the
    // screen and ignores exclusive zones; the bar's old window reserved 30px
    // (gaps_out takes it from there).
    PanelWindow {
        screen: root.screen
        anchors { top: true; left: true; right: true }
        implicitHeight: 1
        exclusiveZone: 30
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-exclusion"
    }

    PanelWindow {
        id: frameWindow
        screen: root.screen
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrLayershell.None
        exclusionMode: WlrLayershell.Ignore
        color: "transparent"

        // Drawers' focus grabs include the frame (FrameState)
        Component.onCompleted: FrameState.addFrame(frameWindow)
        Component.onDestruction: FrameState.removeFrame(frameWindow)

        readonly property real fw: width
        readonly property real fh: height

        // Input only on the frame itself; everything else reaches the windows.
        mask: Region {
            Region { x: 0; y: 0; width: frameWindow.fw; height: root.frameBar }
            Region { x: 0; y: root.frameBar; width: root.frameSide; height: frameWindow.fh - root.frameBar }
            Region { x: frameWindow.fw - root.frameSide; y: root.frameBar; width: root.frameSide; height: frameWindow.fh - root.frameBar }
            Region { x: 0; y: frameWindow.fh - root.frameBottom; width: frameWindow.fw; height: root.frameBottom }
        }

        // ── Paths ───────────────────────────────────────────────────────────
        function f(v) { return (Math.round(v * 100) / 100).toString() }

        // The frame: the screen with a rounded hole. A corner a drawer has
        // taken over is left square; the drawer draws it.
        function framePath() {
            const W = frameWindow.fw, H = frameWindow.fh, C = root.frameCorner
            if (W <= 0 || H <= 0) return "M 0 0"
            const x0 = root.frameSide, y0 = root.frameBar, x1 = W - root.frameSide, y1 = H - root.frameBottom
            const s = root.screenName
            const tl = FrameCorners.taken(s, "topLeft") ? 0 : C
            const tr = FrameCorners.taken(s, "topRight") ? 0 : C
            const bl = FrameCorners.taken(s, "bottomLeft") ? 0 : C
            const br = FrameCorners.taken(s, "bottomRight") ? 0 : C
            const A = (r, x, y) => " A " + f(r) + " " + f(r) + " 0 0 0 " + f(x) + " " + f(y)
            // Outer edge clockwise, hole counter-clockwise
            return "M 0 0 L " + f(W) + " 0 L " + f(W) + " " + f(H) + " L 0 " + f(H) + " Z"
                + " M " + f(x1 - tr) + " " + f(y0) + " L " + f(x0 + tl) + " " + f(y0) + A(tl, x0, y0 + tl)
                + " L " + f(x0) + " " + f(y1 - bl) + A(bl, x0 + bl, y1)
                + " L " + f(x1 - br) + " " + f(y1) + A(br, x1, y1 - br)
                + " L " + f(x1) + " " + f(y0 + tr) + A(tr, x1 - tr, y0) + " Z"
        }

        // Frame + every open drawer on this screen, for the shared shadow
        function materialPath() {
            let p = framePath()
            const ds = FrameState.drawers
            for (let i = 0; i < ds.length; i++) {
                if (!ds[i] || ds[i].screenName !== root.screenName) continue
                const m = ds[i].materialPath()
                if (m) p += " " + m
            }
            return p
        }

        // ── Shared shadow ───────────────────────────────────────────────────
        // An opaque silhouette of frame + drawers, never shown itself...
        Item {
            id: silhouette
            anchors.fill: parent
            visible: false
            layer.enabled: true

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "black"
                    fillRule: ShapePath.WindingFill
                    strokeColor: "transparent"
                    strokeWidth: 0
                    PathSvg { path: frameWindow.materialPath() }
                }
            }
        }

        // ...blurred into a shadow (same tint as the old popup shadows: a
        // heavily darkened accent, so it follows the wallpaper)...
        Item {
            id: shadowLayer
            anchors.fill: parent
            visible: false
            layer.enabled: true

            MultiEffect {
                anchors.fill: parent
                source: silhouette
                autoPaddingEnabled: false
                shadowEnabled: true
                shadowColor: Qt.darker(Theme.primary, 9)
                shadowOpacity: 0.9
                shadowBlur: 0.6
                blurMax: 24
                shadowVerticalOffset: 2
                shadowHorizontalOffset: 0
            }
        }

        // ...then cut away inside the silhouette, so only the part falling on
        // the windows remains. (A separate pass: MultiEffect masks its source
        // before building the shadow, so masking in the same pass erased it.)
        MultiEffect {
            anchors.fill: parent
            source: shadowLayer
            autoPaddingEnabled: false
            maskEnabled: true
            maskInverted: true
            maskSource: silhouette
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.2
        }

        // ── The frame ───────────────────────────────────────────────────────
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.withAlpha(Theme.background, 0.8)
                fillRule: ShapePath.WindingFill
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: frameWindow.framePath() }
            }
        }

        // ── Frame actions ───────────────────────────────────────────────────
        // Every hit area runs a few pixels past the screen edge. Pushed against
        // an edge, the pointer sits a hair inside the screen, but Wayland's
        // fixed-point coordinates round that up to exactly the screen's width
        // or height, which is just outside an area that stops at the edge. So
        // the very corner (where the pointer lands when flung there) did
        // nothing until the pointer moved back a pixel.
        readonly property real overhang: 6
        MouseArea {
            x: -frameWindow.overhang; y: root.frameBar
            width: root.frameSide + frameWindow.overhang; height: frameWindow.fh - root.frameBar + frameWindow.overhang
            onClicked: Sys.run(["qs", "ipc", "call", "wallpaper", "toggle"])
        }
        MouseArea {
            x: frameWindow.fw - root.frameSide; y: root.frameBar
            width: root.frameSide + frameWindow.overhang; height: frameWindow.fh - root.frameBar + frameWindow.overhang
            onClicked: Sys.run(["qs", "ipc", "call", "sidebar", "toggle"])
        }
        MouseArea {
            x: root.frameSide; y: frameWindow.fh - root.frameBottom
            width: frameWindow.fw - 2 * root.frameSide; height: root.frameBottom + frameWindow.overhang
            onClicked: dockPopup.active = !dockPopup.active
        }

        // ── Corners ─────────────────────────────────────────────────────────
        // The bottom corners open their drawers (CornerDrawer): hover opens
        // after a short pause, a click opens it until dismissed (or pins one
        // that hover opened). They take the corner's end of the side and
        // bottom strips, in front of the strips' own actions (the input mask
        // keeps them to the frame itself).
        readonly property real cornerSize: 64
        MouseArea {
            id: quickCorner
            x: -frameWindow.overhang; y: frameWindow.fh - frameWindow.cornerSize
            width: frameWindow.cornerSize + frameWindow.overhang
            height: frameWindow.cornerSize + frameWindow.overhang
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Corners.toggle("quick", root.screenName)
        }
        MouseArea {
            id: captureCorner
            x: frameWindow.fw - frameWindow.cornerSize; y: frameWindow.fh - frameWindow.cornerSize
            width: frameWindow.cornerSize + frameWindow.overhang
            height: frameWindow.cornerSize + frameWindow.overhang
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Corners.toggle("capture", root.screenName)
        }

        // ── The bar ─────────────────────────────────────────────────────────
        MainBar { id: bar; screen: root.screen }
    }

    DockPopup { id: dockPopup; screen: root.screen }

    // Bottom left: quick settings
    CornerDrawer {
        id: quickDrawer
        screen: root.screen
        key: "quick"; side: "left"
        cornerHovered: quickCorner.containsMouse
        panelW: 380
        bodyHeight: quickPanel.implicitHeight
        busy: quickPanel.vpnOpen && quickDrawer.open
        QuickPanel {
            id: quickPanel
            width: parent ? parent.width : 0
            screenName: root.screenName
            shown: quickDrawer.open
        }
    }

    // Bottom right: capture
    CornerDrawer {
        id: captureDrawer
        screen: root.screen
        key: "capture"; side: "right"
        cornerHovered: captureCorner.containsMouse
        panelW: 380
        bodyHeight: capturePanel.implicitHeight
        CapturePanel {
            id: capturePanel
            width: parent ? parent.width : 0
            screenName: root.screenName
            shown: captureDrawer.open
        }
    }
}
