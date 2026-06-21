import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

PanelWindow {
    id: bar
    anchors { top: true; left: true; right: true }
    property var modelData
    screen: modelData

    height: 60
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: WlrLayershell.Exclusive
    exclusiveZone: height - 30
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    // All system data + the command runner now live in the Sys singleton.

    // ── INSTANT OSD HANDLER ──
    function triggerOSD(type, delta) {
        Sys.activeOSD = type
        osdPopup.active = true
        osdTimer.restart()

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
    Rectangle { anchors.top: parent.top; width: parent.width; height: 40; color: Theme.background; opacity: 0.8 }

    // Center pill — media info
    Rectangle {
        id: centerPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 5
        height: 30; width: Math.min(centerRow.implicitWidth + 30, 450); radius: 15; z: 5
        scale: centerMouse.pressed ? 0.96 : (centerMouse.containsMouse ? 1.02 : 1.0)
        color: centerMouse.containsMouse ? Theme.withAlpha(Theme.background, 0.95) : Theme.background
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 200 } }

        Row {
            id: centerRow; anchors.centerIn: parent; spacing: 8

            property color _primary: Theme.primary
            property color _tertiary: Theme.tertiary
            property bool isPlaying: Sys.activePlayer && Sys.activePlayer.playbackState === MprisPlaybackState.Playing

            Text {
                text: "󰎆"
                color: centerRow.isPlaying ? centerRow._tertiary : centerRow._primary
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: { let title = Sys.activePlayer ? (Sys.activePlayer.trackTitle || "No Media") : "No Media"; let artist = Sys.activePlayer ? (Sys.activePlayer.trackArtist || "") : ""; return title + (artist ? " - " + artist : "") }
                color: Theme.primary; font.pixelSize: 14; font.weight: Font.Medium;
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight; width: Math.min(implicitWidth, 350)
            }
        }
        MouseArea { id: centerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: mediaPopup.active = !mediaPopup.active }
    }

    RowLayout {
        anchors.top: parent.top; width: parent.width; height: 40
        anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 0

        // ── LEFT: logo + workspaces + tray ──
        Row {
            Layout.alignment: Qt.AlignLeft; spacing: 8

            // Logo
            Text {
                text: "   󰣇"; color: Theme.primary; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter
                opacity: 1; scale: logoMouse.pressed ? 0.85 : (logoMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: logoMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: dashPopup.active = !dashPopup.active }
            }

            // Workspaces pill
            Rectangle {
                height: 30; width: wsRow.width + 20; radius: 15
                color: Theme.background; anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: wsRow; anchors.centerIn: parent; spacing: 12
                    Repeater {
                        model: Hyprland.workspaces
                        Item {
                            id: wsItem
                            property var wsClients: {
                                let name = modelData.name
                                return Sys.hyprClients.filter(function(c) {
                                    return c.workspace && c.workspace.name === name
                                })
                            }
                            property bool showIcons: wsMouse.containsMouse && wsClients.length > 0

                            width: 16 + (showIcons ? wsIconsRow.implicitWidth + 6 : 0)
                            height: 16
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            scale: wsMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            Text {
                                id: wsText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.active ? "󰮯" : "󰊠"

                                // Make active workspace pop with tertiary color
                                property color _primary: Theme.primary
                                property color _tertiary: Theme.tertiary
                                color: modelData.active ? _tertiary : _primary

                                font.pixelSize: 16; verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Row {
                                id: wsIconsRow
                                anchors.left: wsText.right
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                opacity: wsItem.showIcons ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                Repeater {
                                    model: wsItem.wsClients
                                    delegate: Item {
                                        width: 14; height: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        property string resolvedIcon: {
                                            let cls = modelData.class || ""
                                            if (cls === "") return ""
                                            let candidates = [cls, cls.toLowerCase()]
                                            for (let i = 0; i < candidates.length; i++) {
                                                let p = Quickshell.iconPath(candidates[i], true)
                                                if (p && p.length > 0 && !p.includes("image-missing")) return p
                                            }
                                            return ""
                                        }

                                        Image {
                                            anchors.fill: parent
                                            source: parent.resolvedIcon
                                            sourceSize: Qt.size(14, 14)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            visible: parent.resolvedIcon !== ""
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰣆"
                                            color: Theme.primary
                                            font.pixelSize: 12
                                            visible: parent.resolvedIcon === ""
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: wsMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: Sys.run(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + modelData.name + "\" })"])
                            }
                        }
                    }
                }
            }

            // System tray pill
            Rectangle {
                id: trayPill
                height: 30; width: trayRow.width + 20; radius: 15
                anchors.verticalCenter: parent.verticalCenter
                visible: SystemTray.items.values.length > 0

                // Solid base so the gradient doesn't double-blend with the transparent bar background
                color: Theme.background

                // Gradient overlay using dynamic theme colors
                Rectangle {
                    id: trayGradient
                    anchors.fill: parent
                    radius: 15

                    // Force rigorous bindings to avoid QML gradient theme loss
                    property color gradStart: Theme.withAlpha(Theme.primary, 0.6)
                    property color gradEnd: Theme.withAlpha(Theme.tertiary, 0.6)

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: trayGradient.gradStart }
                        GradientStop { position: 1.0; color: trayGradient.gradEnd }
                    }

                    // Subtle border to frame the gradient nicely
                    border.color: Theme.withAlpha(Theme.primary, 0.3)
                    border.width: 1
                }

                Row {
                    id: trayRow; anchors.centerIn: parent; spacing: 10

                    Repeater {
                        model: SystemTray.items.values

                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            width: 16; height: 16
                            anchors.verticalCenter: parent.verticalCenter

                            scale: trayMouse.pressed ? 0.85 : (trayMouse.containsMouse ? 1.15 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            Image {
                                anchors.fill: parent
                                source: trayItem.modelData.icon
                                sourceSize.width: 16
                                sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                                smooth: true
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
            }
        }

        Item { Layout.fillWidth: true }

        // ── RIGHT: controls + status ──
        Row {
            Layout.alignment: Qt.AlignRight; spacing: 15
            anchors.verticalCenter: parent.verticalCenter

            // Compact Cluster (Mic, Brightness, Volume, Layout)
            Row {
                spacing: 12; anchors.verticalCenter: parent.verticalCenter

                // Mic
                RingControl {
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

            // CLIPBOARD
            Text {
                text: "󰅌"; color: Theme.primary; font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                opacity: 1; scale: clipMouse.pressed ? 0.85 : (clipMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: clipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: clipboardPopup.active = !clipboardPopup.active }
            }

            // NOTIFICATIONS
            Item {
                id: notifContainer
                height: 28
                width: 28 + (notifMouse.containsMouse ? notifLabel.implicitWidth + 6 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                scale: notifMouse.pressed ? 0.85 : (notifMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                property color _primary: Theme.primary
                property color _tertiary: Theme.tertiary
                property color _outline: Theme.outline
                property color activeColor: Sys.swayncState.includes("notification") ? _tertiary : (Sys.swayncState.includes("dnd") ? _outline : _primary)

                Item {
                    id: notifIconWrapper
                    width: 28; height: 28
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: Sys.notificationIcon(Sys.swayncState)
                        color: notifContainer.activeColor
                        font.pixelSize: 18
                        anchors.centerIn: parent
                    }
                }

                Text {
                    id: notifLabel
                    text: Sys.swayncState.includes("dnd") ? "DND" : (Sys.swayncState.includes("notification") ? "New" : "Clear")
                    color: Theme.secondary
                    font.pixelSize: 11; font.bold: true
                    anchors.left: notifIconWrapper.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    opacity: notifMouse.containsMouse ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: notifMouse; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) Sys.run(["swaync-client", "-t", "-sw"])
                        else Sys.run(["swaync-client", "-d", "-sw"])
                    }
                }
            }

            // CLOCK
            Item {
                id: clockContainer
                height: 32
                width: clockCol.implicitWidth + (clockMouse.containsMouse ? dateLabel.implicitWidth + 6 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                opacity: 1; scale: clockMouse.pressed ? 0.95 : (clockMouse.containsMouse ? 1.05 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                property var time: new Date()
                property color _primary: Theme.primary
                Timer { interval: 1000; running: true; repeat: true; onTriggered: clockContainer.time = new Date() }

                Column {
                    id: clockCol
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2
                    Text { text: Qt.formatDateTime(clockContainer.time, "HH:mm"); color: clockContainer._primary; font.pixelSize: 12; font.weight: Font.Black; horizontalAlignment: Text.AlignHCenter }
                    Text { text: Qt.formatDateTime(clockContainer.time, "AP"); color: clockContainer._primary; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter }
                }

                Text {
                    id: dateLabel
                    text: Qt.formatDateTime(clockContainer.time, "ddd, MMM d")
                    color: Theme.secondary
                    font.pixelSize: 11; font.bold: true
                    anchors.left: clockCol.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    opacity: clockMouse.containsMouse ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: clockMouse
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    onClicked: calendarPopup.active = !calendarPopup.active
                }
            }

            // SYSTEM PILL
            Rectangle {
                height: 30; width: sysRow.implicitWidth + 24; radius: 15
                color: sysMouse.containsMouse ? Theme.withAlpha(Theme.background, 0.95) : Theme.background
                anchors.verticalCenter: parent.verticalCenter
                scale: sysMouse.pressed ? 0.96 : (sysMouse.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: 200 } }
                RowLayout {
                    id: sysRow; anchors.centerIn: parent; spacing: 10
                    Row {
                        spacing: 4; Layout.alignment: Qt.AlignVCenter; visible: Sys.connType !== "none"
                        Text { text: Sys.connType === "ethernet" ? "󰈀" : "󰤨"; color: Theme.primary; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                        Text { text: Sys.wifi; color: Theme.secondary; font.pixelSize: 13; font.weight: Font.Bold; visible: Sys.connType === "wifi" && Sys.wifi !== ""; verticalAlignment: Text.AlignVCenter }
                    }
                    Text { text: "󰂯"; color: Theme.secondary; font.pixelSize: 14; visible: Sys.bluetooth; Layout.alignment: Qt.AlignVCenter; verticalAlignment: Text.AlignVCenter }

                    Row {
                        spacing: 4; visible: Sys.hasBattery; Layout.alignment: Qt.AlignVCenter

                        property color _primary: Theme.primary
                        property color _tertiary: Theme.tertiary
                        property color _error: Theme.error
                        property color activeColor: Sys.batCharging ? _tertiary : (Sys.batLevel <= 20 ? _error : _primary)

                        Text { text: Sys.batteryIcon(Sys.batLevel, Sys.batCharging); color: parent.activeColor; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                        Text { text: Sys.bat; color: parent.activeColor; font.pixelSize: 13; font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }
                    }
                }
                MouseArea { id: sysMouse; anchors.fill: parent; hoverEnabled: true; onClicked: systemPopup.active = !systemPopup.active }
            }

            // POWER
            Text {
                text: "󰐥    "; color: Theme.primary; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter
                opacity: 1; scale: powerMouse.pressed ? 0.85 : (powerMouse.containsMouse ? 1.15 : 1.0)
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                MouseArea { id: powerMouse; anchors.fill: parent; hoverEnabled: true; onClicked: powerPopup.active = !powerPopup.active }
            }
        }
    }

    // --- CANVAS CORNERS ---
    Canvas {
        opacity: 0.8; id: leftCorner; x: 10; y: 40; width: 20; height: 20
        renderTarget: Canvas.FramebufferObject
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = Theme.background; ctx.moveTo(0, 0); ctx.lineTo(20, 0); ctx.arcTo(0, 0, 0, 20, 20); ctx.fill() }
    }
    Canvas {
        opacity: 0.8; id: rightCorner; x: parent.width - 30; y: 40; width: 20; height: 20
        renderTarget: Canvas.FramebufferObject
        property color syncColor: Theme.background; onSyncColorChanged: requestPaint()
        onPaint: { var ctx = getContext("2d"); ctx.reset(); ctx.fillStyle = Theme.background; ctx.moveTo(20, 0); ctx.lineTo(0, 0); ctx.arcTo(20, 0, 20, 20, 20); ctx.fill() }
    }

    // --- NATIVE WINDOWS ---
    MediaPopup { id: mediaPopup }
    SystemPopup { id: systemPopup }
    CalendarPopup { id: calendarPopup }
    ClipboardPopup { id: clipboardPopup }
    PowerPopup { id: powerPopup }
    DashboardPopup { id: dashPopup }
    KbLayoutPopup { id: keyboardPopup }

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
        visible: shown
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive so Escape key is always captured when menu is open
        WlrLayershell.keyboardFocus: shown ? WlrLayershell.Exclusive : WlrLayershell.None
        exclusionMode: WlrLayershell.Ignore

        property bool shown: false
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

        Rectangle {
            id: menuBox
            x: Math.min(Math.max(10, trayMenu.anchorX - width / 2), parent.width - width - 10)
            y: 46
            width: 250
            height: Math.min(menuCol.implicitHeight + 16, parent.height - 60)
            radius: 16
            clip: true

            color: Theme.withAlpha(Theme.background, 0.8)
            border.color: Theme.withAlpha(Theme.primary, 0.8)
            border.width: 2

            opacity: trayMenu.shown ? 1.0 : 0.0
            scale: trayMenu.shown ? 1.0 : 0.95
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
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
    }

    // ══════════════════════════════════════════════════════════════════════════
    // OSD OVERLAY
    // ══════════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: osdPopup
        screen: bar.screen
        anchors { top: true; right: true }
        margins { top: 45; right: 290 }
        width: 230; height: 46
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: WlrLayershell.Ignore

        property bool active: false
        property bool isAnimating: false
        visible: active || isAnimating
        onActiveChanged: if(active) isAnimating = true

        Item {
            anchors.fill: parent
            transformOrigin: Item.Top
            opacity: osdPopup.active ? 1.0 : 0.0
            scale: osdPopup.active ? 1.0 : 0.95

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic; onRunningChanged: if(!running && !osdPopup.active) osdPopup.isAnimating = false } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

            Rectangle {
                anchors.fill: parent; radius: 23
                color: Theme.withAlpha(Theme.background, 0.8)
                border.color: Theme.withAlpha(Theme.primary, 0.8); border.width: 2

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
