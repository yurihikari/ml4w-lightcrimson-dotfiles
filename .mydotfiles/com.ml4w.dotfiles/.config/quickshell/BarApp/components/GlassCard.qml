import QtQuick
import qs.CustomTheme

// The recurring "glass" surface: a faint primary-tinted fill with a slightly
// stronger hairline border. Drop content inside; tweak radius/alpha as needed.
Rectangle {
    property real fillAlpha: 0.05
    property real borderAlpha: 0.12

    radius: 14
    color: Theme.withAlpha(Theme.primary, fillAlpha)
    border.color: Theme.withAlpha(Theme.primary, borderAlpha)
    border.width: 1
}
