import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.CustomTheme
import qs.BarApp.services
import qs.SettingsApp.components

// Themes: switch between complete setups (dotswitch), make new ones, and
// snapshot / restore them. Your data (notes, wallpapers, monitor layout,
// default apps) comes along with every switch.
StPage {
    id: page
    heading: "Themes"
    subheading: "Switch between complete setups. Your notes, wallpapers and screens come with you."
    icon: "󰏘"

    property bool active: false
    onActiveChanged: if (active) Themes.refresh()

    // Two-click confirmation for anything that restarts the shell or removes
    // something: the first click arms the button, the second does it.
    property string armed: ""
    function arm(key) { armed = key; disarm.restart() }
    Timer { id: disarm; interval: 3500; onTriggered: page.armed = "" }

    function closeSettings() { Quickshell.execDetached(["qs", "ipc", "call", "settings", "close"]) }

    readonly property var current: Themes.activeTheme
    readonly property var others: Themes.themes.filter(t => !t.active)

    // ── Not installed ───────────────────────────────────────────────────────
    StCard {
        visible: Themes.loaded && !Themes.available
        StRow {
            icon: "󰀦"
            title: "The theme switcher isn't installed"
            subtitle: "Run install.sh from the dotfiles repository; it installs dotswitch to ~/.local/bin."
        }
    }

    // ── Error from the last action ──────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: Themes.error !== ""
        implicitHeight: errRow.implicitHeight + 20
        radius: 14
        color: Qt.rgba(0.88, 0.42, 0.46, 0.14)
        RowLayout {
            id: errRow
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 8
            spacing: 10
            Text { text: "󰀦"; color: "#e06c75"; font.pixelSize: 16 }
            Text {
                Layout.fillWidth: true
                text: Themes.error
                color: Theme.primary
                font.family: Theme.fontFamily; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            StIconButton { icon: "󰅖"; onClicked: Themes.error = "" }
        }
    }

    // ── Current theme ───────────────────────────────────────────────────────
    StCard {
        title: "Current theme"
        visible: page.current !== null

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            spacing: 16

            ThemePreview {
                theme: page.current
                Layout.preferredWidth: 220
                Layout.preferredHeight: 138
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 4
                Text {
                    text: page.current ? page.current.name : ""
                    color: Theme.primary
                    font.family: Theme.fontFamily; font.pixelSize: 18; font.bold: true
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                Text {
                    text: page.current ? page.current.description : ""
                    visible: text !== ""
                    color: Theme.primary; opacity: 0.6
                    font.family: Theme.fontFamily; font.pixelSize: 12
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
                Text {
                    text: page.current ? page.current.id : ""
                    color: Theme.primary; opacity: 0.35
                    font.family: "monospace"; font.pixelSize: 10
                    Layout.fillWidth: true; elide: Text.ElideMiddle
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 6 }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    StButton {
                        icon: "󰄀"; text: Themes.isBusy("preview") ? "Taking…" : "Update preview"
                        implicitHeight: 32
                        enabled: Themes.busy === ""
                        onClicked: { page.closeSettings(); Themes.updatePreview() }
                    }
                    StButton {
                        icon: "󰆓"; text: Themes.isBusy("save", Themes.active) ? "Saving…" : "Snapshot"
                        implicitHeight: 32
                        enabled: Themes.busy === ""
                        onClicked: Themes.save(Themes.active)
                    }
                    StButton {
                        icon: "󰉋"; text: "Open folder"
                        implicitHeight: 32
                        onClicked: Themes.openFolder(Themes.active)
                    }
                }
            }
        }
    }

    // ── Other themes ────────────────────────────────────────────────────────
    StCard {
        title: "Switch to"
        visible: Themes.available && Themes.loaded

        Text {
            visible: page.others.length === 0
            Layout.fillWidth: true
            Layout.margins: 14
            text: "No other themes yet. Create one below: it starts as a copy of " + (page.current ? page.current.name : "this one") + " that you can change freely."
            color: Theme.primary; opacity: 0.5
            font.family: Theme.fontFamily; font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: page.others
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool switching: Themes.isBusy("switch", modelData.id)
                Layout.fillWidth: true
                implicitHeight: 92
                radius: 12
                color: rowMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.rightMargin: 12
                    spacing: 14

                    ThemePreview {
                        theme: row.modelData
                        Layout.preferredWidth: 122
                        Layout.preferredHeight: 76
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 8
                            Text {
                                text: row.modelData.name
                                color: Theme.primary
                                font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                            }
                            Rectangle {
                                visible: row.modelData.id === Themes.previous
                                implicitWidth: prevLbl.implicitWidth + 12; implicitHeight: 18; radius: 9
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                Text { id: prevLbl; anchors.centerIn: parent; text: "Previous"; color: Theme.primary; opacity: 0.7; font.pixelSize: 9; font.bold: true }
                            }
                        }
                        Text {
                            text: row.modelData.description
                            visible: text !== ""
                            color: Theme.primary; opacity: 0.5
                            font.family: Theme.fontFamily; font.pixelSize: 11
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Text {
                            visible: !row.modelData.live
                            text: "No activate script: log out and back in after switching"
                            color: Theme.primary; opacity: 0.4
                            font.family: Theme.fontFamily; font.pixelSize: 10; font.italic: true
                        }
                    }

                    RowLayout {
                        spacing: 6
                        StIconButton {
                            icon: "󰉋"
                            onClicked: Themes.openFolder(row.modelData.id)
                        }
                        StIconButton {
                            icon: "󰆓"
                            busy: Themes.isBusy("save", row.modelData.id)
                            enabled: Themes.busy === ""
                            onClicked: Themes.save(row.modelData.id)
                        }
                        StButton {
                            readonly property bool sure: page.armed === "rm:" + row.modelData.id
                            icon: "󰆴"; text: sure ? "Remove?" : ""
                            implicitWidth: sure ? implicitHeight + 64 : 32
                            implicitHeight: 32
                            dangerous: true
                            enabled: Themes.busy === ""
                            onClicked: sure ? (page.armed = "", Themes.remove(row.modelData.id)) : page.arm("rm:" + row.modelData.id)
                        }
                        StButton {
                            readonly property bool sure: page.armed === "sw:" + row.modelData.id
                            icon: row.switching ? "󰑓" : "󰁔"
                            text: row.switching ? "Switching…" : sure ? "Switch now" : "Switch"
                            implicitHeight: 32
                            accent: true
                            enabled: Themes.busy === ""
                            onClicked: sure ? (page.armed = "", Themes.switchTo(row.modelData.id)) : page.arm("sw:" + row.modelData.id)
                        }
                    }
                }
            }
        }

        Text {
            visible: page.others.length > 0
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.topMargin: 2
            text: "Switching restarts the bar with the new theme. Removed themes go to the backups, not the bin."
            color: Theme.primary; opacity: 0.4
            font.family: Theme.fontFamily; font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }

    // ── New theme ───────────────────────────────────────────────────────────
    StCard {
        title: "New theme"
        visible: Themes.available && page.current !== null
        StRow {
            icon: "󰐕"
            title: "Start from " + (page.current ? page.current.name : "")
            subtitle: "A full copy you can then change freely: another bar, popups instead of drawers, anything."
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            Layout.topMargin: 0
            spacing: 8
            StField {
                id: newName
                placeholder: "Name, e.g. Popups"
                onAccepted: create.clicked()
            }
            StButton {
                id: create
                icon: "󰐕"; text: Themes.isBusy("new") ? "Creating…" : "Create"
                accent: true
                enabled: Themes.busy === "" && newName.text.trim() !== ""
                onClicked: {
                    if (!enabled) return
                    Themes.create(newName.text.trim(), Themes.active)
                    newName.text = ""
                }
            }
        }
    }

    // ── Snapshots ───────────────────────────────────────────────────────────
    StCard {
        title: "Snapshots"
        visible: Themes.available && Themes.loaded

        Text {
            visible: Themes.snapshots.length === 0
            Layout.fillWidth: true
            Layout.margins: 14
            text: "No snapshots yet. A snapshot saves a whole theme so you can roll it back after an experiment."
            color: Theme.primary; opacity: 0.5
            font.family: Theme.fontFamily; font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: Themes.snapshots.slice(0, 8)
            delegate: StRow {
                id: snap
                required property var modelData
                readonly property bool sure: page.armed === "rs:" + modelData.file
                readonly property bool installed: Themes.theme(modelData.theme) !== null
                icon: "󰁯"
                title: modelData.name + (installed ? "" : " (removed)")
                subtitle: Themes.ago(modelData.time) + " · " + Themes.sizeText(modelData.size)
                StButton {
                    icon: "󰦛"
                    text: Themes.isBusy("restore", snap.modelData.theme) ? "Restoring…" : snap.sure ? "Restore now" : "Restore"
                    implicitHeight: 30
                    enabled: Themes.busy === ""
                    onClicked: snap.sure ? (page.armed = "", Themes.restore(snap.modelData.theme, snap.modelData.file))
                                         : page.arm("rs:" + snap.modelData.file)
                }
            }
        }
        Text {
            visible: Themes.snapshots.length > 0
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.topMargin: 2
            text: "Restoring keeps your current data. The version it replaces is kept in the backups."
            color: Theme.primary; opacity: 0.4
            font.family: Theme.fontFamily; font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }

    // ── Your data ───────────────────────────────────────────────────────────
    StCard {
        title: "Your data"
        visible: Themes.available && Themes.loaded
        StRow {
            icon: "󰆼"
            title: "Comes with you to every theme"
            subtitle: Themes.keepCount + " files and folders: dock notes and todos, wallpapers, monitor and keyboard setup, bookmarks, default apps"
            clickable: true
            onClicked: Themes.editKeepList()
            StButton { text: "Edit list"; icon: "󰏫"; implicitHeight: 30; onClicked: Themes.editKeepList() }
        }
    }

    // A theme's thumbnail: its preview screenshot, or its initial.
    component ThemePreview: ClippingRectangle {
        id: tp
        property var theme: null
        radius: 10
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: tp.theme ? tp.theme.name.charAt(0).toUpperCase() : ""
            color: Theme.primary; opacity: 0.5
            font.family: Theme.fontFamily; font.pixelSize: tp.height * 0.4; font.bold: true
        }
        Image {
            id: img
            anchors.fill: parent
            source: tp.theme && tp.theme.preview ? "file://" + tp.theme.preview + "?" + Themes.previewRev : ""
            sourceSize.width: 440
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
    }
}
