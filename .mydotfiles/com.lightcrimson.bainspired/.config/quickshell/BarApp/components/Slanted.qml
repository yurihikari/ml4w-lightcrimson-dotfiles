import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.CustomTheme
import qs.BarApp.services

// The BA themes' basic shape: a parallelogram leaning right (the top edge sits
// `slant` px right of the bottom one). Backs chips, buttons, tabs, plates.
//
// `leftEdge` / `rightEdge` false make that side straight instead (a plate
// flush with a screen edge). `shadow` adds a soft drop shadow (plates that
// float over the wallpaper).
Item {
    id: root
    property color fill: "white"
    property color fill2: fill            // gradient to the right (optional)
    property color stroke: "transparent"
    property real strokeWidth: 0
    property real slant: Math.min(PanelStyle.slant, height * 0.35)
    property bool leftEdge: true
    property bool rightEdge: true
    property bool shadow: false

    readonly property real _l: leftEdge ? slant : 0
    readonly property real _r: rightEdge ? slant : 0

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
            PathSvg {
                path: "M " + root._l + " 0 L " + root.width + " 0 L " + (root.width - root._r) + " " + root.height + " L 0 " + root.height + " Z"
            }
        }
    }
}
