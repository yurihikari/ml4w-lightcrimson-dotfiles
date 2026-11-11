import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs.CustomTheme
import qs.BarApp.components
import qs.WallpaperApp
import QtMultimedia

// Per-workspace wallpaper picker (META+SHIFT+E). Slides out of the left frame
// as a frame drawer, like the wallpaper selector.
//
// Assignments live in ~/.config/hypr/conf/custom/workspace-wallpapers.json and
// are applied by workspace-wallpapers.sh (its daemon repaints on workspace
// switches). The picker goes through that script for every change (--assign /
// --clear): it writes the file atomically and applies the wallpaper if that
// workspace is showing. (Writing the JSON here and then asking the script to
// apply raced: the script could read the old file, so nothing changed.)
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    color: "transparent"

    // Covers the screen: the panel is a drawer sliding out of the left frame,
    // and its outline runs round the whole frame.
    anchors { left: true; right: true; top: true; bottom: true }

    // --- CLICK OUTSIDE / ESCAPE TO CLOSE ---
    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen
        onCleared: if (root.isOpen) root.isOpen = false
    }
    Shortcut {
        sequence: "Escape"
        onActivated: if (root.isOpen) root.isOpen = false
    }

    // --- OPEN / CLOSE ---
    property bool isOpen: false
    // Stays mapped until the drawer has slid back into the frame.
    property bool animating: false
    visible: isOpen || animating
    onIsOpenChanged: {
        if (isOpen) {
            animating = true
            // Always start on the workspace you're on.
            selectedWorkspace = activeWorkspaceId()
            searchInput.text = ""
            configFile.reload()
            WallpaperService.refreshPosters()   // thumbnails for newly added videos
        }
    }

    IpcHandler {
        target: "workspacewallpaper"
        function toggle(): void { root.isOpen = !root.isOpen }
        function open(): void { root.isOpen = true }
        function close(): void { root.isOpen = false }
    }

    // --- CONFIGURATION ---
    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultWallpaperFolder: home + "/.config/ml4w/wallpapers"
    readonly property string script: home + "/.config/hypr/conf/custom/workspace-wallpapers.sh"

    property string wallpaperFolder: defaultWallpaperFolder
    property int selectedWorkspace: 1
    property var wallpaperConfig: ({})
    readonly property int workspaceCount: 10

    FileView {
        id: folderSetting
        path: root.home + "/.config/ml4w/settings/wallpaper-folder"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const expanded = text().trim().replace(/~|\$HOME/g, root.home)
            root.wallpaperFolder = expanded !== "" ? expanded : root.defaultWallpaperFolder
        }
    }

    FileView {
        id: configFile
        path: root.home + "/.config/hypr/conf/custom/workspace-wallpapers.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadConfig(text())
        onLoadFailed: root.wallpaperConfig = ({})
    }

    function loadConfig(raw) {
        const t = (raw || "").trim()
        if (t === "") { root.wallpaperConfig = ({}); return }
        try {
            root.wallpaperConfig = JSON.parse(t)
        } catch (e) {
            console.log("Failed to parse workspace wallpaper config: " + e)
            root.wallpaperConfig = ({})
        }
    }

    function activeWorkspaceId() {
        const id = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
        return Math.max(1, Math.min(root.workspaceCount, id))
    }

    function wallpaperFor(ws) {
        return root.wallpaperConfig[ws.toString()] || ""
    }

    function basename(path) {
        if (!path) return ""
        const parts = path.split("/")
        return parts[parts.length - 1]
    }

    // Run the script, then re-read the file (the script replaces it atomically,
    // which a file watch can miss).
    Process {
        id: scriptRun
        onExited: configFile.reload()
    }
    function runScript(args) {
        scriptRun.command = [root.script].concat(args)
        scriptRun.running = true
    }

    function assign(ws, path) {
        if (!path) return
        // Show it straight away; the script's write follows.
        const c = Object.assign({}, root.wallpaperConfig)
        c[ws.toString()] = path
        root.wallpaperConfig = c
        runScript(["--assign", ws.toString(), path])
    }

    function clearAssignment(ws) {
        const c = Object.assign({}, root.wallpaperConfig)
        delete c[ws.toString()]
        root.wallpaperConfig = c
        runScript(["--clear", ws.toString()])
    }

    // A click outside the panel closes it (the window covers the screen).
    MouseArea { anchors.fill: parent; onClicked: root.isOpen = false }

    FrameDrawer {
        open: root.isOpen
        onClosed: root.animating = false
        edge: "left"
        panelWidth: 380
        duration: 300

        Item {
            anchors.fill: parent

            MouseArea { anchors.fill: parent } // Keep clicks on the panel from closing it

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                // --- HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        implicitWidth: 34; implicitHeight: 34; radius: 10
                        color: Theme.withAlpha(Theme.primary, 0.1)
                        Text {
                            anchors.centerIn: parent
                            text: "󰸉"
                            color: Theme.primary
                            font.pixelSize: 17
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Workspace " + root.selectedWorkspace
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Theme.primary
                            opacity: 0.6
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            text: {
                                const p = root.wallpaperFor(root.selectedWorkspace)
                                return p !== "" ? root.basename(p) : "Follows the global wallpaper"
                            }
                        }
                    }

                    // Back to the global wallpaper (only when it has its own)
                    Rectangle {
                        visible: root.wallpaperFor(root.selectedWorkspace) !== ""
                        implicitWidth: resetLabel.implicitWidth + 20; implicitHeight: 28; radius: 9
                        color: Theme.withAlpha(Theme.primary, resetMouse.containsMouse ? 0.16 : 0.08)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: resetLabel
                            anchors.centerIn: parent
                            text: "Follow global"
                            color: Theme.primary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: resetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearAssignment(root.selectedWorkspace)
                        }
                    }
                }

                // --- WORKSPACE SELECTOR ---
                // Filled: selected. Dot: has its own wallpaper. Underline: the
                // workspace you're on.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: root.workspaceCount

                        Rectangle {
                            id: wsButton
                            required property int index
                            readonly property int ws: index + 1
                            readonly property bool selected: root.selectedWorkspace === ws
                            readonly property bool assigned: root.wallpaperFor(ws) !== ""
                            readonly property bool current: (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1) === ws

                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 10
                            color: selected ? Theme.primary
                                 : Theme.withAlpha(Theme.primary, wsMouse.containsMouse ? 0.16 : 0.08)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                text: wsButton.ws
                                color: wsButton.selected ? Theme.background : Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Rectangle {
                                visible: wsButton.assigned
                                width: 4; height: 4; radius: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                color: wsButton.selected ? Theme.background : Theme.primary
                            }
                            Rectangle {
                                visible: wsButton.current
                                height: 2; radius: 1
                                width: parent.width * 0.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: 3
                                color: Theme.primary
                                opacity: 0.7
                            }

                            MouseArea {
                                id: wsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedWorkspace = wsButton.ws
                            }
                        }
                    }
                }

                // --- SEARCH ---
                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    placeholderText: "Search wallpapers"
                    placeholderTextColor: Theme.withAlpha(Theme.primary, 0.45)
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    leftPadding: 14; rightPadding: 14; topPadding: 9; bottomPadding: 9
                    background: Rectangle {
                        radius: 12
                        color: Theme.withAlpha(Theme.primary, searchInput.activeFocus ? 0.12 : 0.08)
                    }
                }

                // --- EMPTY STATE ---
                Text {
                    visible: grid.count === 0 && folderModel.status === FolderListModel.Ready
                    Layout.fillWidth: true
                    Layout.topMargin: 20
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.primary
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    text: searchInput.text.trim() !== ""
                        ? "No wallpaper matches \"" + searchInput.text.trim() + "\""
                        : "No wallpapers in " + root.wallpaperFolder
                }

                // --- IMAGE GRID ---
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cacheBuffer: 3000
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: width / 2
                    cellHeight: cellWidth * 0.78

                    ScrollBar.vertical: ScrollBar { interactive: true }

                    model: FolderListModel {
                        id: folderModel
                        folder: "file://" + root.wallpaperFolder
                        showDirs: false
                        caseSensitive: false
                        sortField: FolderListModel.Name
                        // Images and videos (videos play with mpvpaper on top of awww)
                        nameFilters: {
                            const s = searchInput.text.trim()
                            return WallpaperService.nameFilters(s).concat(s === "" ? ["*.webp"] : ["*" + s + "*.webp"])
                        }
                    }

                    delegate: Item {
                        id: cell
                        required property string filePath
                        required property string fileName
                        readonly property bool assigned: root.wallpaperFor(root.selectedWorkspace) === filePath
                        readonly property bool isVideo: WallpaperService.isVideo(filePath)

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Item {
                            id: card
                            anchors.fill: parent
                            anchors.margins: 6
                            scale: thumbMouse.pressed ? 0.97 : (thumbMouse.containsMouse ? 1.02 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            // Rounded thumbnail
                            ClippingRectangle {
                                id: thumbFrame
                                anchors.fill: parent
                                radius: 12
                                color: Theme.withAlpha(Theme.primary, 0.08)

                                Image {
                                    id: thumbnail
                                    anchors.fill: parent
                                    // Videos show their first frame (cached poster)
                                    source: WallpaperService.thumb(cell.filePath)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 256
                                    sourceSize.height: 256
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }

                                // Live preview: play the video while hovered (one decoder at a time)
                                Loader {
                                    anchors.fill: parent
                                    active: cell.isVideo && thumbMouse.containsMouse && root.isOpen
                                    sourceComponent: Video {
                                        source: "file://" + cell.filePath
                                        autoPlay: true
                                        muted: true
                                        loops: MediaPlayer.Infinite
                                        fillMode: VideoOutput.PreserveAspectCrop
                                    }
                                }

                                // Name strip
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 22
                                    color: Theme.withAlpha(Theme.background, 0.7)
                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 12
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                        text: cell.fileName
                                        color: Theme.primary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            // Hover / assigned ring
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: "transparent"
                                border.width: cell.assigned ? 2 : (thumbMouse.containsMouse ? 1 : 0)
                                border.color: cell.assigned ? Theme.primary : Theme.withAlpha(Theme.primary, 0.6)
                            }

                            // Video badge
                            Rectangle {
                                visible: cell.isVideo
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 6
                                width: 20; height: 20; radius: 10
                                color: Theme.withAlpha(Theme.background, 0.75)
                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 1
                                    text: "▶"
                                    color: Theme.primary
                                    font.pixelSize: 9
                                }
                            }

                            // Assigned badge
                            Rectangle {
                                visible: cell.assigned
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: 20; height: 20; radius: 10
                                color: Theme.primary
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄬"
                                    color: Theme.background
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                id: thumbMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.assign(root.selectedWorkspace, cell.filePath)
                            }
                        }
                    }
                }
            }
        }
    }
}
