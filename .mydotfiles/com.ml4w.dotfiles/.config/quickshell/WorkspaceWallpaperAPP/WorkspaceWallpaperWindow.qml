import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects
import "../CustomTheme"

PanelWindow {
    id: root

    // --- WAYLAND CONFIGURATION ---
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore

    implicitWidth: 420
    color: "transparent"

    // --- POSITIONING ---
    anchors {
        left: true
        top: true
        bottom: true
    }

    margins {
        top: 67
        bottom: 0
    }

    // --- CLICK OUTSIDE TO CLOSE ---
    HyprlandFocusGrab {
        windows: [root]
        active: root.isOpen
        onCleared: {
            if (root.isOpen) {
                root.isOpen = false
            }
        }
    }

    // --- ESCAPE KEY LISTENER ---
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.isOpen) {
                root.isOpen = false
            }
        }
    }

    // --- ANIMATION LOGIC ---
    property bool isOpen: false
    visible: isOpen || slideAnim.running

    margins { left: root.currentMargin }
    property real currentMargin: isOpen ? 0 : -root.implicitWidth

    Behavior on currentMargin {
        NumberAnimation {
            id: slideAnim
            duration: 250
            easing.type: Easing.OutQuint
        }
    }

    // --- IPC HANDLER ---
    IpcHandler {
        target: "workspacewallpaper"
        function toggle() { root.isOpen = !root.isOpen }
        function open() { root.isOpen = true }
        function close() { root.isOpen = false }
    }

    // --- CONFIGURATION ---
    property string defaultWallpaperFolder: Quickshell.env("HOME") + "/.config/ml4w/wallpapers"
    property string wallpaperSettingFile: Quickshell.env("HOME") + "/.config/ml4w/settings/wallpaper-folder"
    property string configFile: Quickshell.env("HOME") + "/.config/hypr/conf/custom/workspace-wallpapers.json"

    property string wallpaperFolder: defaultWallpaperFolder
    property int selectedWorkspace: 1
    property var wallpaperConfig: ({})

    Component.onCompleted: {
        root.selectedWorkspace = root.activeWorkspaceId();
    }

    FileView {
        id: wallpaperDirSettingFileHandler
        path: Qt.url(root.wallpaperSettingFile)
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.updateWallpaperFolder(this.text().trim());
        }
        onLoaded: {
            root.updateWallpaperFolder(this.text().trim());
        }
    }

    FileView {
        id: configFileHandler
        path: Qt.url(root.configFile)
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.loadConfig();
        }
        onLoaded: {
            root.loadConfig();
        }
    }

    function updateWallpaperFolder(dirString) {
        const expanded = dirString.replace(/~|\$HOME/g, Quickshell.env("HOME"));
        root.wallpaperFolder = expanded !== "" ? expanded : root.defaultWallpaperFolder;
    }

    function activeWorkspaceId() {
        const id = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
        return Math.max(1, id);
    }

    function loadConfig() {
        const text = configFileHandler.text().trim();
        if (text === "") {
            root.wallpaperConfig = {};
            return;
        }
        try {
            root.wallpaperConfig = JSON.parse(text);
        } catch (e) {
            console.log("Failed to parse workspace wallpaper config: " + e);
            root.wallpaperConfig = {};
        }
    }

    function saveConfig() {
        const json = JSON.stringify(root.wallpaperConfig, null, 2);
        configFileHandler.setText(json + "\n");
    }

    function wallpaperForWorkspace(ws) {
        const path = root.wallpaperConfig[ws.toString()];
        return path || "";
    }

    function setWallpaperForWorkspace(ws, imagePath) {
        if (!imagePath || imagePath === "") return;
        root.wallpaperConfig[ws.toString()] = imagePath;
        root.saveConfig();
        root.applyIfActive(ws);
    }

    function applyIfActive(ws) {
        const activeId = root.activeWorkspaceId();
        if (ws !== activeId) return;

        const scriptPath = Quickshell.env("HOME") + "/.config/hypr/conf/custom/workspace-wallpapers.sh";
        console.log("Applying workspace wallpaper immediately for workspace " + ws);
        Quickshell.execDetached(["bash", "-c", "exec " + scriptPath + " --apply-now"]);
    }

    function basename(path) {
        if (!path || path === "") return "";
        const parts = path.split("/");
        return parts[parts.length - 1];
    }

    Item {
        anchors.fill: parent
        anchors.margins: 20

        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 12

                // --- HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 5
                    spacing: 10

                    Text {
                        text: "Workspace " + root.selectedWorkspace
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        implicitWidth: 28
                        implicitHeight: 28
                        text: "x"
                        font.family: "monospace"
                        font.pixelSize: 18
                        background: Rectangle { color: "transparent" }
                        contentItem: Text {
                            text: parent.text
                            color: Theme.primary
                            font.pixelSize: 18
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: root.isOpen = false
                    }
                }

                // --- WORKSPACE SELECTOR ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: 10

                        Button {
                            property int wsNumber: index + 1

                            Layout.fillWidth: true
                            implicitHeight: 32
                            text: wsNumber
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: root.selectedWorkspace === wsNumber

                            background: Rectangle {
                                color: root.selectedWorkspace === wsNumber ? Theme.primary : "transparent"
                                border.color: Theme.primary
                                border.width: 1
                                radius: 8
                            }

                            contentItem: Text {
                                text: parent.text
                                color: root.selectedWorkspace === wsNumber ? Theme.background : Theme.primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.bold: root.selectedWorkspace === wsNumber
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }

                            onClicked: root.selectedWorkspace = wsNumber
                        }
                    }
                }

                // --- CURRENT ASSIGNMENT ---
                Text {
                    id: currentAssignmentText
                    Layout.fillWidth: true
                    color: Theme.secondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: {
                        const path = root.wallpaperForWorkspace(root.selectedWorkspace);
                        return path !== "" ? "Assigned: " + root.basename(path) : "No wallpaper assigned";
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.primary
                    opacity: 0.3
                }

                // --- SEARCH INPUT ---
                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: "Search image"
                    color: Theme.primary
                    font.pixelSize: 14
                    padding: 8
                    horizontalAlignment: TextInput.AlignHCenter

                    background: Rectangle {
                        anchors.fill: parent
                        color: Theme.background
                        radius: 10
                        border.color: Theme.primary
                        border.width: 1
                    }
                }

                // --- EMPTY DIRECTORY MESSAGE ---
                Text {
                    id: emptyWallpaperDirectoryMsg
                    visible: true

                    Layout.fillWidth: true
                    color: Theme.primary
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Wallpaper folder is either empty or invalid."
                }

                // --- IMAGE GRID ---
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    cacheBuffer: 3000
                    reuseItems: true

                    cellWidth: width / 2
                    cellHeight: cellWidth * 0.80

                    ScrollBar.vertical: ScrollBar {
                        interactive: true
                    }

                    model: FolderListModel {
                        folder: "file://" + root.wallpaperFolder
                        showDirs: false
                        caseSensitive: false
                        sortField: FolderListModel.Name

                        nameFilters: {
                            let s = searchInput.text.trim();
                            if (s === "") {
                                return ["*.jpg", "*.jpeg", "*.png"];
                            }
                            return ["*" + s + "*.jpg", "*" + s + "*.jpeg", "*" + s + "*.png"];
                        }

                        onCountChanged: {
                            emptyWallpaperDirectoryMsg.visible = (count === 0 && this.status === FolderListModel.Ready)
                        }
                    }

                    delegate: Item {
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 8
                            color: Theme.secondary

                            border.color: mouseArea.containsMouse ? Theme.primary : "transparent"
                            border.width: 2
                            radius: 10
                            clip: true

                            Rectangle {
                                id: contentMask
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 8
                                visible: false
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: 2

                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: contentMask
                                }

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    running: thumbnail.status === Image.Loading
                                    opacity: running ? 0.5 : 0.0
                                }

                                Image {
                                    id: thumbnail
                                    anchors.fill: parent
                                    source: "file://" + model.filePath
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 250
                                    sourceSize.height: 250

                                    opacity: status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 350
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    onStatusChanged: {
                                        if (status === Image.Error) {
                                            console.log("Failed to load image at: " + source);
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 22
                                    color: "#aa000000"

                                    Text {
                                        anchors.centerIn: parent
                                        text: model.fileName
                                        color: "white"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        width: parent.width - 8
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    root.setWallpaperForWorkspace(root.selectedWorkspace, model.filePath);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
