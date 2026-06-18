import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Appearance"
    subheading: "Wallpaper and desktop look"
    icon: "󰸉"

    property bool active: false

    property string defaultFolder: Quickshell.env("HOME") + "/.config/ml4w/wallpapers"
    property string folderSettingFile: Quickshell.env("HOME") + "/.config/ml4w/settings/wallpaper-folder"
    property string transitionFile: Quickshell.env("HOME") + "/.config/ml4w/settings/wallpaper-transition-effect"
    property var transitionEffects: ["simple", "left", "right", "top", "bottom", "center", "any", "random", "none"]

    property string wallpaperFolder: defaultFolder
    property string transitionEffect: "simple"
    property string search: ""

    function expand(p) { return p.replace(/~|\$HOME/g, Quickshell.env("HOME")) }

    FileView {
        id: folderSetting
        path: Qt.url(page.folderSettingFile)
        blockLoading: true
        watchChanges: true
        onLoaded: { let v = text().trim(); if (v !== "") page.wallpaperFolder = page.expand(v) }
        onFileChanged: { reload(); let v = text().trim(); if (v !== "") page.wallpaperFolder = page.expand(v) }
    }

    FileView {
        id: transitionSetting
        path: Qt.url(page.transitionFile)
        blockLoading: true
        watchChanges: true
        onLoaded: { let v = text().trim(); if (page.transitionEffects.indexOf(v) !== -1) page.transitionEffect = v }
        onFileChanged: { reload(); let v = text().trim(); if (page.transitionEffects.indexOf(v) !== -1) page.transitionEffect = v }
    }

    // ── Wallpaper actions ───────────────────────────────────────────────
    StCard {
        title: "Wallpaper"

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            spacing: 8

            StSearchField {
                id: wpSearch
                placeholder: "Search wallpapers…"
                onTextChanged: page.search = text
            }
            StButton {
                text: "Random"; icon: "󰒝"
                onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-wallpaper --random"])
            }
            StButton {
                text: "Effects"; icon: "󰉼"
                onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-wallpaper-effects"])
            }
        }

        // Grid of wallpapers
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 6
            Layout.preferredHeight: 420
            radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
            clip: true

            Text {
                anchors.centerIn: parent
                visible: wpGrid.count === 0
                text: "Wallpaper folder is empty or invalid"
                color: Theme.primary; opacity: 0.4; font.pixelSize: 13
            }

            GridView {
                id: wpGrid
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                cacheBuffer: 2400
                reuseItems: true
                cellWidth: width / 3
                cellHeight: cellWidth * 0.62
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                model: FolderListModel {
                    folder: "file://" + page.wallpaperFolder
                    showDirs: false
                    caseSensitive: false
                    sortField: FolderListModel.Name
                    nameFilters: {
                        let s = page.search.trim()
                        if (s === "") return ["*.jpg", "*.jpeg", "*.png"]
                        return ["*" + s + "*.jpg", "*" + s + "*.jpeg", "*" + s + "*.png"]
                    }
                }

                delegate: Item {
                    required property string filePath
                    required property string fileName
                    width: wpGrid.cellWidth
                    height: wpGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 10
                        color: Theme.surface_container
                        border.color: wpMouse.containsMouse ? Theme.primary : "transparent"
                        border.width: 2
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: "file://" + filePath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 320
                            sourceSize.height: 200
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 2
                            height: 20
                            color: "#aa000000"
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 10
                                text: fileName
                                color: "white"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            id: wpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-wallpaper '" + filePath + "'"])
                        }
                    }
                }
            }
        }
    }

    // ── Wallpaper options ───────────────────────────────────────────────
    StCard {
        title: "Options"

        StRow {
            icon: "󰉼"
            title: "Transition effect"
            subtitle: "Animation used when switching wallpaper"
            StComboBox {
                implicitWidth: 180
                model: page.transitionEffects
                currentIndex: page.transitionEffects.indexOf(page.transitionEffect)
                onActivated: (i) => transitionSetting.setText(page.transitionEffects[i])
            }
        }

        StRow {
            icon: "󰃨"
            title: "Wallpaper folder"
            subtitle: page.wallpaperFolder
            clickable: true
            onClicked: Quickshell.execDetached(["xdg-open", page.wallpaperFolder])
            Text { text: "󰏌"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }

        StRow {
            icon: "󰃢"
            title: "Clear wallpaper cache"
            clickable: true
            onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-clear-wallpaper-cache"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
