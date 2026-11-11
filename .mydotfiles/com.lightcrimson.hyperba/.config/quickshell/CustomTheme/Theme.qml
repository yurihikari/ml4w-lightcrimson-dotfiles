pragma Singleton
import QtQuick
import Quickshell 
import Quickshell.Io 

QtObject { 
    id: root
    
    // HyperBA: LightCrimson's matugen palette (it follows the wallpaper), plus
    // the HUD colour names the BA components use, derived from it, so every
    // plate, counter and button recolours itself with each wallpaper.

    // Nunito (SIL Open Font License, fonts/OFL.txt), loaded from the theme,
    // one file per weight. (The variable font they are cut from only ever
    // drew its default instance, ExtraLight, whatever weight was asked.)
    property list<QtObject> _fonts: [
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-Regular.ttf") },
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-Medium.ttf") },
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-SemiBold.ttf") },
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-Bold.ttf") },
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-ExtraBold.ttf") },
        FontLoader { source: Qt.resolvedUrl("fonts/Nunito-Black.ttf") }
    ]
    readonly property string fontFamily: _fonts[0].status === FontLoader.Ready ? _fonts[0].name : "Fira Sans"
    
    // True while the loaded palette is a light one. Derived from the palette
    // itself rather than read from the GTK preference, so it updates atomically
    // with reloadTheme() and stays correct for any hand-written colors.json.
    readonly property bool isLight: background.hslLightness > 0.5

    // Dynamic color properties
    property color background: "#0e1514"
    property color error: "#ffb4ab"
    property color error_container: "#93000a"
    property color inverse_on_surface: "#2b3231"
    property color inverse_primary: "#006a64"
    property color inverse_surface: "#dde4e2"
    property color on_background: "#dde4e2"
    property color on_error: "#690005"
    property color on_error_container: "#ffdad6"
    property color on_primary: "#003734"
    property color on_primary_container: "#9df2e9"
    property color on_primary_fixed: "#00201e"
    property color on_primary_fixed_variant: "#00504b"
    property color on_secondary: "#1c3532"
    property color on_secondary_container: "#cce8e4"
    property color on_secondary_fixed: "#051f1d"
    property color on_secondary_fixed_variant: "#324b49"
    property color on_surface: "#dde4e2"
    property color on_surface_variant: "#bec9c6"
    property color on_tertiary: "#18324a"
    property color on_tertiary_container: "#cfe5ff"
    property color on_tertiary_fixed: "#001d33"
    property color on_tertiary_fixed_variant: "#304962"
    property color outline: "#899391"
    property color outline_variant: "#3f4947"
    property color primary: "#81d5cd"
    property color primary_container: "#00504b"
    property color primary_fixed: "#9df2e9"
    property color primary_fixed_dim: "#81d5cd"
    property color scrim: "#000000"
    property color secondary: "#b0ccc8"
    property color secondary_container: "#324b49"
    property color secondary_fixed: "#cce8e4"
    property color secondary_fixed_dim: "#b0ccc8"
    property color shadow: "#000000"
    property color source_color: "#458680"
    property color surface: "#0e1514"
    property color surface_bright: "#343a39"
    property color surface_container: "#1a2120"
    property color surface_container_high: "#252b2a"
    property color surface_container_highest: "#303635"
    property color surface_container_low: "#161d1c"
    property color surface_container_lowest: "#090f0f"
    property color surface_dim: "#0e1514"
    property color surface_tint: "#81d5cd"
    property color surface_variant: "#3f4947"
    property color tertiary: "#afc9e7"
    property color tertiary_container: "#304962"
    property color tertiary_fixed: "#cfe5ff"
    property color tertiary_fixed_dim: "#afc9e7"

    // ── HUD colour names (derived from the palette above) ───────────────────
    // Text and icons are tones of the primary colour, never plain black or
    // white: a deep primary in light mode (darker than the accent itself, so
    // it reads on pale plates) and a pale one in dark mode. The fixed tones
    // are the same in both palettes, so these follow the wallpaper's hue at
    // a lightness that keeps them readable.
    readonly property color ink: isLight ? mix(on_primary_fixed_variant, on_primary_fixed, 0.45)   // text and icons
                                         : mix(primary_fixed, on_surface, 0.3)
    readonly property color inkSoft: mix(ink, surface_container, isLight ? 0.3 : 0.28)           // secondary text
    readonly property color blue: primary                   // accent
    readonly property color blueDeep: Qt.darker(primary, 1.25)
    // Text on the accent: a pale primary on the light palette's accent (its
    // on_primary is pure white), the deep one on the dark palette's
    readonly property color accentInk: isLight ? mix(on_primary, primary_fixed, 0.6) : on_primary
    // The level card and the Overview plate: deep primary plates, like the
    // game's navy ones, with pale primary text and a pale tertiary highlight
    readonly property color deepPlate: withAlpha(mix(on_primary_fixed_variant, on_primary_fixed, 0.25), isLight ? 0.94 : 0.9)
    readonly property color deepInk: primary_fixed
    readonly property color deepAccent: primary_fixed_dim
    readonly property color deepHighlight: tertiary_fixed_dim
    readonly property color sky: primary_fixed_dim
    readonly property color yellow: tertiary                // highlight
    readonly property color coral: error
    readonly property color paper: withAlpha(surface_container_low, 0.96)   // windows
    readonly property color mist: surface_container_high    // cards on panels
    readonly property color line: outline_variant           // hairlines
    // HUD plates. Light palettes get more opaque plates: near-white over a
    // pale wallpaper washes out at the transparency that suits dark ones.
    readonly property real plateAlpha: isLight ? 0.95 : 0.86
    readonly property color plate: withAlpha(surface_container, plateAlpha)
    readonly property color plateDark: withAlpha(isLight ? surface_container_high : surface_container_lowest, isLight ? 0.95 : 0.82)
    // A plate flattened into the bar band (compact mode): a light tint
    readonly property color plateFlat: withAlpha(on_surface, isLight ? 0.06 : 0.08)
    // Blend two colours (t = 0: a, 1: b), for morphing between plate styles
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }
    // How far a plate's gradient fades toward its far end
    readonly property real plateFade: isLight ? 0.96 : 0.8

    // Generic accent. Used by widgets that want a distinct highlight separate
    // from `primary` (e.g. the dock's terminal-command mode). Tracks the theme.
    readonly property color accent: tertiary

    // Convenience: return `c` with a custom alpha. Replaces the very common
    // Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, a) boilerplate.
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    property var themeReader: Process {
        id: reader
        command: ["cat", Quickshell.env("HOME") + "/.config/ml4w/colors/colors.json"]
        
        // REQUIRED: Quickshell needs this to parse the binary stream into text
        stdout: StdioCollector {
            onStreamFinished: {
                // "this.text" contains the full output of the cat command
                var output = this.text.trim();
                
                if (output !== "") {
                    try {
                        var newColors = JSON.parse(output);
                        for (var key in newColors) {
                            if (root.hasOwnProperty(key) && key !== "objectName") {
                                root[key] = newColors[key];
                            }
                        }
                        console.log("Theme colors loaded successfully!");
                    } catch (e) {
                        console.log("Failed to parse theme JSON: " + e);
                    }
                }
            }
        }
    }

    function reloadTheme() {
        // Toggle false then true to guarantee Quickshell restarts the cat process
        reader.running = false;
        reader.running = true;
    }

    // Load the JSON colors automatically when Quickshell starts
    // Component.onCompleted: reloadTheme()
}