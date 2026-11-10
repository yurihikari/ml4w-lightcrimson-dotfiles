pragma Singleton
import QtQuick
import qs.CustomTheme

// Shared look for everything shown in the bar popout, so the sections read as
// one panel rather than separate popups: the same padding, sizes, radii and
// tonal surfaces everywhere. Surfaces are told apart by tone, not outlines,
// like the frame they grow out of.
QtObject {
    // Layout
    readonly property int pad: 20             // panel inner padding
    readonly property int gap: 14             // between blocks
    readonly property int headerHeight: 40

    // The right-hand sections (keyboard, clipboard, calendar, system) share
    // one anchor flush against the right frame and one height, so switching
    // between them only changes the panel's width around a fixed corner.
    readonly property int rightHeight: 640
    readonly property int narrowWidth: 440
    readonly property int rightMargin: 10     // = frame side thickness (attached)

    // Shapes
    readonly property int radiusCard: 14
    readonly property int radiusControl: 12
    readonly property int controlHeight: 40

    // Popout outline (same for every section, so it doesn't shift while morphing)
    readonly property color outline: Theme.withAlpha(Theme.primary, 0.64)
    // Drawer outline width. 0: no outline; the frame and its drawers read as
    // one material, set apart by the shared shadow alone. (Each drawer drew
    // its outline round the whole frame, so with two drawers open at once,
    // say a toast arriving while the sidebar is out, each one's outline cut
    // across the other.) 2 brings the outlines back.
    readonly property real outlineWidth: 0

    // Tonal surfaces
    readonly property color cardFill: Theme.withAlpha(Theme.primary, 0.06)
    readonly property color cardHover: Theme.withAlpha(Theme.primary, 0.11)
    readonly property color fieldFill: Theme.withAlpha(Theme.primary, 0.06)
    readonly property color fieldFocus: Theme.withAlpha(Theme.primary, 0.10)
    readonly property color fieldRing: Theme.withAlpha(Theme.primary, 0.35)
    readonly property color divider: Theme.withAlpha(Theme.primary, 0.10)

    // Text
    readonly property real dim: 0.55      // secondary text
    readonly property real faint: 0.35    // hints, placeholders
    readonly property int titleSize: 16
    readonly property int subtitleSize: 11
    readonly property int bodySize: 13
    readonly property int labelSize: 10
}
