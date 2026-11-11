import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// The bar's content. It lives inside the screen frame's window (ScreenFrame),
// which draws the bar's background as part of the one frame shape, reserves
// its space and decides where it takes input.
Item {
    id: bar
    // The app drawer lives in ScreenFrame, next to this bar: asking for it
    // here (not over IPC, which reaches one screen's drawer only) opens the
    // one on this bar's screen.
    signal openDock()

    // 0 on a screen without tiled windows (floating lobby HUD), 1 with them
    // (plates shrink into BA Inspired's band). Animated, so the top morphs.
    readonly property bool compact: bar.screen ? Hud.busy(bar.screen.name) : false
    // The lobby's now-playing banner on this screen (set by ScreenFrame). On
    // the lobby the media player grows out of it (and shrinks back into it),
    // as there is no media capsule up here; with tiled windows it drops from
    // the capsule as before.
    property Item lobbyBanner: null
    readonly property bool mediaFromBanner: !compact && lobbyBanner !== null && lobbyBanner.visible
    readonly property bool mediaOpen: mediaPopup.active
    property real compactness: compact ? 1 : 0
    Behavior on compactness { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    // Popups the lobby on this screen asks for
    Connections {
        target: Hud
        function onRequest(s, what, arg) {
            if (!bar.screen || s !== bar.screen.name) return
            if (what === "media") mediaPopup.active = !mediaPopup.active
            else if (what === "notifications") notifPopup.active = !notifPopup.active
            else if (what === "clipboard") clipboardPopup.active = !clipboardPopup.active
            else if (what === "dashboard") dashPopup.active = !dashPopup.active
        }
    }
    property var screen
    width: parent ? parent.width : 0
    height: 40

    // All system data + the command runner now live in the Sys singleton.

    // ── INSTANT OSD HANDLER ──
    function triggerOSD(type, delta) {
        Sys.activeOSD = type
        // The hover drawer under the rings already shows the value
        if (!hoverDrawer.open) {
            osdPopup.active = true
            osdTimer.restart()
        }

        if (delta !== 0) {
            if (type === "vol") {
                let nv = Math.max(0, Math.min(1, Sys.volValue + delta))
                Sys.volValue = nv
                Sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", nv.toFixed(2)])
            } else if (type === "mic") {
                let nv = Math.max(0, Math.min(1, Sys.micValue + delta))
                Sys.micValue = nv
                Sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", nv.toFixed(2)])
            } else if (type === "bri") {
                let nv = Math.max(0, Math.min(1, Sys.briValue + delta))
                Sys.briValue = nv
                let sign = delta > 0 ? "+" : "-"
                Sys.run(["bash", "-c", "brightnessctl s 5%" + sign])
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // UI LAYOUT
    // ══════════════════════════════════════════════════════════════════════════
    // Center pill — media info
    Rectangle {
        id: centerPill
        // HyperBA: on the lobby, now playing lives on its banner; with tiled
        // windows (no lobby) this capsule comes back in the band, right after
        // the level card, fading in with it.
        x: 360
        anchors.top: parent.top; anchors.topMargin: 5
        height: 30; width: Math.min(centerRow.implicitWidth + 52, 300); z: 5
        opacity: bar.compactness
        visible: opacity > 0.01
        scale: centerMouse.pressed ? 0.96 : (centerMouse.containsMouse ? 1.02 : 1.0)
        // BA Inspired: a slanted white capsule (outlined in blue while hot)
        color: "transparent"
        Slanted {
            anchors.fill: parent; z: -1; slant: 10
            fill: Theme.plateFlat
            stroke: mediaPopup.active || centerMouse.containsMouse ? Theme.blue : Theme.line
            strokeWidth: 1
        }
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: centerRow; anchors.centerIn: parent; spacing: 8

            property color _primary: Theme.primary
            property color _tertiary: Theme.tertiary
            property bool isPlaying: Sys.activePlayer && Sys.activePlayer.playbackState === MprisPlaybackState.Playing

            Item {
                width: 26; height: 20
                anchors.verticalCenter: parent.verticalCenter
                Slanted { anchors.fill: parent; slant: 6; fill: centerRow.isPlaying ? Theme.blue : Theme.inkSoft; fill2: Qt.lighter(fill, 1.2) }
                Text { anchors.centerIn: parent; text: "󰎆"; color: Theme.accentInk; font.pixelSize: 12 }
            }
            Text {
                text: { let title = Sys.activePlayer ? (Sys.activePlayer.trackTitle || "No Media") : "No Media"; let artist = Sys.activePlayer ? (Sys.activePlayer.trackArtist || "") : ""; return title + (artist ? " - " + artist : "") }
                color: Theme.ink; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold;
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight; width: Math.min(implicitWidth, 230)
            }
        }
        MouseArea {
            id: centerMouse; anchors.fill: parent; hoverEnabled: true
            onClicked: mediaPopup.active = !mediaPopup.active
            onContainsMouseChanged: hoverDrawer.hoverItem("media", centerPill, containsMouse)
        }
    }

    RowLayout {
        // Anchored to both edges (not just sized to the screen), so the
        // margins apply: the last group sits clear of the right edge.
        anchors.top: parent.top; anchors.topMargin: 7 * (1 - bar.compactness); height: 40
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 0; anchors.rightMargin: 26; spacing: 0

        // ── LEFT: the level card ──
        Row {
            Layout.alignment: Qt.AlignLeft; spacing: 8
            Item { width: 6; height: 1 }

            // Level card, flush with the left screen edge. "Lv." is the CPU
            // load (1 to 100); next to it the workspaces, then a memory bar
            // with its count under it. While the screen has tiled windows it
            // turns compact (the height of the other plates), so they get the
            // room of a regular bar. (Click "Lv.": dashboard; scroll: switch
            // workspace.) Its footprint in the row is the row's height; the
            // full card hangs lower.
            Item {
                id: logoIcon
                readonly property bool compact: bar.compact
                width: lvPlate.width - 16; height: 40
                anchors.verticalCenter: parent.verticalCenter

                Item {
                    id: lvPlate
                    readonly property real slant: logoIcon.compact ? 14 : 24
                    readonly property real stripe: 3
                    readonly property int level: Math.max(1, Math.min(100, Math.round(Sys.cpuUsage * 100)))
                    readonly property real contentX: logoIcon.compact ? 84 : 100
                    // In the band: a 32px plate, 4px from its top
                    x: -16; y: 5 * bar.compactness
                    width: 352
                    height: logoIcon.compact ? 30 : 82
                    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Slanted {
                        anchors.fill: parent
                        leftEdge: false; slant: lvPlate.slant; shadow: true
                        // A deep primary card (the game's navy one), set apart
                        // from the other plates
                        fill: dashPopup.active || lvMouse.containsMouse ? Qt.lighter(Theme.deepPlate, 1.2) : Theme.deepPlate
                        fill2: Theme.withAlpha(Qt.lighter(Theme.deepPlate, 1.25), Theme.deepPlate.a * Theme.plateFade)
                        stroke: Theme.withAlpha(Theme.deepAccent, 0.3); strokeWidth: 1
                    }
                    // Highlight line along the foot (the game's line under the
                    // name), ending short of the slanted edge
                    Rectangle {
                        readonly property real lineY: lvPlate.height - lvPlate.stripe - (logoIcon.compact ? 1 : 4)
                        x: 0; y: lineY
                        width: lvPlate.width - lvPlate.slant * PanelStyle.lean * (lineY + lvPlate.stripe) / lvPlate.height - 14
                        height: lvPlate.stripe; radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.deepHighlight }
                            GradientStop { position: 1; color: Theme.withAlpha(Theme.deepHighlight, 0.3) }
                        }
                    }

                    // Lv. + level (click: dashboard)
                    Item {
                        id: lvBlock
                        x: 18; width: lvPlate.contentX - 30; height: parent.height
                        Text {
                            id: lvTag
                            x: 0; y: logoIcon.compact ? 11 : 12
                            text: "Lv."
                            color: Theme.deepHighlight
                            font.family: Theme.fontFamily; font.pixelSize: logoIcon.compact ? 11 : 15
                            font.weight: Font.Black; font.italic: true
                        }
                        Text {
                            x: logoIcon.compact ? lvTag.width + 3 : 10
                            y: logoIcon.compact ? (parent.height - height) / 2 - 1 : 22
                            text: lvPlate.level
                            color: Theme.deepInk
                            font.family: Theme.fontFamily; font.pixelSize: logoIcon.compact ? 22 : 40
                            font.weight: Font.Black; font.italic: true
                        }
                        MouseArea {
                            id: lvMouse; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashPopup.active = !dashPopup.active
                        }
                    }
                    Rectangle {
                        x: lvPlate.contentX - 10; y: 10
                        width: 1; height: parent.height - 20 - lvPlate.stripe
                        color: Theme.withAlpha(Theme.deepInk, 0.22)
                    }

                    // Workspaces, memory bar, count
                    Item {
                        id: lvContent
                        x: lvPlate.contentX
                        width: lvPlate.width - x - lvPlate.slant - 14
                        height: parent.height

                        Row {
                            id: wsTabs
                            readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0)
                            readonly property real tabW: Math.max(20, Math.min(30, (lvContent.width - (list.length - 1) * 3) / Math.max(1, list.length)))
                            y: logoIcon.compact ? (lvPlate.height - 26) / 2 - 1 : 12
                            spacing: 3
                            Repeater {
                                model: wsTabs.list
                                Item {
                                    id: wsTab
                                    required property var modelData
                                    readonly property bool occupied: Sys.hyprClients.some(c => c.workspace && c.workspace.id === modelData.id)
                                    width: wsTabs.tabW; height: 26
                                    scale: wsTabMouse.pressed ? 0.88 : 1
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Slanted {
                                        anchors.fill: parent; slant: 6
                                        fill: wsTab.modelData.focused ? Theme.deepAccent
                                            : wsTab.modelData.active ? Theme.withAlpha(Theme.deepAccent, 0.28)
                                            : wsTabMouse.containsMouse ? Theme.withAlpha(Theme.deepInk, 0.14) : "transparent"
                                        fill2: wsTab.modelData.focused ? Theme.deepInk : fill
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: wsTab.modelData.name
                                        color: wsTab.modelData.focused ? Theme.on_primary_fixed
                                            : wsTab.occupied || wsTab.modelData.active ? Theme.deepInk : Theme.withAlpha(Theme.deepInk, 0.5)
                                        font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Black
                                    }
                                    MouseArea {
                                        id: wsTabMouse; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Sys.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + wsTab.modelData.name + "\" })"])
                                    }
                                }
                            }
                        }

                        // Memory bar and its count (full card only)
                        Item {
                            visible: opacity > 0
                            opacity: logoIcon.compact ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            y: 46; width: parent.width; height: 26
                            Rectangle {
                                width: parent.width; height: 7; radius: 3.5
                                color: Theme.withAlpha(Theme.deepInk, 0.18)
                                Rectangle {
                                    width: parent.width * (Hud.memTotalGb > 0 ? Hud.memUsedGb / Hud.memTotalGb : Sys.ramUsage)
                                    height: parent.height; radius: 3.5
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: Theme.deepAccent }
                                        GradientStop { position: 1; color: Theme.deepInk }
                                    }
                                    Behavior on width { NumberAnimation { duration: 400 } }
                                }
                            }
                            Text {
                                y: 12
                                text: Hud.memUsedGb.toFixed(1) + " / " + Math.round(Hud.memTotalGb) + " GB"
                                color: Theme.withAlpha(Theme.deepInk, 0.75)
                                font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                            }
                        }
                    }

                    // Scroll anywhere on the card: switch workspace
                    WheelHandler {
                        onWheel: (w) => Sys.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + (w.angleDelta.y > 0 ? "r-1" : "r+1") + "\" })"])
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // ── RIGHT: controls + status ──
        Row {
            Layout.alignment: Qt.AlignRight; spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            // Into the band: 38px plates down to ~31px, anchored at the right
            scale: 1 - 0.21 * bar.compactness   // 38px plates to 30px in the band
            transformOrigin: Item.Right

            // What is running from the corners: recording (click: stop),
            // instant replay (click: save the clip), presenting / keep awake
            // (click: quick settings)
            Row {
                spacing: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: Capture.recording || Capture.replayOn || QuickSettings.presenting || QuickSettings.keepAwake

                Rectangle {
                    visible: Capture.recording
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24; width: recRow.implicitWidth + 18; radius: 12
                    color: Theme.withAlpha(Theme.error, recMouse.containsMouse ? 0.3 : 0.18)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Row {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Theme.error
                            SequentialAnimation on opacity {
                                running: Capture.recording && !Capture.paused
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.25; duration: 700 }
                                NumberAnimation { to: 1; duration: 700 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: recMouse.containsMouse ? "Stop" : Capture.clock(Capture.elapsed)
                            color: Theme.error
                            font.pixelSize: 11; font.bold: true
                        }
                    }
                    MouseArea {
                        id: recMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Capture.stopRecording()
                    }
                }

                Repeater {
                    model: [
                        { show: Capture.replayOn, icon: "󰕧", act: "replay" },
                        { show: QuickSettings.presenting, icon: "󰐨", act: "quick" },
                        { show: QuickSettings.keepAwake && !QuickSettings.presenting, icon: "󰅶", act: "quick" }
                    ]
                    Text {
                        required property var modelData
                        visible: modelData.show
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.icon
                        color: Theme.primary
                        font.pixelSize: 16
                        scale: statusMouse.pressed ? 0.85 : (statusMouse.containsMouse ? 1.15 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                        MouseArea {
                            id: statusMouse
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.act === "replay") Capture.saveReplay()
                                else Corners.toggle("quick", bar.screen ? bar.screen.name : "")
                            }
                        }
                    }
                }
            }

            // Compact Cluster (Mic, Brightness, Volume, Layout), on a plate.
            // (The plate is the wrapper's, not the row's: as a row child it
            // was laid out by the row and sized from it, a layout loop.)
            Item {
                width: clusterRow.width + 44; height: 38
                anchors.verticalCenter: parent.verticalCenter
                Slanted {
                    anchors.fill: parent
                    slant: 10; shadow: bar.compactness < 0.5
                    fill: Theme.mix(Theme.plate, Theme.plateFlat, bar.compactness)
                    stroke: Theme.line; strokeWidth: 1
                }
            Row {
                id: clusterRow
                x: 22
                spacing: 8; anchors.verticalCenter: parent.verticalCenter

                // Mic
                RingControl {
                    id: micRing
                    onHoveredChanged: hoverDrawer.hoverItem("mic", micRing, hovered, 14)
                    property color _primary: Theme.primary
                    property color _error: Theme.error
                    ringColor: Sys.isMicMuted ? _error : _primary
                    value: Sys.micValue
                    icon: Sys.isMicMuted ? "󰍭" : "󰍬"
                    labelText: Sys.isMicMuted ? "Muted" : (Math.round(Sys.micValue * 100) + "%")
                    onClicked: {
                        Sys.isMicMuted = !Sys.isMicMuted
                        Sys.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"])
                    }
                    onScrolled: (delta) => triggerOSD("mic", delta)
                }

                // Brightness
                RingControl {
                    id: briRing
                    onHoveredChanged: hoverDrawer.hoverItem("bri", briRing, hovered, 14)
                    property color _primary: Theme.primary
                    ringColor: _primary
                    value: Sys.briValue
                    icon: Sys.briValue > 0.6 ? "󰃠" : (Sys.briValue > 0.3 ? "󰃟" : "󰃞")
                    labelText: Math.round(Sys.briValue * 100) + "%"
                    onClicked: triggerOSD("bri", 0)
                    onScrolled: (delta) => triggerOSD("bri", delta)
                }

                // Volume
                RingControl {
                    id: volRing
                    onHoveredChanged: hoverDrawer.hoverItem("vol", volRing, hovered, 14)
                    property color _primary: Theme.primary
                    property color _error: Theme.error
                    ringColor: Sys.isMuted ? _error : _primary
                    value: Sys.volValue
                    icon: Sys.isMuted ? "󰝟" : (Sys.volValue > 0.6 ? "󰕾" : (Sys.volValue > 0.2 ? "󰖀" : "󰕿"))
                    labelText: Sys.isMuted ? "Muted" : (Math.round(Sys.volValue * 100) + "%")
                    onClicked: {
                        Sys.isMuted = !Sys.isMuted
                        Sys.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"])
                    }
                    onScrolled: (delta) => triggerOSD("vol", delta)
                }

                Rectangle { width: 1; height: 16; color: Theme.primary; opacity: 0.2; anchors.verticalCenter: parent.verticalCenter }

                // KB Layout
                Item {
                    id: kbContainer
                    height: 28
                    width: 28 + (kbMouse.containsMouse ? kbLabel.implicitWidth + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    scale: kbMouse.pressed ? 0.95 : (kbMouse.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    property color _primary: Theme.primary

                    BarActiveBg { active: keyboardPopup.active; padX: 4; padY: 1 }

                    Item {
                        id: kbIconWrapper
                        width: 28; height: 28
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "󰌌"
                            color: kbContainer._primary
                            font.pixelSize: 16
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        id: kbLabel
                        text: Sys.kbLayout + (Sys.kbVariant !== "" ? " (" + Sys.kbVariant.split(",")[0].substring(0,2) + ")" : "")
                        color: Theme.secondary
                        font.pixelSize: 11
                        font.bold: true
                        anchors.left: kbIconWrapper.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter

                        clip: true
                        opacity: kbMouse.containsMouse ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: kbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: keyboardPopup.active = !keyboardPopup.active
                    }
                }
            }
            }

            // CLOCK
            Item {
                id: clockContainer
                height: 38
                width: clockCap.implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                scale: clockMouse.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                property var time: new Date()
                Timer { interval: 1000; running: true; repeat: true; onTriggered: clockContainer.time = new Date() }

                HudCapsule {
                    id: clockCap
                    flat: bar.compactness
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰥔"
                    tone: Theme.yellow
                    value: Qt.formatDateTime(clockContainer.time, "HH:mm")
                    sub: clockMouse.containsMouse ? "  " + Qt.formatDateTime(clockContainer.time, "ddd d MMM") : ""
                    plus: false
                    hot: calendarPopup.active || clockMouse.containsMouse
                }
                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: calendarPopup.active = !calendarPopup.active
                }
            }

            // COUNTERS: battery (stamina-style), network, bluetooth
            Item {
                id: sysPill
                height: 38; width: sysRow.implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                RowLayout {
                    id: sysRow; anchors.centerIn: parent; spacing: 10
                    HudCapsule {
                        id: sysBatItem
                    flat: bar.compactness
                        Layout.alignment: Qt.AlignVCenter
                        visible: Sys.hasBattery
                        icon: Sys.batCharging ? "󱐋" : "󰂄"
                        tone: Sys.batLevel <= 20 && !Sys.batCharging ? Theme.coral : "#2ec27e"
                        value: String(Sys.batLevel)
                        sub: "/100"
                        fill: Sys.batLevel / 100
                        hot: sysMouse.containsMouse && sysMouse.over(sysBatItem)
                    }
                    HudCapsule {
                        id: sysNetItem
                    flat: bar.compactness
                        Layout.alignment: Qt.AlignVCenter; visible: Sys.connType !== "none"
                        icon: Sys.connType === "ethernet" ? "󰈀" : "󰤨"
                        tone: Theme.blue
                        // Its name only while hovered (keeps the top uncrowded)
                        hot: sysMouse.containsMouse && sysMouse.over(sysNetItem)
                        value: !hot ? "" : Sys.connType === "wifi" && Sys.wifi !== "" ? Sys.wifi : (Sys.connType === "ethernet" ? "Wired" : "Online")
                        maxValueWidth: 150
                    }
                    HudCapsule {
                        id: sysBtItem
                    flat: bar.compactness
                        Layout.alignment: Qt.AlignVCenter; visible: Sys.bluetooth
                        icon: "󰂯"; tone: Theme.tertiary; value: ""; plus: false
                        hot: sysMouse.containsMouse && sysMouse.over(sysBtItem)
                    }
                }
                // One click area: the counter under the pointer picks the
                // system popup's tab (network, bluetooth, performance).
                MouseArea {
                    id: sysMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    function over(item) {
                        if (!item.visible) return false
                        const p = sysMouse.mapToItem(item, sysMouse.mouseX, 0)
                        return p.x >= -5 && p.x <= item.width + 5
                    }
                    function hit(item, x) {
                        if (!item.visible) return false
                        const p = sysMouse.mapToItem(item, x, 0)
                        return p.x >= -5 && p.x <= item.width + 5
                    }
                    function openTab(tab) {
                        if (systemPopup.active && systemPopup.currentTab === tab) systemPopup.active = false
                        else { systemPopup.currentTab = tab; systemPopup.active = true }
                    }
                    onClicked: (mouse) => {
                        if (hit(sysNetItem, mouse.x)) openTab("Network")
                        else if (hit(sysBtItem, mouse.x)) openTab("Bluetooth")
                        else if (hit(sysBatItem, mouse.x)) openTab("Performance")
                        else systemPopup.active = !systemPopup.active
                    }
                }
            }

            // BUTTON GROUP: clipboard / alerts / apps / power on one plate,
            // split by slanted dividers
            Item {
                id: btnGroup
                readonly property real slant: 12
                width: groupRow.implicitWidth + slant * 2 + 16; height: 38
                anchors.verticalCenter: parent.verticalCenter

                Slanted {
                    anchors.fill: parent
                    slant: btnGroup.slant; shadow: bar.compactness < 0.5
                    fill: Theme.mix(Theme.plate, Theme.plateFlat, bar.compactness)
                    stroke: Theme.line; strokeWidth: 1
                }

                component GroupButton: Item {
                    id: gb
                    property string glyph: ""
                    property bool lit: false
                    property bool danger: false
                    property alias mouse: gbMouse
                    signal clicked(var mouse)
                    width: 42; height: 38
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: 6
                        color: gb.lit || gbMouse.containsMouse
                            ? (gb.danger && gbMouse.containsMouse ? Theme.coral : Theme.blue)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: gb.glyph
                        color: gb.lit || gbMouse.containsMouse ? Theme.accentInk : Theme.blue
                        font.pixelSize: 21
                    }
                    scale: gbMouse.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    MouseArea {
                        id: gbMouse; anchors.fill: parent; hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => gb.clicked(m)
                    }
                }
                component Divider: Rectangle {
                    width: 1.5; height: 18; radius: 1
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: 20
                    color: Theme.withAlpha(Theme.blue, 0.35)
                }

                Row {
                    id: groupRow
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 0
                    spacing: 6

                    // Tray icons (when there are any)
                    Row {
                        id: trayRow
                        visible: SystemTray.items.values.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        leftPadding: 6; rightPadding: 6
                    Repeater {
                            model: SystemTray.items.values

                            delegate: Item {
                                id: trayItem
                                required property var modelData
                                width: 19; height: 19
                                anchors.verticalCenter: parent.verticalCenter

                                scale: trayMouse.pressed ? 0.85 : (trayMouse.containsMouse ? 1.15 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                // Tray icons come from the apps themselves (a
                                // themed name or a raw D-Bus pixmap), and the
                                // monochrome ones (nm-applet, Steam...) are
                                // drawn white for a dark panel, so they vanish
                                // on a light plate. A monochrome icon is
                                // redrawn in the accent colour, like the glyphs
                                // next to it, in either palette; a coloured
                                // one (an app logo) is left as it is.
                                Image {
                                    anchors.fill: parent
                                    source: trayItem.modelData.icon
                                    sourceSize.width: 19
                                    sourceSize.height: 19
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    layer.enabled: trayProbe.monochrome
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Theme.blue
                                    }
                                }

                                // Samples the icon once it is loaded to tell
                                // monochrome from coloured. Never shown.
                                Canvas {
                                    id: trayProbe
                                    property bool monochrome: false
                                    property string loaded: ""
                                    readonly property string src: trayItem.modelData.icon
                                    width: 19; height: 19
                                    opacity: 0

                                    function probe() {
                                        if (src === "") { monochrome = false; return }
                                        if (loaded !== "" && loaded !== src) unloadImage(loaded)
                                        loaded = src
                                        if (isImageLoaded(src)) requestPaint()
                                        else loadImage(src)
                                    }
                                    onSrcChanged: probe()
                                    Component.onCompleted: probe()
                                    onImageLoaded: requestPaint()

                                    onPaint: {
                                        if (!isImageLoaded(src)) return
                                        const ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.drawImage(src, 0, 0, width, height)
                                        const px = ctx.getImageData(0, 0, width, height).data
                                        // Average channel spread (max - min)
                                        // over the solid pixels: near zero for
                                        // white, grey or black, high for colour.
                                        let solid = 0, spread = 0
                                        for (let i = 0; i < px.length; i += 4) {
                                            if (px[i + 3] < 128) continue
                                            const r = px[i], g = px[i + 1], b = px[i + 2]
                                            spread += Math.max(r, g, b) - Math.min(r, g, b)
                                            solid++
                                        }
                                        monochrome = solid > 0 && spread / solid < 24
                                    }
                                }

                                MouseArea {
                                    id: trayMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        let item = trayItem.modelData
                                        if (mouse.button === Qt.LeftButton) {
                                            if (item.onlyMenu) {
                                                trayMenu.openFor(trayItem, item)
                                            } else {
                                                item.activate()
                                            }
                                        } else if (mouse.button === Qt.MiddleButton) {
                                            item.secondaryActivate()
                                        } else if (mouse.button === Qt.RightButton) {
                                            if (item.hasMenu) trayMenu.openFor(trayItem, item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Divider { visible: trayRow.visible }
                    GroupButton {
                        id: clipIcon
                        glyph: "󰅌"
                        lit: clipboardPopup.active
                        onClicked: clipboardPopup.active = !clipboardPopup.active
                    }
                    Divider {}
                    GroupButton {
                        id: notifContainer
                        glyph: Notifs.dnd ? "󰂛" : "󰂚"
                        lit: notifPopup.active
                        // Left: notification center, right: Do Not Disturb
                        onClicked: (m) => { if (m.button === Qt.RightButton) Notifs.toggleDnd(); else notifPopup.active = !notifPopup.active }
                        Rectangle {
                            visible: Notifs.count > 0 && !Notifs.dnd
                            x: parent.width - width + 1; y: 2
                            width: Math.max(15, badge.implicitWidth + 7); height: 15; radius: 7.5
                            color: Theme.coral
                            border.color: Theme.plate; border.width: 1.5
                            Text { id: badge; anchors.centerIn: parent; text: Notifs.count > 99 ? "99+" : Notifs.count; color: Theme.on_error; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Black }
                        }
                    }
                    Divider {}
                    GroupButton {
                        id: menuButton
                        glyph: "󰀻"
                        onClicked: bar.openDock()
                    }
                    Divider {}
                    GroupButton {
                        id: powerIcon
                        glyph: "󰐥"
                        danger: true
                        lit: powerPopup.active
                        onClicked: powerPopup.active = !powerPopup.active
                        mouse.onContainsMouseChanged: hoverDrawer.hoverItem("power", powerIcon, powerIcon.mouse.containsMouse)
                    }
                }
            }
        }
    }

    // --- NATIVE WINDOWS ---
    // One shared popout surface for the bar popups: switching between them
    // morphs it instead of closing one window and opening another.
    PopoutHost { id: popoutHost; screen: bar.screen }
    // anchorItem: the bar item each popup grows out of (and is highlighted).
    MediaPopup {
        id: mediaPopup; host: popoutHost
        anchorItem: bar.mediaFromBanner ? bar.lobbyBanner : centerPill
        // "banner": grows out of the lobby's banner; "capsule": drops from the
        // band's media capsule; "center": the lobby without a banner
        placement: bar.mediaFromBanner ? "banner" : bar.compact ? "capsule" : "center"
    }
    SystemPopup { id: systemPopup; host: popoutHost; anchorItem: sysPill }
    CalendarPopup { id: calendarPopup; host: popoutHost; anchorItem: clockContainer }
    ClipboardPopup { id: clipboardPopup; host: popoutHost; anchorItem: clipIcon }
    DashboardPopup { id: dashPopup; host: popoutHost; anchorItem: logoIcon }
    KbLayoutPopup { id: keyboardPopup; host: popoutHost; anchorItem: kbContainer }
    NotificationsPopup { id: notifPopup; host: popoutHost; anchorItem: notifContainer }
    // Quick-controls drawer under the rings, power icon and media pill (on hover)
    // It is drawn in the frame window (the bar's parent), above the bar.
    HoverDrawer { id: hoverDrawer; screen: bar.screen; suppressed: popoutHost.open || powerPopup.active || notifToasts.shown }
    // Notification toasts (the daemon itself is the Notifs singleton)
    // Toasts use the same top-right corner as the popouts: they wait while one is open.
    NotificationToasts { id: notifToasts; screen: bar.screen; suppressed: popoutHost.open }
    PowerPopup { id: powerPopup }

    // ══════════════════════════════════════════════════════════════════════════
    // SYSTEM TRAY MENU (renders SNI DBusMenu with recursive submenus)
    // ══════════════════════════════════════════════════════════════════════════

    Component {
        id: menuEntryComponent

        Column {
            id: entryRoot
            property var entryData
            property int depth: 0
            property bool expanded: false
            width: parent ? parent.width : 200

            QsMenuOpener {
                id: subOpener
                menu: entryRoot.entryData
            }

            property var subItems: {
                try { return subOpener.children ? subOpener.children.values : [] }
                catch(e) { return [] }
            }
            property bool hasChildren: subItems.length > 0

            Item {
                width: parent.width
                height: entryRoot.entryData && entryRoot.entryData.isSeparator ? 9 : 32

                Rectangle {
                    visible: entryRoot.entryData && entryRoot.entryData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - 12 - entryRoot.depth * 14
                    height: 1
                    color: Theme.withAlpha(Theme.primary, 0.15)
                }

                Rectangle {
                    visible: entryRoot.entryData && !entryRoot.entryData.isSeparator
                    anchors.fill: parent
                    anchors.leftMargin: 2; anchors.rightMargin: 2
                    radius: 8
                    color: eMouse.containsMouse
                           ? Theme.withAlpha(Theme.primary, 0.15)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10 + entryRoot.depth * 14
                        anchors.rightMargin: 10
                        spacing: 6

                        Text {
                            text: (entryRoot.entryData ? entryRoot.entryData.text : "") || ""
                            color: Theme.primary
                            opacity: (entryRoot.entryData && entryRoot.entryData.enabled) ? 1.0 : 0.4
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            visible: entryRoot.hasChildren
                            text: entryRoot.expanded ? "󰅃" : "󰅀"
                            color: Theme.primary; opacity: 0.4
                            font.pixelSize: 10
                        }
                    }

                    MouseArea {
                        id: eMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: entryRoot.entryData && entryRoot.entryData.enabled && !entryRoot.entryData.isSeparator
                        onClicked: {
                            if (entryRoot.hasChildren) {
                                entryRoot.expanded = !entryRoot.expanded
                            } else {
                                entryRoot.entryData.triggered()
                                trayMenu.shown = false
                            }
                        }
                    }
                }
            }

            Column {
                visible: entryRoot.expanded && entryRoot.hasChildren
                width: parent.width
                spacing: 0

                Repeater {
                    model: entryRoot.expanded ? entryRoot.subItems : []
                    delegate: Loader {
                        width: parent ? parent.width : 200
                        sourceComponent: menuEntryComponent
                        onLoaded: {
                            item.entryData = modelData
                            item.depth = entryRoot.depth + 1
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: trayMenu
        screen: bar.screen
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        // Stays mapped until the menu has slid back into the bar.
        visible: shown || animating
        WlrLayershell.layer: WlrLayer.Overlay
        // Slides out of the frame on its own: Hyprland's layer animation is off
        // for this namespace (hypr/conf/custom/style.lua), or it slid in twice.
        WlrLayershell.namespace: "quickshell-drawer"
        // Exclusive so Escape key is always captured when menu is open
        WlrLayershell.keyboardFocus: shown ? WlrLayershell.Exclusive : WlrLayershell.None
        exclusionMode: WlrLayershell.Ignore

        property bool shown: false
        property bool animating: false
        onShownChanged: if (shown) animating = true
        property real anchorX: 0

        function openFor(itemUi, item) {
            opener.menu = item.menu
            let pos = itemUi.mapToItem(null, 0, 0)
            anchorX = pos.x + itemUi.width / 2
            shown = true
        }

        Shortcut { sequence: "Escape"; onActivated: trayMenu.shown = false }

        QsMenuOpener { id: opener }

        MouseArea { anchors.fill: parent; onClicked: trayMenu.shown = false }

        // Hangs from the bar under the tray icon, as part of the frame. Kept far
        // enough from the side frames for its curve and the frame's corner.
        FrameDrawer {
            open: trayMenu.shown
            onClosed: trayMenu.animating = false
            hAlign: "free"
            freeX: Math.min(Math.max(52, trayMenu.anchorX - menuBox.width / 2), trayMenu.width - menuBox.width - 52)
            panelWidth: menuBox.width
            panelHeight: menuBox.height
            duration: 300

        Rectangle {
            id: menuBox
            width: 250
            height: Math.min(menuCol.implicitHeight + 16, trayMenu.height - 60)
            radius: 16
            clip: true
            color: "transparent"
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            Flickable {
                anchors.fill: parent; anchors.margins: 8
                clip: true; boundsBehavior: Flickable.StopAtBounds
                contentWidth: width; contentHeight: menuCol.implicitHeight

                Column {
                    id: menuCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: opener.children ? opener.children.values : []
                        delegate: Loader {
                            width: menuCol.width
                            sourceComponent: menuEntryComponent
                            onLoaded: {
                                item.entryData = modelData
                                item.depth = 0
                            }
                        }
                    }
                }
            }
        }
        } // FrameDrawer
    }

    // ══════════════════════════════════════════════════════════════════════════
    // OSD OVERLAY
    // ══════════════════════════════════════════════════════════════════════════
    // A small tab hanging from the bar, 290px from the right as before. The
    // window covers the screen so the drawer's outline can run round the frame,
    // and its empty input mask keeps it from taking any clicks.
    PanelWindow {
        id: osdPopup
        screen: bar.screen
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {}
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Slides out of the frame on its own: Hyprland's layer animation is off
        // for this namespace (hypr/conf/custom/style.lua), or it slid in twice.
        WlrLayershell.namespace: "quickshell-drawer"
        exclusionMode: WlrLayershell.Ignore

        property bool active: false
        property bool isAnimating: false
        visible: active || isAnimating
        onActiveChanged: if(active) isAnimating = true

        FrameDrawer {
            open: osdPopup.active
            onClosed: osdPopup.isAnimating = false
            hAlign: "right"
            hMargin: 290
            panelWidth: 230
            panelHeight: 46
            duration: 300

            Rectangle {
                width: 230; height: 46; radius: 23
                color: "transparent"

                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10

                    property color _primary: Theme.primary
                    property color _error: Theme.error
                    property color activeColor: {
                        if (Sys.activeOSD === "vol" && Sys.isMuted) return _error;
                        if (Sys.activeOSD === "mic" && Sys.isMicMuted) return _error;
                        return _primary;
                    }

                    Text { text: Sys.activeOSD === "vol" ? "󰕾" : (Sys.activeOSD === "mic" ? "󰍬" : "󰃠"); color: parent.activeColor; font.pixelSize: 18 }

                    Rectangle {
                        Layout.fillWidth: true; height: 6; radius: 3; color: Theme.withAlpha(parent.activeColor, 0.2)
                        Rectangle {
                            width: parent.width * (Sys.activeOSD === "vol" ? Sys.volValue : (Sys.activeOSD === "mic" ? Sys.micValue : Sys.briValue))
                            height: parent.height; radius: 3; color: parent.parent.activeColor
                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        text: Math.round((Sys.activeOSD === "vol" ? Sys.volValue : (Sys.activeOSD === "mic" ? Sys.micValue : Sys.briValue)) * 100) + "%"
                        color: parent.activeColor; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 35
                    }
                }
            }
        }
        Timer { id: osdTimer; interval: 2000; onTriggered: osdPopup.active = false }
    }
}
