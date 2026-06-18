import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.CustomTheme
import qs.SettingsApp.services
import qs.SettingsApp.components
import qs.SettingsApp.pages

// A real, movable application window (xdg-toplevel) — behaves like any other
// app in Hyprland. Left: navigation + search. Right: the selected page.
//
// This window is created/destroyed on demand by SettingsLauncher (via a
// LazyLoader). The IpcHandler lives in the launcher, NOT here, so closing the
// window with the WM (e.g. Super+Q) can never strand the IPC target.
FloatingWindow {
    id: root
    title: "Settings"
    color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)

    implicitWidth: 1060
    implicitHeight: 720

    visible: true

    // Initial page to open on, set by the launcher before creation.
    property string initialPage: "wifi"
    // Emitted when the user asks to close from within the window (Escape).
    signal dismissed()

    property string currentPage: initialPage
    property string query: ""
    readonly property var results: SettingsRegistry.search(query)
    readonly property bool searching: query.trim() !== ""

    function goTo(id) { root.currentPage = id; root.query = ""; searchField.clear() }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.searching) { root.query = ""; searchField.clear() }
            else root.dismissed()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── SIDEBAR ───────────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 264
            Layout.fillHeight: true
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // Title
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 10
                    Rectangle {
                        width: 36; height: 36; radius: 11
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        Text { anchors.centerIn: parent; text: "󰒓"; color: Theme.primary; font.pixelSize: 19 }
                    }
                    Text {
                        text: "Settings"
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.bold: true
                        Layout.fillWidth: true
                    }
                }

                StSearchField {
                    id: searchField
                    onTextChanged: root.query = text
                    onEscaped: { if (text !== "") clear(); else root.visible = false }
                    onAccepted: if (root.results.length > 0) root.goTo(root.results[0].page)
                }

                // ── Navigation list (when not searching) ──
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.searching
                    clip: true
                    contentWidth: width
                    contentHeight: navCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: navCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: SettingsRegistry.pages
                            delegate: StNavItem {
                                required property var modelData
                                icon: modelData.icon
                                label: modelData.title
                                selected: root.currentPage === modelData.id
                                onClicked: root.currentPage = modelData.id
                            }
                        }

                        // Separator before external tools
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            Layout.bottomMargin: 6
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            implicitHeight: 1
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        }

                        // Opens HyprMod (external) instead of switching pages.
                        StNavItem {
                            icon: "󰧨"
                            label: "Hyprland"
                            selected: false
                            onClicked: Quickshell.execDetached(["bash", "-c",
                                "command -v hyprmod >/dev/null 2>&1 && hyprmod || " +
                                "kitty --class dotfiles-floating -e " + Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-install-hyprmod"])
                        }
                    }
                }

                // ── Search results (when searching) ──
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.searching
                    clip: true
                    model: root.results
                    spacing: 4
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    header: Text {
                        text: root.results.length + " result" + (root.results.length === 1 ? "" : "s")
                        color: Theme.primary; opacity: 0.4
                        font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true
                        bottomPadding: 6
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 48
                        radius: 11
                        color: resMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Text { text: modelData.icon; color: Theme.primary; font.pixelSize: 16; Layout.preferredWidth: 20; horizontalAlignment: Text.AlignHCenter }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Text { text: modelData.title; color: Theme.primary; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { visible: modelData.sub !== ""; text: "in " + modelData.sub; color: Theme.primary; opacity: 0.45; font.pixelSize: 10 }
                            }
                            Text { visible: modelData.isPage; text: "Page"; color: Theme.primary; opacity: 0.4; font.pixelSize: 9 }
                        }
                        MouseArea {
                            id: resMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goTo(modelData.page)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.results.length === 0
                        text: "No matching settings"
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                    }
                }
            }
        }

        // Divider
        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) }

        // ── CONTENT ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: stack
                anchors.fill: parent
                anchors.leftMargin: 26
                anchors.rightMargin: 20
                anchors.topMargin: 22
                anchors.bottomMargin: 18
                currentIndex: SettingsRegistry.pageIndex(root.currentPage)

                WifiPage       { active: StackLayout.isCurrentItem && root.visible }
                NetworkPage    { active: StackLayout.isCurrentItem && root.visible }
                FirewallPage   { active: StackLayout.isCurrentItem && root.visible }
                BluetoothPage  { active: StackLayout.isCurrentItem && root.visible }
                DisplaysPage   { active: StackLayout.isCurrentItem && root.visible }
                SoundPage      { active: StackLayout.isCurrentItem && root.visible }
                PowerPage      { active: StackLayout.isCurrentItem && root.visible }
                AppearancePage { active: StackLayout.isCurrentItem && root.visible }
                KeyboardPage   { active: StackLayout.isCurrentItem && root.visible }
                PrintersPage   { active: StackLayout.isCurrentItem && root.visible }
                SystemPage     { active: StackLayout.isCurrentItem && root.visible }
            }
        }
    }
}
