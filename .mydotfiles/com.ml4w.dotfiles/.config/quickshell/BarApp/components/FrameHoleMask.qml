import Quickshell

// Input region for a drawer window that covers the screen (for its click-
// outside-to-close backdrop): the whole window except the frame itself, so the
// bar and the side and bottom strips stay clickable while the drawer is open
// (see FrameState). Set `active: false` to take no input at all.
Region {
    id: r
    property var window: null
    property bool active: true

    readonly property real w: window && active ? window.width : 0
    readonly property real h: window && active ? window.height : 0
    // The frame's thickness (ScreenFrame: bar 40, sides and bottom 10)
    readonly property real bar: 40
    readonly property real side: 10

    x: 0; y: 0; width: w; height: h
    Region { intersection: Intersection.Subtract; x: 0; y: 0; width: r.w; height: r.bar }
    Region { intersection: Intersection.Subtract; x: 0; y: 0; width: r.side; height: r.h }
    Region { intersection: Intersection.Subtract; x: r.w - r.side; y: 0; width: r.side; height: r.h }
    Region { intersection: Intersection.Subtract; x: 0; y: r.h - r.side; width: r.w; height: r.side }
}
