import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.CustomTheme
import qs.BarApp.services

// HyperBA's take on the BA themes' basic shape: a parallelogram leaning right
// (the top edge sits right of the bottom one), with rounded corners. Backs
// chips, buttons, tabs and plates.
//
// It leans a little less than `slant` asks (PanelStyle.lean of it), like the
// game's shapes, so the callers keep the BA Inspired values.
//
// `leftEdge` / `rightEdge` false make that side straight instead (a plate
// flush with a screen edge). `shadow` adds a soft drop shadow (plates that
// float over the wallpaper). `radius` rounds the corners.
Item {
    id: root
    property color fill: Theme.plate
    property color fill2: fill            // gradient to the right (optional)
    property color stroke: "transparent"
    property real strokeWidth: 0
    property real slant: Math.min(PanelStyle.slant, height * 0.35)
    property bool leftEdge: true
    property bool rightEdge: true
    property bool shadow: false
    property real radius: Math.min(8, height * 0.22)

    // How far the top edge actually sits right of the bottom one
    readonly property real lean: slant * PanelStyle.lean
    readonly property real _l: leftEdge ? lean : 0
    readonly property real _r: rightEdge ? lean : 0

    // The outline: each corner cut back along both of its edges and joined
    // with a curve through the corner. A straight side is flush with a
    // screen edge: its corners stay square.
    readonly property string _path: {
        const w = width, h = height
        const pts = [[_l, 0], [w, 0], [w - _r, h], [0, h]]
        const n = pts.length
        let d = ""
        for (let i = 0; i < n; i++) {
            const c = pts[i], p = pts[(i + n - 1) % n], q = pts[(i + 1) % n]
            const lp = Math.hypot(p[0] - c[0], p[1] - c[1])
            const lq = Math.hypot(q[0] - c[0], q[1] - c[1])
            const flush = (i === 0 || i === 3) ? !leftEdge : !rightEdge
            const r = flush ? 0 : Math.max(0, Math.min(radius, lp / 2, lq / 2))
            if (r === 0 || lp === 0 || lq === 0) {
                d += (i === 0 ? "M " : " L ") + c[0] + " " + c[1]
                continue
            }
            const a = [c[0] + (p[0] - c[0]) * r / lp, c[1] + (p[1] - c[1]) * r / lp]
            const b = [c[0] + (q[0] - c[0]) * r / lq, c[1] + (q[1] - c[1]) * r / lq]
            d += (i === 0 ? "M " : " L ") + a[0] + " " + a[1]
               + " Q " + c[0] + " " + c[1] + " " + b[0] + " " + b[1]
        }
        return d + " Z"
    }

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: root.shadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.withAlpha(Theme.shadow, 0.45)
            shadowBlur: 0.5
            shadowVerticalOffset: 2
            autoPaddingEnabled: true
        }
        ShapePath {
            strokeColor: root.stroke
            strokeWidth: root.strokeWidth
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: 0
                GradientStop { position: 0; color: root.fill }
                GradientStop { position: 1; color: root.fill2 }
            }
            PathSvg { path: root._path }
        }
    }
}
