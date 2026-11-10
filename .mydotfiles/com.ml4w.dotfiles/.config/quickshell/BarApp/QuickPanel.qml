import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components
import qs.SettingsApp.services

// Quick settings, in the bottom-left corner drawer: the toggles that are
// otherwise a script or a keybinding away (keep awake, night light, Do Not
// Disturb, game mode, hotspot, VPN), presentation mode, the power profile
// with the battery's current draw, and the theme (dotswitch).
ColumnLayout {
    id: root
    property string screenName: ""
    property bool shown: false

    spacing: 12

    // Poll only while visible.
    property bool watching: false
    onShownChanged: setWatching(shown)
    Component.onDestruction: setWatching(false)
    function setWatching(on) {
        if (on === watching) return
        watching = on
        armedTheme = ""
        if (on) { QuickSettings.watch(); NM.watch(); Themes.refresh(); vpnOpen = false; chosenSource = QuickSettings.defaultSource() }
        else { QuickSettings.unwatch(); NM.unwatch() }
    }

    function openSettings(page) {
        Corners.closeAll()
        Sys.run(["qs", "ipc", "call", "settings", "openPage", page])
    }

    // ── Header ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: "Quick settings"
                color: Theme.primary
                font.pixelSize: PanelStyle.titleSize; font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: QuickSettings.hasBattery
                    ? Sys.bat + (QuickSettings.charging ? " · charging" : "")
                      + (QuickSettings.watts > 0.05 ? " · " + QuickSettings.watts.toFixed(1) + " W" : "")
                    : "On mains power"
                color: Theme.primary; opacity: PanelStyle.dim
                font.pixelSize: PanelStyle.subtitleSize
                elide: Text.ElideRight
            }
        }
        IconButton {
            icon: "󰒓"; size: 30; iconSize: 15
            onClicked: root.openSettings("network")
        }
    }

    // ── Toggles ─────────────────────────────────────────────────────────────
    readonly property var hotspot: NM.hotspot
    readonly property var activeVpn: NM.vpns.find(c => NM.isUp(c)) || null
    readonly property var busyVpn: NM.vpns.find(c => NM.isBusy(c)) || null
    property bool vpnOpen: false

    function toggleVpn(c) {
        if (NM.isUp(c)) NM.down(c.uuid)
        else NM.up(c.uuid, {}, (ok) => { if (!ok) root.openSettings("network") })
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8; rowSpacing: 8

        QuickTile {
            Layout.fillWidth: true
            icon: "󰅶"; label: "Keep awake"
            active: QuickSettings.keepAwake
            status: active ? "Screen stays on" : "Off"
            onClicked: QuickSettings.keepAwake = !QuickSettings.keepAwake
        }
        QuickTile {
            Layout.fillWidth: true
            icon: "󰖔"; label: "Night light"
            active: QuickSettings.nightLight
            status: active ? "Warmer colours" : "Off"
            onClicked: QuickSettings.toggleNightLight()
        }
        QuickTile {
            Layout.fillWidth: true
            icon: Notifs.dnd ? "󰂛" : "󰂚"; label: "Do not disturb"
            active: Notifs.dnd
            status: active ? "Critical only" : "Off"
            onClicked: Notifs.toggleDnd()
        }
        QuickTile {
            Layout.fillWidth: true
            icon: "󰊴"; label: "Game mode"
            active: QuickSettings.gameMode
            status: active ? "No blur or animations" : "Off"
            onClicked: QuickSettings.toggleGameMode()
        }
        QuickTile {
            Layout.fillWidth: true
            icon: "󰀂"; label: "Hotspot"
            active: NM.hotspotOn
            busy: root.hotspot !== null && NM.isBusy(root.hotspot)
            status: root.hotspot === null ? "Set up in Settings"
                : busy ? "Switching…" : active ? "Sharing Wi-Fi" : "Off"
            onClicked: {
                if (root.hotspot === null) root.openSettings("network")
                else if (NM.hotspotOn) NM.stopHotspot()
                else NM.up(root.hotspot.uuid, { ifname: NM.wifiDevice }, (ok) => { if (!ok) root.openSettings("network") })
            }
        }
        QuickTile {
            Layout.fillWidth: true
            icon: "󰖂"; label: "VPN"
            active: root.activeVpn !== null
            busy: root.busyVpn !== null
            more: NM.vpns.length > 1
            moreOpen: root.vpnOpen
            status: NM.vpns.length === 0 ? "Set up in Settings"
                : busy ? "Switching…"
                : active ? root.activeVpn.name
                : NM.vpns.length === 1 ? NM.vpns[0].name : NM.vpns.length + " connections"
            onClicked: {
                if (NM.vpns.length === 0) root.openSettings("network")
                else if (root.activeVpn) NM.down(root.activeVpn.uuid)
                else if (NM.vpns.length === 1) root.toggleVpn(NM.vpns[0])
                else root.vpnOpen = !root.vpnOpen
            }
            onMoreClicked: root.vpnOpen = !root.vpnOpen
        }
    }

    // Which VPN (when there are several)
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.vpnOpen && NM.vpns.length > 1
        spacing: 4
        Repeater {
            model: NM.vpns
            Rectangle {
                id: vpnRow
                required property var modelData
                readonly property bool up: NM.isUp(modelData)
                readonly property bool busy: NM.isBusy(modelData)
                Layout.fillWidth: true
                implicitHeight: 38
                radius: PanelStyle.radiusControl
                color: vpnMouse.containsMouse ? PanelStyle.cardHover : PanelStyle.cardFill
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 10
                    spacing: 10
                    Text { text: "󰖂"; color: Theme.primary; opacity: vpnRow.up ? 1 : 0.5; font.pixelSize: 15 }
                    Text {
                        Layout.fillWidth: true
                        text: vpnRow.modelData.name
                        color: Theme.primary
                        font.pixelSize: 12; font.bold: vpnRow.up
                        elide: Text.ElideRight
                    }
                    Text {
                        text: vpnRow.busy ? "…" : vpnRow.up ? "Connected" : ""
                        color: Theme.primary; opacity: PanelStyle.dim
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: vpnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleVpn(vpnRow.modelData)
                }
            }
        }
    }

    // ── Presentation ────────────────────────────────────────────────────────
    property string chosenSource: ""
    readonly property var screenNames: Quickshell.screens.map(s => s.name)
    function screenLabel(n) { return n.startsWith("eDP") ? "Laptop" : n }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        QuickTile {
            Layout.fillWidth: true
            icon: "󰐨"; label: "Present"
            active: QuickSettings.presenting
            status: active
                ? (QuickSettings.mirrorSource !== ""
                    ? "Mirroring " + root.screenLabel(QuickSettings.mirrorSource) + " · notifications muted"
                    : "Notifications muted · screen stays on")
                : root.chosenSource !== ""
                    ? "Mirror " + root.screenLabel(root.chosenSource) + ", mute notifications, stay awake"
                    : "Mute notifications and stay awake"
            onClicked: QuickSettings.togglePresentation(root.chosenSource)
        }

        // Which screen the others show (with more than one monitor)
        RowLayout {
            Layout.fillWidth: true
            visible: root.screenNames.length > 1 && !QuickSettings.presenting
            spacing: 6
            Text {
                text: "Mirror"
                color: Theme.primary; opacity: PanelStyle.dim
                font.pixelSize: 11; font.bold: true
                Layout.rightMargin: 2
            }
            Repeater {
                model: root.screenNames
                Chip {
                    required property string modelData
                    text: root.screenLabel(modelData)
                    selected: root.chosenSource === modelData
                    onClicked: root.chosenSource = modelData
                }
            }
            Chip {
                text: "Off"
                selected: root.chosenSource === ""
                onClicked: root.chosenSource = ""
            }
            Item { Layout.fillWidth: true }
        }
    }

    // ── Power profile ───────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: QuickSettings.powerProfile !== ""
        spacing: 8
        SectionLabel { text: "Power profile" }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "power-saver", icon: "󰌪", text: "Saver" },
                    { id: "balanced", icon: "󰾅", text: "Balanced" },
                    { id: "performance", icon: "󱐋", text: "Performance" }
                ]
                Chip {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    icon: modelData.icon; text: modelData.text
                    selected: QuickSettings.powerProfile === modelData.id
                    onClicked: QuickSettings.setPowerProfile(modelData.id)
                }
            }
        }
    }

    // ── Theme ───────────────────────────────────────────────────────────────
    // Pick another theme, confirm, and the whole setup switches (this shell
    // included). Managing themes lives in Settings › Themes.
    property string armedTheme: ""
    readonly property var armed: Themes.theme(armedTheme)
    readonly property var switching: Themes.busy === "switch" ? Themes.theme(Themes.busyTheme) : null

    ColumnLayout {
        Layout.fillWidth: true
        visible: Themes.available && Themes.themes.length > 0
        spacing: 8

        SectionLabel { text: "Theme" }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Themes.themes
                Chip {
                    required property var modelData
                    icon: modelData.active ? "󰄬" : ""
                    text: modelData.name
                    selected: modelData.active
                    enabled: Themes.busy === ""
                    onClicked: if (!modelData.active) root.armedTheme = root.armedTheme === modelData.id ? "" : modelData.id
                }
            }
            Chip {
                icon: Themes.themes.length > 1 ? "󰒓" : "󰐕"
                text: Themes.themes.length > 1 ? "Manage" : "New theme"
                onClicked: root.openSettings("themes")
            }
        }

        // Confirm (switching restarts everything), then progress
        Rectangle {
            Layout.fillWidth: true
            visible: root.armed !== null || root.switching !== null
            implicitHeight: 50
            radius: PanelStyle.radiusCard
            color: Theme.withAlpha(Theme.primary, 0.14)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 8
                spacing: 10
                Text {
                    text: "󰏘"; color: Theme.primary; font.pixelSize: 17
                    SequentialAnimation on opacity {
                        running: root.switching !== null
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.3; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: root.switching ? "Switching to " + root.switching.name + "…"
                            : root.armed ? "Switch to " + root.armed.name + "?" : ""
                        color: Theme.primary
                        font.pixelSize: 12; font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.armed && !root.armed.live ? "Log out and back in afterwards to start it"
                            : "The bar restarts with it. Your data comes along."
                        color: Theme.primary; opacity: PanelStyle.dim
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                Chip {
                    visible: root.switching === null
                    text: "Cancel"
                    onClicked: root.armedTheme = ""
                }
                Chip {
                    visible: root.switching === null
                    icon: "󰁔"; text: "Switch"
                    selected: true
                    onClicked: { const id = root.armedTheme; root.armedTheme = ""; Themes.switchTo(id) }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: Themes.error !== ""
            text: Themes.error
            color: Theme.error
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
