pragma Singleton
import QtQuick
import Quickshell

// BA Inspired theme palette: a bright game-HUD look. White panels, deep navy ink,
// a sky-blue accent, a sunny yellow highlight and a coral for alerts.
//
// Unlike LightCrimson, the palette is fixed: it doesn't follow the wallpaper
// (reloadTheme() is kept for callers, and does nothing). The property names
// are the same as LightCrimson's, so every component keeps working: `primary`
// is the ink (text, icons, tinted fills) and `background` the panel white.
QtObject {
    id: root

    // Nunito (SIL Open Font License, fonts/OFL.txt), loaded from the theme
    // itself so nothing has to be installed.
    property var _font: FontLoader { source: Qt.resolvedUrl("fonts/Nunito.ttf") }
    readonly property string fontFamily: _font.status === FontLoader.Ready ? _font.name : "Fira Sans"

    readonly property bool isLight: true

    // ── BA Inspired palette ─────────────────────────────────────────────────────
    readonly property color ink: "#2b4566"          // text and icons
    readonly property color inkSoft: "#5d7593"      // secondary text
    readonly property color blue: "#1e9bf0"         // accent: selection, primary buttons
    readonly property color blueDeep: "#0f74c8"     // pressed / gradient end
    readonly property color sky: "#8fd6ff"          // light accent, stripes
    readonly property color yellow: "#ffd93b"       // highlight, confirm buttons
    readonly property color coral: "#ff5f7e"        // alerts, badges
    readonly property color paper: "#ffffff"        // panel body
    readonly property color mist: "#eef4fa"         // cards on panels
    readonly property color line: "#d5e2ee"         // hairlines and borders
    readonly property color accentInk: "#ffffff"     // text and icons on blue / coral
    readonly property color plate: "#ffffff"        // bar plates and counters

    // ── Names the components use ────────────────────────────────────────────
    property color background: "#f7fafd"
    property color error: coral
    property color error_container: "#ffe1e7"
    property color inverse_on_surface: "#eef4fa"
    property color inverse_primary: sky
    property color inverse_surface: ink
    property color on_background: ink
    property color on_error: "#ffffff"
    property color on_error_container: "#7a1730"
    property color on_primary: "#ffffff"
    property color on_primary_container: "#0b3a63"
    property color on_primary_fixed: "#0b3a63"
    property color on_primary_fixed_variant: blueDeep
    property color on_secondary: "#ffffff"
    property color on_secondary_container: ink
    property color on_secondary_fixed: ink
    property color on_secondary_fixed_variant: inkSoft
    property color on_surface: ink
    property color on_surface_variant: inkSoft
    property color on_tertiary: "#ffffff"
    property color on_tertiary_container: "#0b3a63"
    property color on_tertiary_fixed: "#0b3a63"
    property color on_tertiary_fixed_variant: blueDeep
    property color outline: "#9fb3c8"
    property color outline_variant: line
    property color primary: ink
    property color primary_container: "#d9eeff"
    property color primary_fixed: "#d9eeff"
    property color primary_fixed_dim: sky
    property color scrim: "#0b1a2b"
    property color secondary: inkSoft
    property color secondary_container: mist
    property color secondary_fixed: mist
    property color secondary_fixed_dim: line
    property color shadow: "#1d3a5c"
    property color source_color: blue
    property color surface: "#f7fafd"
    property color surface_bright: "#ffffff"
    property color surface_container: "#f1f6fb"
    property color surface_container_high: "#e9f1f8"
    property color surface_container_highest: "#e1ebf5"
    property color surface_container_low: "#f7fafd"
    property color surface_container_lowest: "#ffffff"
    property color surface_dim: "#e3ebf3"
    property color surface_tint: blue
    property color surface_variant: mist
    property color tertiary: blue
    property color tertiary_container: "#d9eeff"
    property color tertiary_fixed: "#d9eeff"
    property color tertiary_fixed_dim: sky

    readonly property color accent: blue

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Fixed palette: nothing to reload (kept so callers don't break).
    function reloadTheme() {}
}
