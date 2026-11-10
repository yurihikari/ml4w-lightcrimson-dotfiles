pragma Singleton
import QtQuick
import qs.CustomTheme

// BA Inspired's shared look: floating game-style windows. White body, a slim
// accent stripe on top, light "mist" cards, small radii and slanted controls.
// Same token names as LightCrimson's, plus a few of BA Inspired's own.
QtObject {
    // Layout
    readonly property int pad: 20
    readonly property int gap: 14
    readonly property int headerHeight: 40

    readonly property int rightHeight: 640
    readonly property int narrowWidth: 440
    readonly property int rightMargin: 14     // windows float off the screen edge

    // Shapes
    readonly property int radiusCard: 8
    readonly property int radiusControl: 6
    readonly property int controlHeight: 40
    readonly property int radiusWindow: 10
    // Horizontal lean of slanted controls (tabs, chips, buttons), in px over
    // their height: the shape leans this far to the right at the top.
    readonly property real slant: 8

    // Where floating windows start (below the bar), and whether the bar's
    // plates float over the wallpaper with their own shadow (HyperBA).
    readonly property real topInset: 48
    // Where a floating window starts on a screen, given its left edge x
    // (HyperBA's level card hangs lower than the bar on the left).
    function topInsetFor(screenName, x) { return topInset }
    readonly property bool floatingPlates: false

    readonly property color outline: Theme.line
    readonly property real outlineWidth: 0

    // Surfaces
    readonly property color cardFill: Theme.mist
    readonly property color cardHover: Qt.darker(Theme.mist, 1.04)
    readonly property color fieldFill: Theme.mist
    readonly property color fieldFocus: "#e4effa"
    readonly property color fieldRing: Theme.blue
    readonly property color divider: Theme.line
    readonly property color windowFill: Theme.paper
    readonly property color windowBorder: Theme.line

    // Text
    readonly property real dim: 0.62
    readonly property real faint: 0.4
    readonly property int titleSize: 17
    readonly property int subtitleSize: 11
    readonly property int bodySize: 13
    readonly property int labelSize: 10
}
