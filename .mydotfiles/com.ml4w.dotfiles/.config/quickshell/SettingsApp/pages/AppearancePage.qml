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

    // ── Per-workspace wallpapers ─────────────────────────────────────────
    property string wsConfigFile: Quickshell.env("HOME") + "/.config/hypr/conf/custom/workspace-wallpapers.json"
    property string wsScript: Quickshell.env("HOME") + "/.config/hypr/conf/custom/workspace-wallpapers.sh"
    property int workspaceCount: 10
    property int wsTarget: 1            // which workspace the picker below assigns to
    property var wsConfig: ({})         // { "1": "/path", ... }
    property string wsSearch: ""

    function wsAssignment(n) {
        var v = page.wsConfig[String(n)]
        return v ? v : ""
    }
    function baseName(p) {
        if (!p) return ""
        var parts = String(p).split("/")
        return parts[parts.length - 1]
    }

    // Light / Dark mode: current state + matugen preview palettes for both
    // modes (computed from the current wallpaper, applied only on click).
    property bool isDark: true
    property var modeColors: ({ "dark": ({}), "light": ({}) })
    property bool modeLoaded: false

    onActiveChanged: if (active) matugenPreview.running = true

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

    // Tracks the ml4w dark/light setting (1 = dark) written by ml4w-toggle-theme.
    FileView {
        id: darkmodeSetting
        path: Qt.url(Quickshell.env("HOME") + "/.config/ml4w/settings/darkmode")
        blockLoading: true
        watchChanges: true
        onLoaded: page.isDark = (text().trim() === "1")
        onFileChanged: { reload(); page.isDark = (text().trim() === "1") }
    }

    // The previews depend on the wallpaper — re-render when it changes.
    FileView {
        id: wallpaperCache
        path: Qt.url(Quickshell.env("HOME") + "/.cache/ml4w/hyprland-dotfiles/current_wallpaper")
        blockLoading: true
        watchChanges: true
        onFileChanged: { reload(); if (page.active) matugenPreview.running = true }
    }

    // Per-workspace wallpaper assignments (written by the daemon / picker).
    FileView {
        id: wsConfigView
        path: Qt.url(page.wsConfigFile)
        blockLoading: true
        watchChanges: true
        function parseConfig() {
            var t = text().trim()
            if (t === "") { page.wsConfig = ({}); return }
            try { page.wsConfig = JSON.parse(t) }
            catch (e) { console.log("workspace-wallpapers.json parse error:", e); page.wsConfig = ({}) }
        }
        onLoaded: parseConfig()
        onFileChanged: { reload(); parseConfig() }
    }

    // Emulates matugen for the current wallpaper WITHOUT touching the real
    // colors.json (--dry-run). A single call returns both palettes, so we can
    // preview light and dark side by side. Nothing is applied until you click.
    Process {
        id: matugenPreview
        command: ["bash", "-c",
            "WP=$(cat \"$HOME/.cache/ml4w/hyprland-dotfiles/current_wallpaper\" 2>/dev/null); " +
            "[ -z \"$WP\" ] && exit 0; " +
            "MG=matugen; " +
            "[ -x \"$HOME/.cargo/bin/matugen\" ] && MG=\"$HOME/.cargo/bin/matugen\"; " +
            "[ -x \"$HOME/.local/bin/matugen\" ] && MG=\"$HOME/.local/bin/matugen\"; " +
            "\"$MG\" image \"$WP\" --source-color-index 0 -j hex --dry-run 2>/dev/null"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(text)
                    if (!j.colors) return
                    var roles = ["background", "surface_container", "surface_container_high",
                                 "on_surface", "primary", "on_primary", "secondary_container"]
                    var out = { "dark": ({}), "light": ({}) }
                    for (var i = 0; i < roles.length; i++) {
                        var r = roles[i]
                        if (j.colors[r]) {
                            out.dark[r]  = j.colors[r].dark.color
                            out.light[r] = j.colors[r].light.color
                        }
                    }
                    page.modeColors = out
                    page.modeLoaded = true
                } catch (e) { console.log("matugen preview parse error:", e) }
            }
        }
    }

    // ── Reusable mode preview card (mini mock of the desktop in that mode) ──
    component ModePreview: Rectangle {
        id: mp
        property var colors: ({})
        property string label: ""
        property bool selected: false
        signal clicked()

        // role → color; pass an alpha to get a translucent variant. Falls back
        // to grey until matugen has produced the palette.
        function rc(role, a) {
            var h = (colors && colors[role]) ? colors[role] : "#888888"
            if (a === undefined) return h
            var r = parseInt(h.substr(1, 2), 16) / 255
            var g = parseInt(h.substr(3, 2), 16) / 255
            var b = parseInt(h.substr(5, 2), 16) / 255
            return Qt.rgba(r, g, b, a)
        }

        Layout.fillWidth: true
        implicitHeight: 150
        radius: 16
        color: rc("background")
        border.color: selected ? rc("primary") : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
        border.width: selected ? 3 : 1
        scale: mpMouse.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 200 } }

        // ── mock window content ──
        Item {
            anchors.fill: parent
            anchors.margins: 16
            anchors.bottomMargin: 30

            Rectangle {
                id: avatar
                width: 26; height: 26; radius: 13
                anchors.top: parent.top; anchors.left: parent.left
                color: mp.rc("surface_container_high")
            }
            Column {
                anchors.left: avatar.right; anchors.leftMargin: 10
                anchors.verticalCenter: avatar.verticalCenter
                spacing: 6
                Rectangle { width: 120; height: 7; radius: 3.5; color: mp.rc("on_surface", 0.75) }
                Rectangle { width: 78;  height: 6; radius: 3;   color: mp.rc("on_surface", 0.35) }
            }

            // wavy accent line — painted once, no animation
            Canvas {
                id: wave
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: avatar.bottom; anchors.topMargin: 12
                height: 14
                property color stroke: mp.rc("primary")
                onStrokeChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var w = width, midY = height / 2, amp = 4, k = 2 * Math.PI / 26
                    ctx.beginPath()
                    for (var x = 0; x <= w; x += 2) {
                        var y = midY + amp * Math.sin(k * x)
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.strokeStyle = stroke; ctx.lineWidth = 2.5
                    ctx.lineJoin = "round"; ctx.lineCap = "round"; ctx.stroke()
                }
            }

            // three pills; the first carries the accent + selected check
            Row {
                anchors.bottom: parent.bottom; anchors.left: parent.left
                spacing: 6
                Rectangle {
                    width: 52; height: 22; radius: 11
                    color: mp.selected ? mp.rc("primary") : mp.rc("surface_container_high")
                    Text {
                        anchors.centerIn: parent; visible: mp.selected
                        text: "󰄬"; color: mp.rc("on_primary"); font.pixelSize: 12
                    }
                }
                Rectangle { width: 44; height: 22; radius: 11; color: mp.rc("secondary_container") }
                Rectangle { width: 44; height: 22; radius: 11; color: mp.rc("secondary_container") }
            }
        }

        // footer label
        Text {
            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: mp.label
            color: mp.selected ? mp.rc("primary") : mp.rc("on_surface", 0.6)
            font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: mp.selected
        }

        MouseArea {
            id: mpMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mp.clicked()
        }
    }

    // ── Theme mode ──────────────────────────────────────────────────────
    StCard {
        title: "Mode"

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            spacing: 12

            ModePreview {
                colors: page.modeColors.light
                label: "Light"
                selected: !page.isDark
                // ml4w-toggle-theme is a pure toggle, so only act when switching.
                onClicked: if (page.isDark) Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-toggle-theme"])
            }
            ModePreview {
                colors: page.modeColors.dark
                label: "Dark"
                selected: page.isDark
                onClicked: if (!page.isDark) Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-toggle-theme"])
            }
        }
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

    // ── Per-workspace wallpapers ────────────────────────────────────────
    StCard {
        title: "Per-workspace wallpapers"

        // What this does / doesn't do.
        StRow {
            icon: "󰋩"
            title: "Wallpaper only — theme stays the same"
            subtitle: "Each workspace can show its own wallpaper. This does not change "
                    + "the colour theme. To recolour the desktop, set a global wallpaper "
                    + "from the Wallpaper section above (that also applies to this workspace)."
        }

        // Target workspace selector (number chips; dot = has an assignment).
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.topMargin: 4
            text: "TARGET WORKSPACE"
            color: Theme.primary
            opacity: 0.45
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            spacing: 6
            Repeater {
                model: page.workspaceCount
                delegate: Rectangle {
                    required property int index
                    readonly property int ws: index + 1
                    readonly property bool sel: page.wsTarget === ws
                    width: 34; height: 34; radius: 9
                    color: sel ? Theme.primary
                         : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                    Behavior on color { ColorAnimation { duration: 130 } }

                    Text {
                        anchors.centerIn: parent
                        text: ws
                        color: sel ? Theme.background : Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: sel
                    }
                    Rectangle {
                        visible: page.wsAssignment(ws) !== ""
                        width: 6; height: 6; radius: 3
                        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4
                        color: sel ? Theme.background : Theme.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.wsTarget = ws
                    }
                }
            }
        }

        // Current assignment + clear.
        StRow {
            icon: "󰋩"
            title: "Workspace " + page.wsTarget
            subtitle: page.wsAssignment(page.wsTarget) !== ""
                      ? page.baseName(page.wsAssignment(page.wsTarget))
                      : "Using the global wallpaper"
            StButton {
                text: "Clear"
                icon: "󰜺"
                dangerous: true
                enabled: page.wsAssignment(page.wsTarget) !== ""
                onClicked: Quickshell.execDetached(["bash", "-c",
                    page.wsScript + " --clear " + page.wsTarget])
            }
        }

        StSearchField {
            id: wsSearchField
            placeholder: "Search wallpapers…"
            onTextChanged: page.wsSearch = text
        }

        // Grid — clicking assigns to the target workspace.
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 6
            Layout.preferredHeight: 320
            radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
            clip: true

            Text {
                anchors.centerIn: parent
                visible: wsGrid.count === 0
                text: "Wallpaper folder is empty or invalid"
                color: Theme.primary; opacity: 0.4; font.pixelSize: 13
            }

            GridView {
                id: wsGrid
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
                        let s = page.wsSearch.trim()
                        if (s === "") return ["*.jpg", "*.jpeg", "*.png"]
                        return ["*" + s + "*.jpg", "*" + s + "*.jpeg", "*" + s + "*.png"]
                    }
                }

                delegate: Item {
                    required property string filePath
                    required property string fileName
                    width: wsGrid.cellWidth
                    height: wsGrid.cellHeight
                    readonly property bool isAssigned: page.wsAssignment(page.wsTarget) === filePath

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 10
                        color: Theme.surface_container
                        border.color: isAssigned ? Theme.primary
                                    : (wsCellMouse.containsMouse ? Theme.primary : "transparent")
                        border.width: isAssigned ? 3 : 2
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
                            id: wsCellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["bash", "-c",
                                page.wsScript + " --assign " + page.wsTarget + " '" + filePath + "'"])
                        }
                    }
                }
            }
        }
    }
}
