import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// The notification center (replaces SwayNC's control center), a section of
// the right-hand panel. Same widgets, in the same order, as the former SwayNC
// config: title with "Clear", Do Not Disturb, the buttons grid (Wi-Fi,
// Bluetooth, sound, lock) and the notifications, grouped per app.
//
// Keyboard (as SwayNC): Up/Down select, Return runs the selected
// notification's action, Delete dismisses it, C clears all, D toggles Do Not
// Disturb, Escape closes. Clear and running an action close the center
// (hide-on-clear, hide-on-action).
BarPopup {
    id: root
    ipcTarget: "bar-notifications"

    onActiveChanged: {
        Notifs.centerOpen = active
        if (active) sel = -1
    }

    // Groups whose stack is expanded, by app name
    property var expandedApps: ({})
    function toggleGroup(app) {
        const e = Object.assign({}, expandedApps)
        e[app] = !e[app]
        expandedApps = e
    }

    // Notifications in the order they are shown (for keyboard selection)
    readonly property var shown: {
        const out = []
        for (const g of Notifs.groups) {
            if (g.notifs.length === 1 || expandedApps[g.app] === true) out.push(...g.notifs)
            else out.push(g.notifs[0])
        }
        return out
    }
    property int sel: -1
    readonly property var selNotif: sel >= 0 && sel < shown.length ? shown[sel] : null
    onShownChanged: if (sel >= shown.length) sel = shown.length - 1

    FocusScope {
        anchors.fill: parent
        focus: root.active
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { root.active = false }
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) { root.sel = Math.min(root.sel + 1, root.shown.length - 1) }
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) { root.sel = Math.max(root.sel - 1, 0) }
            else if (e.key === Qt.Key_Home) { root.sel = root.shown.length > 0 ? 0 : -1 }
            else if (e.key === Qt.Key_End) { root.sel = root.shown.length - 1 }
            else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.selNotif) {
                if (Notifs.activate(root.selNotif)) root.active = false
            }
            else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && root.selNotif) { Notifs.dismiss(root.selNotif) }
            else if (e.key === Qt.Key_C) { if (Notifs.count > 0) { Notifs.clearAll(); root.active = false } }
            else if (e.key === Qt.Key_D) { Notifs.toggleDnd() }
            else return
            e.accepted = true
        }
    }

    // A tile of the buttons grid
    component QuickTile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property bool on: false
        property bool toggle: true
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 58
        radius: PanelStyle.radiusCard
        readonly property bool lit: on && toggle
        color: lit ? Theme.withAlpha(Theme.primary, tileMouse.containsMouse ? 0.26 : 0.20)
                   : (tileMouse.containsMouse ? PanelStyle.cardHover : PanelStyle.cardFill)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: tileMouse.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

        Column {
            anchors.centerIn: parent
            spacing: 3
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.icon; color: Theme.primary; font.pixelSize: 18
                opacity: tile.lit || !tile.toggle ? 1.0 : 0.55
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label; color: Theme.primary; font.pixelSize: 10; font.bold: true
                opacity: tile.lit || !tile.toggle ? 0.85 : 0.5
            }
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    PopoutContent {
        open: root.active
        onClosed: root.isAnimating = false
        hAlign: "right"
        hMargin: PanelStyle.rightMargin
        panelWidth: center.width
        panelHeight: center.height

    Item {
        id: center
        width: PanelStyle.narrowWidth; height: PanelStyle.rightHeight
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: PanelStyle.pad; spacing: PanelStyle.gap

            PanelHeader {
                icon: Notifs.dnd ? "󰂛" : "󰂚"
                title: "Notifications"
                subtitle: (Notifs.count === 0 ? "No notifications"
                           : Notifs.count + (Notifs.count === 1 ? " notification" : " notifications"))
                          + (Notifs.dnd ? "  ·  Do not disturb" : "")

                // "Clear" (icon only, so the title fits next to the switcher)
                PanelButton {
                    icon: "󰎟"
                    enabled: Notifs.count > 0
                    onClicked: { Notifs.clearAll(); root.active = false }
                }
                SectionNav { host: root.host; current: root.ipcTarget }
            }

            // ── Do Not Disturb ──────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 54
                radius: PanelStyle.radiusCard
                color: Notifs.dnd ? Theme.withAlpha(Theme.primary, 0.16) : PanelStyle.cardFill
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Notifs.toggleDnd() }

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 12
                    Text { text: "󰂛"; color: Theme.primary; font.pixelSize: 18; opacity: Notifs.dnd ? 1.0 : 0.6 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: "Do not Disturb"; color: Theme.primary; font.pixelSize: 13; font.bold: true }
                        Text {
                            text: Notifs.dnd ? "Only critical notifications pop up" : "Notifications pop up"
                            color: Theme.primary; opacity: PanelStyle.dim; font.pixelSize: 11
                        }
                    }
                    BarToggle { checked: Notifs.dnd; onClicked: Notifs.toggleDnd() }
                }
            }

            // ── Buttons grid ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                QuickTile {
                    icon: Sys.wifiRadio ? "󰤨" : "󰤭"; label: "Wi-Fi"; on: Sys.wifiRadio
                    onClicked: {
                        Sys.run(["bash", "-c", Sys.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"])
                        Sys.wifiRadio = !Sys.wifiRadio
                    }
                }
                QuickTile {
                    icon: Sys.bluetooth ? "󰂯" : "󰂲"; label: "Bluetooth"; on: Sys.bluetooth
                    onClicked: {
                        Sys.run(["bash", "-c", Sys.bluetooth ? "bluetoothctl power off" : "bluetoothctl power on"])
                        Sys.bluetooth = !Sys.bluetooth
                    }
                }
                QuickTile {
                    icon: Sys.isMuted ? "󰝟" : "󰕾"; label: Sys.isMuted ? "Muted" : "Sound"; on: !Sys.isMuted
                    onClicked: {
                        Sys.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
                        Sys.isMuted = !Sys.isMuted
                    }
                }
                QuickTile {
                    icon: "󰌾"; label: "Lock"; toggle: false
                    onClicked: { root.active = false; Sys.run(["hyprlock"]) }
                }
            }

            // ── Notifications ───────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: Notifs.count === 0
                    spacing: 8
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Notifs.dnd ? "󰂛" : "󰂚"
                        color: Theme.primary; opacity: 0.18; font.pixelSize: 54
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No notifications"
                        color: Theme.primary; opacity: 0.45; font.pixelSize: 13
                    }
                }

                ListView {
                    id: groupList
                    anchors.fill: parent
                    clip: true
                    spacing: 10
                    boundsBehavior: Flickable.StopAtBounds
                    model: Notifs.groups
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.primary; opacity: 0.25 }
                    }

                    delegate: ColumnLayout {
                        id: grp
                        required property var modelData
                        readonly property bool multi: modelData.notifs.length > 1
                        readonly property bool expanded: root.expandedApps[modelData.app] === true
                        width: groupList.width
                        spacing: 6

                        // Stack header (an app with several notifications)
                        RowLayout {
                            visible: grp.multi
                            Layout.fillWidth: true
                            Layout.leftMargin: 4
                            spacing: 8
                            Image {
                                Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                source: Notifs.appIconSource(grp.modelData.notifs[0])
                                sourceSize.width: 32; sourceSize.height: 32
                                visible: source != ""
                                asynchronous: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: grp.modelData.app
                                color: Theme.primary; font.pixelSize: 12; font.bold: true
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: Math.max(18, countText.implicitWidth + 10)
                                radius: 9
                                color: Theme.withAlpha(Theme.primary, 0.14)
                                Text {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: grp.modelData.notifs.length
                                    color: Theme.primary; font.pixelSize: 10; font.bold: true
                                }
                            }
                            PanelButton {
                                implicitHeight: 24
                                icon: grp.expanded ? "󰅃" : "󰅀"
                                text: grp.expanded ? "Less" : "More"
                                fontSize: 10
                                onClicked: root.toggleGroup(grp.modelData.app)
                            }
                            PanelButton {
                                implicitHeight: 24
                                icon: "󰅖"
                                fontSize: 10
                                onClicked: Notifs.dismissGroup(grp.modelData.app)
                            }
                        }

                        Repeater {
                            model: grp.multi && !grp.expanded ? [grp.modelData.notifs[0]] : grp.modelData.notifs
                            NotificationCard {
                                required property var modelData
                                Layout.fillWidth: true
                                notif: modelData
                                selected: root.selNotif === modelData
                                onActionInvoked: root.active = false   // hide-on-action
                            }
                        }
                    }
                }
            }
        }
    }
    } // PopoutContent
}
