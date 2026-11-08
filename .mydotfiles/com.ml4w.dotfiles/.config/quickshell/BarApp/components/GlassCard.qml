import QtQuick
import qs.CustomTheme

// The recurring "glass" surface: a faint primary-tinted fill. No outline: like
// the frame, surfaces are told apart by tone rather than borders. Drop content inside; tweak radius/alpha as needed.
Rectangle {
    property real fillAlpha: 0.08
    property real borderAlpha: 0

    radius: 14
    color: Theme.withAlpha(Theme.primary, fillAlpha)
    border.color: Theme.withAlpha(Theme.primary, borderAlpha)
    border.width: 1
}
