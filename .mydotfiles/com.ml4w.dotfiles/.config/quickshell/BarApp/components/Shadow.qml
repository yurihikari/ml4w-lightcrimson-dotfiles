import QtQuick
import QtQuick.Effects
import qs.CustomTheme

// Subtle elevation shadow for popups and frames.
//
// Drop it in as the FIRST child of a rounded, transparent container (one whose
// own `color` is transparent, with a separate background rect on top). It fills
// the parent, sits behind it (z: -1), matches the corner radius, and inherits
// the parent's scale/opacity — so it animates in together with the popup.
//
// Kept deliberately light: just enough blur/offset to read as "above" the
// windows behind it, not a heavy drop shadow. The colour is a heavily darkened
// accent rather than flat black, so it harmonises with the theme (and shifts
// with the wallpaper).
RectangularShadow {
    property color tint: Qt.darker(Theme.primary, 6)

    anchors.fill: parent
    z: -1
    radius: 30
    blur: 18
    spread: 0
    offset: Qt.vector2d(0, 5)
    color: Theme.withAlpha(tint, 0.2)
    cached: true
}
