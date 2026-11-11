import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// HyperBA's lobby: the desktop layer of each screen, laid out like a game's
// main menu. It sits above the wallpaper and below the windows, so it shows
// on an empty workspace and windows simply cover it.
//
//   left        shortcuts (alerts, notes, tasks) under the level plate
//   edges       arrows to the previous / next workspace
//   top right   next wallpaper, view mode (hide everything but the wallpaper)
//   right       capture badge
//   bottom left now-playing banner
//   bottom      menu bar (apps, files, terminal, browser, capture, wallpaper,
//               settings, themes) with the clock at its end
//   bottom right the big "Overview" button: a folder behind the menu bar's
//               end and a plate laid over it
//
// Colours come from the theme (matugen), so the lobby follows the wallpaper.
PanelWindow {
    id: lobby

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-lobby"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property string screenName: screen ? screen.name : ""
    // The now-playing banner: the media player grows out of it (MainBar)
    readonly property Item nowPlaying: banner
    // The media player is open on this screen: the banner has turned into it
    property bool mediaOpen: false
    // Only on a screen without tiled windows (they would cover it anyway).
    // The window itself stays mapped: on a busy screen its contents are
    // hidden (not drawn) and it takes no input. Unmapping and remapping it
    // whenever a window moved between screens crashed Qt: a remapped surface
    // gets its scale anew, and Qt tripped walking the lobby's layered items
    // on that scale change (QQuickWindow::physicalDpiChanged).
    readonly property bool active: !Hud.busy(screenName)
    readonly property real margin: 26
    readonly property real topClear: 86          // under the top HUD (level card)
    readonly property real barH: 74              // bottom menu bar plate
    readonly property real overviewW: 270        // the Overview plate, over the bar's right end
    readonly property bool overviewHot: ovCardMouse.containsMouse || ovPlateMouse.containsMouse
    readonly property bool overviewDown: ovCardMouse.pressed || ovPlateMouse.pressed

    // Shown unless in view mode; fades as a whole.
    readonly property bool shown: active && !Hud.viewMode
    property real reveal: shown ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    function run(cmd) { Sys.run(["bash", "-c", cmd]) }
    // A popup on this screen (the bar / drawer of this screen opens it)
    function ask(what, arg) { Hud.request(lobby.screenName, what, arg) }
    function ipc(target, fn, arg) { Sys.run(["qs", "ipc", "call", target, fn].concat(arg !== undefined ? [String(arg)] : [])) }
    function openOverview() { run("qs -p $HOME/.local/share/quickshell-overview ipc call overview toggle") }
    function workspace(rel) { Sys.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + rel + "\" })"]) }

    // Input only where there is something to click; in view mode the whole
    // screen, so a click anywhere on the desktop brings the lobby back.
    // slideNote: a Region follows its item's x/y/width/height only, not its
    // transforms, so the plates slide in by moving x/y; with a Translate the
    // input area stayed where the slide started (the menu bar's icons were
    // left out of it, only their labels took clicks).
    mask: Region {
        Region { item: lobby.active && Hud.viewMode ? fullArea : null }
        Region { item: lobby.active && !Hud.viewMode ? shortcuts : null }
        Region { item: lobby.active && !Hud.viewMode ? leftArrow : null }
        Region { item: lobby.active && !Hud.viewMode ? rightArrow : null }
        Region { item: lobby.active && !Hud.viewMode ? topRight : null }
        Region { item: lobby.active && !Hud.viewMode ? captureBadge : null }
        Region { item: lobby.active && !Hud.viewMode ? banner : null }
        Region { item: lobby.active && !Hud.viewMode ? menuBar : null }
        Region { item: lobby.active && !Hud.viewMode ? ovCard : null }
        Region { item: lobby.active && !Hud.viewMode ? ovPlate : null }
    }
    Item { id: fullArea; anchors.fill: parent }
    MouseArea {
        anchors.fill: parent
        enabled: lobby.active && Hud.viewMode
        onClicked: Hud.viewMode = false
    }

    // ── Components ──────────────────────────────────────────────────────────
    // A drop shadow for plates on the wallpaper
    component PlateShadow: RectangularShadow {
        offset.y: 3; blur: 14; spread: -3
        color: Theme.withAlpha(Theme.shadow, 0.35)
    }

    // An icon tile with a label under it (left shortcuts, menu bar items)
    component IconTile: Item {
        id: tile
        property string icon: ""
        property string label: ""
        property int badge: 0
        property bool dot: false
        property real tileSize: 66
        signal clicked()
        implicitWidth: Math.max(tileSize + 8, lbl.implicitWidth + 6)
        implicitHeight: tileSize + lbl.implicitHeight + 9
        scale: tm.pressed ? 0.92 : (tm.containsMouse ? 1.06 : 1)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        Item {
            id: face
            width: tile.tileSize; height: tile.tileSize
            anchors.horizontalCenter: parent.horizontalCenter
            Slanted {
                anchors.fill: parent; slant: 11; shadow: true
                fill: tm.containsMouse ? Theme.blue : Theme.plate
                fill2: tm.containsMouse ? Qt.lighter(Theme.blue, 1.15) : Theme.plate
                stroke: tm.containsMouse ? "transparent" : Theme.withAlpha(Theme.ink, 0.12)
                strokeWidth: 1
            }
            Text {
                anchors.centerIn: parent
                text: tile.icon
                color: tm.containsMouse ? Theme.accentInk : Theme.blue
                font.pixelSize: tile.tileSize * 0.48
            }
            // Count badge or a plain dot
            Rectangle {
                visible: tile.badge > 0 || tile.dot
                x: parent.width - width / 2 - 6; y: -5
                width: tile.badge > 0 ? Math.max(20, bt.implicitWidth + 10) : 11
                height: tile.badge > 0 ? 20 : 11; radius: height / 2
                color: Theme.coral
                border.color: Theme.paper; border.width: 1.5
                Text {
                    id: bt; anchors.centerIn: parent
                    visible: tile.badge > 0
                    text: tile.badge > 99 ? "99+" : tile.badge
                    color: Theme.on_error
                    font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Black
                }
            }
        }
        Rectangle {
            anchors.centerIn: lbl
            width: lbl.implicitWidth + 16; height: lbl.implicitHeight + 4
            radius: height / 2
            color: Theme.plateDark
        }
        Text {
            id: lbl
            anchors.top: face.bottom; anchors.topMargin: 7
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: Theme.ink
            font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.ExtraBold
        }
        MouseArea {
            id: tm; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    // A small slanted button (top right), like the shortcut tiles
    component SquareButton: Item {
        id: sb
        property string icon: ""
        property string label: ""
        signal clicked()
        width: 70; height: 50
        Text {
            anchors.top: parent.bottom; anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            text: sb.label
            color: Theme.ink
            font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.ExtraBold
            Rectangle {
                anchors.centerIn: parent; z: -1
                width: parent.implicitWidth + 14; height: parent.implicitHeight + 2; radius: height / 2
                color: Theme.plateDark
            }
        }
        scale: sm.pressed ? 0.92 : (sm.containsMouse ? 1.05 : 1)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Slanted {
            anchors.fill: parent; slant: 10; shadow: true
            fill: sm.containsMouse ? Theme.blue : Theme.plate
            fill2: sm.containsMouse ? Qt.lighter(Theme.blue, 1.15) : Theme.plate
            stroke: sm.containsMouse ? "transparent" : Theme.withAlpha(Theme.ink, 0.12)
            strokeWidth: 1
        }
        Text {
            anchors.centerIn: parent
            text: sb.icon
            color: sm.containsMouse ? Theme.accentInk : Theme.blue
            font.pixelSize: 26
        }
        MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.clicked() }
    }

// An arrow on the screen edge
    component EdgeArrow: Item {
        id: ea
        property string glyph: ""
        signal clicked()
        width: 34; height: 64
        opacity: am.containsMouse ? 1 : 0.7
        Text {
            anchors.centerIn: parent
            text: ea.glyph
            color: Theme.ink
            font.pixelSize: 34
            style: Text.Outline; styleColor: Theme.withAlpha(Theme.surface, 0.6)
        }
        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ea.clicked() }
    }

    // ── Everything (fades together) ─────────────────────────────────────────
    Item {
        anchors.fill: parent
        opacity: lobby.reveal
        visible: opacity > 0.01

        // Left shortcuts, under the level plate
        Column {
            id: shortcuts
            x: lobby.margin + (1 - lobby.reveal) * -30   // slides in (see slideNote)
            y: lobby.topClear + 40
            spacing: 20
            Row {
                spacing: 22
                IconTile { icon: "󰂚"; label: "Alerts"; badge: Notifs.count; onClicked: lobby.ask("notifications") }
                IconTile { icon: "󰎚"; label: "Notes"; onClicked: lobby.ask("dock", 1) }
            }
            Row {
                spacing: 22
                IconTile { icon: "󰄲"; label: "Tasks"; onClicked: lobby.ask("dock", 2) }
                IconTile { icon: "󰅌"; label: "Clipboard"; onClicked: lobby.ask("clipboard") }
            }
        }

        // Edge arrows: previous / next workspace
        EdgeArrow { id: leftArrow; x: 6; y: (lobby.height - height) / 2; glyph: "󰅁"; onClicked: lobby.workspace("r-1") }
        EdgeArrow { id: rightArrow; x: lobby.width - width - 6; y: (lobby.height - height) / 2; glyph: "󰅂"; onClicked: lobby.workspace("r+1") }

        // Top right: next wallpaper, view mode
        Row {
            id: topRight
            x: lobby.width - width - lobby.margin
            y: lobby.topClear + 36
            spacing: 14
            SquareButton { icon: "󰑓"; label: "Shuffle"; onClicked: lobby.run("$HOME/.config/ml4w/scripts/ml4w-wallpaper --random") }
            SquareButton { icon: "󰊓"; label: "View"; onClicked: Hud.viewMode = true }
        }

        // Capture badge (round, with a label plate under it)
        Item {
            id: captureBadge
            width: 124; height: 136
            x: lobby.width - width - lobby.margin + 14
            y: topRight.y + topRight.height + 44
            scale: cm.pressed ? 0.93 : (cm.containsMouse ? 1.05 : 1)
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            RectangularShadow { anchors.fill: disc; radius: disc.radius; blur: 16; spread: -2; offset.y: 3; color: Theme.withAlpha(Theme.shadow, 0.4) }
            Rectangle {
                id: disc
                width: 100; height: 100; radius: 50
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.plate
                border.color: Theme.blue; border.width: 3
                Text { anchors.centerIn: parent; text: "󰄀"; color: Theme.blue; font.pixelSize: 42 }
            }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: disc.height - 12
                width: capLbl.implicitWidth + 32; height: 28
                Slanted { anchors.fill: parent; slant: 6; fill: Theme.blue; fill2: Qt.lighter(Theme.blue, 1.15) }
                Text { id: capLbl; anchors.centerIn: parent; text: "Capture"; color: Theme.accentInk; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Black }
            }
            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Corners.open("capture", lobby.screenName, true) }
        }

        // ── Bottom left: now-playing banner ─────────────────────────────────
        Item {
            id: banner
            readonly property var player: Sys.activePlayer
            readonly property bool playing: player && player.playbackState === MprisPlaybackState.Playing
            width: 450; height: 140
            x: lobby.margin + menuBar.slant + (1 - lobby.reveal) * -40   // the bar's top-left corner
            y: menuBar.restY + menuBar.rise - height - 52
            scale: bm.pressed ? 0.98 : 1
            // Hidden while it has turned into the media player (which starts
            // at this exact rectangle, and shrinks back into it on closing)
            opacity: lobby.mediaOpen ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            PlateShadow { anchors.fill: parent; radius: 8 }
            ClippingRectangle {
                anchors.fill: parent; radius: 8
                color: Theme.plate
                border.color: Theme.withAlpha(Theme.ink, 0.1)
                // Album art. Browsers hand MPRIS a tiny copy (Brave: 150x83),
                // which pixelates when stretched over the square. So: large
                // art fills the square (smooth, mipmapped); small art is
                // drawn whole, at most ~1.5x its size, over a blurred copy
                // of itself that fills the square.
                Item {
                    id: artBox
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.height
                    clip: true
                    visible: art.status === Image.Ready

                    readonly property string src: banner.player && banner.player.trackArtUrl ? banner.player.trackArtUrl : ""
                    readonly property real dpr: lobby.screen ? lobby.screen.devicePixelRatio : 1
                    // The art's natural size, from a hidden copy that is never
                    // sized (measuring the shown one fed back into its size)
                    readonly property real natW: artProbe.implicitWidth
                    readonly property real natH: artProbe.implicitHeight
                    // Set a moment after its inputs change, never by a binding:
                    // the pixel ratio changes while Qt walks this window's items
                    // for a scale change (monitors waking up, a new surface),
                    // and flipping lowRes there turned the art's layer and blur
                    // on or off under that walk, which crashed Qt
                    // (QQuickWindow::physicalDpiChanged).
                    property bool lowRes: false
                    function measureLowRes() {
                        lowRes = artProbe.status === Image.Ready
                            && (natW < width * dpr * 0.9 || natH < height * dpr * 0.9)
                    }
                    Timer { id: lowResCheck; interval: 50; onTriggered: artBox.measureLowRes() }
                    onDprChanged: lowResCheck.restart()
                    onNatWChanged: lowResCheck.restart()
                    onNatHChanged: lowResCheck.restart()
                    onWidthChanged: lowResCheck.restart()
                    onHeightChanged: lowResCheck.restart()
                    Image { id: artProbe; visible: false; source: artBox.src; asynchronous: true; cache: false
                        onStatusChanged: lowResCheck.restart() }

                    // Blurred backdrop (small art only)
                    Image {
                        id: artBlurSrc
                        anchors.fill: parent
                        visible: false
                        source: artBox.lowRes ? artBox.src : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        cache: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: artBox.lowRes
                        source: artBlurSrc
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 48
                        saturation: 0.15
                        brightness: Theme.isLight ? 0.05 : -0.12
                    }

                    Image {
                        id: art
                        anchors.centerIn: parent
                        // Large art: fill. Small art: whole, capped at ~1.5x.
                        width: artBox.lowRes ? Math.min(parent.width - 16, artBox.natW / artBox.dpr * 1.5) : parent.width
                        height: artBox.lowRes ? Math.min(parent.height - 16, artBox.natH / artBox.dpr * 1.5) : parent.height
                        source: artBox.src
                        fillMode: artBox.lowRes ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        cache: false
                        layer.enabled: artBox.lowRes
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Theme.withAlpha(Theme.shadow, 0.55)
                            shadowBlur: 0.5
                            shadowVerticalOffset: 2
                            autoPaddingEnabled: true
                        }
                    }
                }
                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.height
                    visible: !artBox.visible
                    color: Theme.withAlpha(Theme.blue, 0.18)
                    Text { anchors.centerIn: parent; text: "󰎆"; color: Theme.blue; font.pixelSize: 44 }
                }
                // Label tab
                Item {
                    x: parent.height + 14; y: 14
                    width: tabLbl.implicitWidth + 26; height: 22
                    Slanted { anchors.fill: parent; slant: 5; fill: banner.playing ? Theme.coral : Theme.blue }
                    Text { id: tabLbl; anchors.centerIn: parent; text: banner.playing ? "NOW PLAYING" : "MUSIC"; color: banner.playing ? Theme.on_error : Theme.accentInk; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Black; font.letterSpacing: 0.6 }
                }
                Column {
                    x: parent.height + 16; y: 44
                    width: parent.width - x - 16
                    spacing: 2
                    Text {
                        width: parent.width
                        text: banner.player ? (banner.player.trackTitle || "Unknown track") : "Nothing playing"
                        color: Theme.ink
                        font.family: Theme.fontFamily; font.pixelSize: 19; font.weight: Font.Black
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: banner.player ? (banner.player.trackArtist || banner.player.identity || "") : "Click to open the player"
                        color: Theme.inkSoft
                        font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                }
                Row {
                    x: parent.height + 14; y: parent.height - height - 12
                    spacing: 6
                    visible: banner.player !== null && banner.player !== undefined
                    Repeater {
                        model: [
                            { g: "󰒮", f: "previous" },
                            { g: banner.playing ? "󰏤" : "󰐊", f: "toggle" },
                            { g: "󰒭", f: "next" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: 40; height: 30; radius: 6
                            color: pm.containsMouse ? Theme.blue : Theme.withAlpha(Theme.ink, 0.08)
                            Text { anchors.centerIn: parent; text: modelData.g; color: pm.containsMouse ? Theme.accentInk : Theme.ink; font.pixelSize: 17 }
                            MouseArea {
                                id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const p = banner.player; if (!p) return
                                    if (modelData.f === "previous") p.previous()
                                    else if (modelData.f === "next") p.next()
                                    else p.togglePlaying()
                                }
                            }
                        }
                    }
                }
            }
            MouseArea { id: bm; anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: lobby.ask("media") }
        }

        // ── Bottom right: Overview ──────────────────────────────────────────
        // Like the game's Campaign button: a folder standing behind the menu
        // bar's end, and a deep plate laid over the bar's end, running to the
        // screen edge (it is declared after the menu bar, to sit on top).
        // The folder: a back panel with its tab, a sheet sticking out, and a
        // front panel. Its foot is hidden behind the bar.
        Item {
            id: ovCard
            width: 220; height: 150
            x: ovPlate.x - 28
            y: menuBar.y + menuBar.rise + 10 - height + (lobby.overviewHot ? -6 : 0)
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            scale: lobby.overviewDown ? 0.97 : 1
            transformOrigin: Item.Bottom
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

            PlateShadow { x: 0; y: 16; width: parent.width; height: parent.height - 16; radius: 10 }
            // Back panel and its tab
            Rectangle { x: 10; y: 0; width: 76; height: 30; radius: 8; color: Theme.blueDeep }
            Rectangle { y: 14; width: parent.width; height: parent.height - 14; radius: 10; color: Theme.blueDeep }
            // A sheet in the folder
            Rectangle {
                x: 16; y: 22; width: parent.width - 30; height: 70; radius: 5
                rotation: -2
                color: Theme.plate
                Column {
                    x: 14; y: 12; spacing: 7
                    Repeater { model: [0.55, 0.4]; Rectangle { required property real modelData; width: ovCard.width * modelData; height: 4; radius: 2; color: Theme.withAlpha(Theme.blue, 0.3) } }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 6
                    text: "󰄰 󰅖 󰐕"
                    color: Theme.withAlpha(Theme.blue, 0.45); font.pixelSize: 11
                }
            }
            // Front panel
            Rectangle {
                id: ovFront
                y: 40; width: parent.width; height: parent.height - 40; radius: 10
                border.color: Theme.withAlpha(Theme.accentInk, 0.35); border.width: 1
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.blue, lobby.overviewHot ? 1.22 : 1.1) }
                    GradientStop { position: 1; color: Theme.blue }
                }
                // Diagonal sheen
                Item {
                    anchors.fill: parent; clip: true
                    Rectangle { x: parent.width * 0.55; y: -60; width: 30; height: 240; rotation: 28; color: Theme.withAlpha(Theme.accentInk, 0.12) }
                    Rectangle { x: parent.width * 0.74; y: -60; width: 10; height: 240; rotation: 28; color: Theme.withAlpha(Theme.accentInk, 0.09) }
                }
                // Icon, in the part above the bar
                Text { x: 46; y: 10; text: "󰕰"; color: Theme.accentInk; font.pixelSize: 44 }
            }
            MouseArea {
                id: ovCardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: lobby.openOverview()
            }
        }

        // ── Bottom menu bar ─────────────────────────────────────────────────
        // A slanted plate across the screen. Its items are big coloured icons
        // that rise out of the plate's top edge, with a bold label under each,
        // and the clock at the end. The item's top `rise` px stand above the
        // plate (and are part of the clickable area).
        Item {
            id: menuBar
            readonly property real slant: 28
            readonly property real rise: 30
            readonly property real plateH: lobby.barH
            // Where it rests once revealed (what the plates above it follow)
            readonly property real restY: lobby.height - height - 14
            x: lobby.margin
            y: restY + (1 - lobby.reveal) * 60
            // Its end runs under the Overview plate
            readonly property real underPlate: 70   // how far its end runs under the plate
            width: lobby.width - lobby.margin - lobby.overviewW + underPlate
            height: plateH + rise

            Item {
                id: plate
                y: menuBar.rise
                width: parent.width; height: menuBar.plateH
                Slanted {
                    anchors.fill: parent
                    slant: menuBar.slant; shadow: true
                    fill: Theme.plate
                    fill2: Theme.withAlpha(Theme.plate, Theme.plateAlpha * Theme.plateFade)
                    stroke: Theme.withAlpha(Theme.ink, 0.1); strokeWidth: 1
                }
                // Accent stripe along the top edge (which starts `slant` in)
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: menuBar.slant + 2; anchors.rightMargin: 2
                    height: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.blue }
                        GradientStop { position: 0.7; color: Theme.withAlpha(Theme.blue, 0.25) }
                        GradientStop { position: 1; color: Theme.withAlpha(Theme.blue, 0) }
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                // Clear of the plate's slanted start and of the Overview plate
                anchors.leftMargin: menuBar.slant * 0.6 + 14
                anchors.rightMargin: menuBar.underPlate + 14
                spacing: 4
                Repeater {
                    model: [
                        { i: "󰀻", l: "Apps", a: () => lobby.ask("dock", 0) },
                        { i: "󰉋", l: "Files", a: () => lobby.run("$(cat $HOME/.config/ml4w/settings/filemanager)") },
                        { i: "󰆍", l: "Terminal", a: () => lobby.run("$HOME/.config/ml4w/settings/terminal.sh") },
                        { i: "󰖟", l: "Browser", a: () => lobby.run("$HOME/.config/ml4w/settings/browser.sh") },
                        { i: "󰂚", l: "Alerts", a: () => lobby.ask("notifications") },
                        { i: "󰸉", l: "Wallpaper", a: () => lobby.ipc("wallpaper", "toggle") },
                        { i: "󰒓", l: "Settings", a: () => lobby.ipc("settings", "toggle") },
                        { i: "󰏘", l: "Themes", a: () => lobby.ipc("settings", "openPage", "themes") }
                    ]
                    Item {
                        id: mi
                        required property var modelData
                        // Evenly spaced, up to a width; what is left goes to
                        // the gap before the clock
                        Layout.preferredWidth: 180
                        Layout.minimumWidth: 90
                        Layout.fillHeight: true

                        // Icon: big, in its own colour, half out of the plate
                        Text {
                            id: miIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: mm.containsMouse ? -4 : 0
                            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            text: mi.modelData.i
                            // One theme colour for every icon (the game uses a
                            // single white + blue set), with a thin outline in
                            // the plate colour so it reads where it rises
                            // above the plate; brighter on hover.
                            color: mm.containsMouse ? Qt.lighter(Theme.blue, Theme.isLight ? 1.15 : 1.12) : Theme.blue
                            style: Text.Outline
                            styleColor: Theme.withAlpha(Theme.surface_container_lowest, 0.85)
                            font.pixelSize: 52
                            scale: mm.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Theme.withAlpha(Theme.shadow, 0.6)
                                shadowBlur: 0.45
                                shadowVerticalOffset: 2
                                autoPaddingEnabled: true
                            }
                        }
                        // Label
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                            text: mi.modelData.l
                            color: mm.containsMouse ? Theme.blue : Theme.ink
                            font.family: Theme.fontFamily; font.pixelSize: 17; font.weight: Font.Black
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mi.modelData.a() }
                    }
                }
                // An airy gap, then the clock at the end, on the plate, with
                // a divider before the Overview plate
                Item { Layout.fillWidth: true; Layout.minimumWidth: 40 }
                Column {
                    Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 10
                    property var now: new Date()
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.now = new Date() }
                    Text { anchors.right: parent.right; text: Qt.formatDateTime(parent.now, "HH:mm"); color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: 24; font.weight: Font.Black }
                    Text { anchors.right: parent.right; text: Qt.formatDateTime(parent.now, "ddd d MMM"); color: Theme.inkSoft; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold }
                }
                Rectangle {
                    Layout.leftMargin: 14
                    Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 14
                    Layout.preferredWidth: 1; Layout.preferredHeight: 38
                    color: Theme.withAlpha(Theme.ink, 0.15)
                }
            }
        }

        // The Overview plate, over the menu bar's end (see ovCard)
        Item {
            id: ovPlate
            width: lobby.overviewW; height: menuBar.plateH + 4
            x: lobby.width - width + (1 - lobby.reveal) * 40
            y: menuBar.y + menuBar.rise - 12      // a little above the bar's top
            Slanted {
                anchors.fill: parent
                rightEdge: false; slant: menuBar.slant; shadow: true
                // Opaque: the bar's end and the folder's foot are under it
                fill: Theme.withAlpha(lobby.overviewHot ? Qt.lighter(Theme.deepPlate, 1.2) : Theme.deepPlate, 1)
                fill2: Theme.withAlpha(Qt.lighter(Theme.deepPlate, 1.25), 1)
                stroke: Theme.withAlpha(Theme.deepAccent, 0.3); strokeWidth: 1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: menuBar.slant * PanelStyle.lean + 26
                text: "Overview"
                color: Theme.deepInk
                font.family: Theme.fontFamily; font.pixelSize: 30; font.weight: Font.Black
            }
            MouseArea {
                id: ovPlateMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: lobby.openOverview()
            }
        }
    }
}
