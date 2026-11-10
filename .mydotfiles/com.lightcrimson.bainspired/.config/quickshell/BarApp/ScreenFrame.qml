import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// BA Inspired: the bar band across the top of each screen (no frame round the
// screen), invisible edges that open the wallpapers / sidebar / dock, and the
// two bottom corners' panels.
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

        // Input only on the bar and the screen edges; everything else reaches
        // the windows.
        readonly property real edge: 3
        mask: Region {
            Region { x: 0; y: 0; width: frameWindow.fw; height: root.frameBar }
            Region { x: 0; y: root.frameBar; width: frameWindow.edge; height: frameWindow.fh - root.frameBar }
            Region { x: frameWindow.fw - frameWindow.edge; y: root.frameBar; width: frameWindow.edge; height: frameWindow.fh - root.frameBar }
            Region { x: 0; y: frameWindow.fh - frameWindow.edge; width: frameWindow.fw; height: frameWindow.edge }
            Region { x: 0; y: frameWindow.fh - frameWindow.cornerSize; width: frameWindow.cornerSize / 2; height: frameWindow.cornerSize }
            Region { x: frameWindow.fw - frameWindow.cornerSize / 2; y: frameWindow.fh - frameWindow.cornerSize; width: frameWindow.cornerSize / 2; height: frameWindow.cornerSize }
        }

        // ── The bar band (BA Inspired: no frame round the screen) ───────────────
        // A white HUD band with a hairline, a blue-to-sky stripe under its
        // left part and a slanted yellow tab, over a soft shadow.
        RectangularShadow {
            anchors.fill: band
            offset.y: 3
            blur: 18
            spread: -4
            color: Theme.withAlpha(Theme.shadow, 0.22)
        }
        Rectangle {
            id: band
            x: 0; y: 0
            width: frameWindow.fw
            height: root.frameBar
            color: Theme.withAlpha(Theme.paper, 0.94)
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1
                color: Theme.line
            }
            Rectangle {
                anchors.left: parent.left; anchors.bottom: parent.bottom
                width: Math.min(parent.width * 0.32, 520); height: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.blue }
                    GradientStop { position: 0.75; color: Theme.sky }
                    GradientStop { position: 1; color: Theme.withAlpha(Theme.sky, 0) }
                }
            }
            Shape {
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.rightMargin: 36
                width: 60; height: 3
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.yellow; strokeColor: "transparent"
                    PathSvg { path: "M 3 0 L 60 0 L 57 3 L 0 3 Z" }
                }
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
            width: frameWindow.edge + frameWindow.overhang; height: frameWindow.fh - root.frameBar + frameWindow.overhang
            onClicked: Sys.run(["qs", "ipc", "call", "wallpaper", "toggle"])
        }
        MouseArea {
            x: frameWindow.fw - frameWindow.edge; y: root.frameBar
            width: frameWindow.edge + frameWindow.overhang; height: frameWindow.fh - root.frameBar + frameWindow.overhang
            onClicked: Sys.run(["qs", "ipc", "call", "sidebar", "toggle"])
        }
        MouseArea {
            x: frameWindow.edge; y: frameWindow.fh - frameWindow.edge
            width: frameWindow.fw - 2 * frameWindow.edge; height: frameWindow.edge + frameWindow.overhang
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
            width: frameWindow.cornerSize / 2 + frameWindow.overhang
            height: frameWindow.cornerSize + frameWindow.overhang
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Corners.toggle("quick", root.screenName)
        }
        MouseArea {
            id: captureCorner
            x: frameWindow.fw - frameWindow.cornerSize / 2; y: frameWindow.fh - frameWindow.cornerSize
            width: frameWindow.cornerSize / 2 + frameWindow.overhang
            height: frameWindow.cornerSize + frameWindow.overhang
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Corners.toggle("capture", root.screenName)
        }

        // ── The bar ─────────────────────────────────────────────────────────
        MainBar { id: bar; screen: root.screen; onOpenDock: dockPopup.active = !dockPopup.active }
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
