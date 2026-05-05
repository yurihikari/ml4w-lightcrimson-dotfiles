import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

// DockPopup — Apps · Notes · Todo
// Wire-up in ScreenFrame:
//   DockPopup { id: dockPopup; screen: root.screen }
//   onClicked: dockPopup.active = !dockPopup.active
PanelWindow {
    id: popup

    property bool active: false
    property var screen
    screen: popup.screen

    anchors { bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    implicitHeight: 580
    width: screen ? screen.width : 800

    margins { bottom: popup.currentBottomMargin }
    property real currentBottomMargin: active ? 0 : -580

    Behavior on currentBottomMargin {
        NumberAnimation {
            id: slideAnim
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    visible: active || slideAnim.running

    // ── EXECUTOR ─────────────────────────────────────────────────────────────
    Process {
        id: executor
        function run(args) { command = args; running = true }
    }

    // ── GLOBAL STATE ─────────────────────────────────────────────────────────
    property int    activeTab:    0
    property string searchText:   ""
    property bool   isCommandMode: false

    onActiveChanged: {
        if (active) {
            activeTab        = 0
            searchText       = ""
            isCommandMode    = false
            searchField.text = ""
            if (appModel.count === 0) appLoader.running = true
            if (!notesLoaded)         loadNotes()
            if (!todosLoaded)         loadTodos()
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // APP MODEL — fast loader
    //
    // The previous loader ran `find /usr/share/icons …` once per app, which
    // does hundreds of filesystem walks (≈300ms × N apps = several seconds).
    //
    // The fast version:
    //   1. A persistent cache at ~/.cache/quickshell/dock-apps.tsv stores
    //      parsed name/exec/iconHint/keywords per .desktop file. The cache
    //      is rebuilt only when any .desktop file is newer than the cache.
    //   2. We DO NOT resolve icon paths in the loader. We just store the
    //      icon hint string. The QML Image element resolves it at render
    //      time using a list of candidate paths — Qt's Image cache means
    //      this happens lazily and only for visible cells (GridView reuses
    //      delegates, so off-screen apps never trigger a lookup).
    // ═════════════════════════════════════════════════════════════════════════
    ListModel { id: appModel }
    property var seenAppNames: ({})

    Process {
        id: appLoader
        command: ["bash", "-c",
            "CACHE=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"\n" +
            "mkdir -p \"$(dirname \"$CACHE\")\"\n" +
            "# Clean up old v1 cache from previous version\n" +
            "rm -f \"$HOME/.cache/quickshell/dock-apps.tsv\" 2>/dev/null\n" +
            "\n" +
            "# Rebuild if cache missing or any .desktop newer than it\n" +
            "rebuild=0\n" +
            "if [ ! -f \"$CACHE\" ]; then\n" +
            "  rebuild=1\n" +
            "else\n" +
            "  newer=$(find /usr/share/applications /usr/local/share/applications \"$HOME/.local/share/applications\" \\\n" +
            "    -maxdepth 1 -name '*.desktop' -newer \"$CACHE\" -print -quit 2>/dev/null)\n" +
            "  [ -n \"$newer\" ] && rebuild=1\n" +
            "fi\n" +
            "\n" +
            "if [ \"$rebuild\" = \"1\" ]; then\n" +
            "  # ── BUILD ICON INDEX (one big find, then everything is in-memory) ─\n" +
            "  # Walks every standard icon location ONCE and builds a name→path map.\n" +
            "  # We pick the largest available size when duplicates exist.\n" +
            "  ICON_INDEX=$(mktemp)\n" +
            "  find /usr/share/icons /usr/share/pixmaps \"$HOME/.local/share/icons\" \\\n" +
            "    -type f \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) 2>/dev/null \\\n" +
            "    | awk '\n" +
            "        {\n" +
            "          path = $0\n" +
            "          # Strip directory and extension to get just the icon name\n" +
            "          n = split(path, parts, \"/\")\n" +
            "          base = parts[n]\n" +
            "          sub(/\\.(png|svg|xpm)$/, \"\", base)\n" +
            "          # Heuristic priority: scalable > 256 > 128 > 64 > 48 > 32 > rest\n" +
            "          prio = 0\n" +
            "          if (path ~ /scalable/) prio = 1000\n" +
            "          else if (path ~ /256/)  prio = 900\n" +
            "          else if (path ~ /128/)  prio = 800\n" +
            "          else if (path ~ /96/)   prio = 700\n" +
            "          else if (path ~ /64/)   prio = 600\n" +
            "          else if (path ~ /48/)   prio = 500\n" +
            "          else if (path ~ /32/)   prio = 400\n" +
            "          else                    prio = 100\n" +
            "          # Prefer apps/ subdirectory over mimetypes/places/etc.\n" +
            "          if (path ~ /\\/apps\\//) prio += 50\n" +
            "          if (!(base in best) || prio > bestp[base]) {\n" +
            "            best[base] = path; bestp[base] = prio\n" +
            "          }\n" +
            "        }\n" +
            "        END { for (k in best) print k \"\\t\" best[k] }\n" +
            "      ' > \"$ICON_INDEX\"\n" +
            "\n" +
            "  # ── PARSE .desktop FILES AND RESOLVE ICONS AGAINST THE INDEX ──────\n" +
            "  {\n" +
            "    for f in /usr/share/applications/*.desktop \\\n" +
            "             /usr/local/share/applications/*.desktop \\\n" +
            "             \"$HOME/.local/share/applications\"/*.desktop; do\n" +
            "      [ -f \"$f\" ] || continue\n" +
            "      awk -F= -v idx=\"$ICON_INDEX\" '\n" +
            "        BEGIN {\n" +
            "          # Load the icon index into memory once per .desktop file.\n" +
            "          # (awk per-file is fine; index is small and OS-cached.)\n" +
            "          while ((getline line < idx) > 0) {\n" +
            "            split(line, a, \"\\t\"); icons[a[1]] = a[2]\n" +
            "          }\n" +
            "          close(idx)\n" +
            "          name=\"\"; exec=\"\"; icon=\"\"; keys=\"\"; nodisp=0; insec=0\n" +
            "        }\n" +
            "        /^\\[Desktop Entry\\]/ { insec=1; next }\n" +
            "        /^\\[/ { insec=0; next }\n" +
            "        insec && /^Name=/     && name==\"\" { sub(/^Name=/,\"\");     name=$0; next }\n" +
            "        insec && /^Exec=/     && exec==\"\" { sub(/^Exec=/,\"\");     exec=$0; next }\n" +
            "        insec && /^Icon=/     && icon==\"\" { sub(/^Icon=/,\"\");     icon=$0; next }\n" +
            "        insec && /^Keywords=/ && keys==\"\" { sub(/^Keywords=/,\"\"); keys=$0; next }\n" +
            "        insec && /^NoDisplay=true/        { nodisp=1 }\n" +
            "        END {\n" +
            "          if (nodisp || name==\"\") exit 0\n" +
            "          gsub(/ *%[uUfFdDnNickvm]*/, \"\", exec)\n" +
            "          gsub(/^[ \\t]+|[ \\t]+$/, \"\", exec)\n" +
            "          gsub(/;/, \" \", keys)\n" +
            "          # Resolve icon to absolute path using the index.\n" +
            "          # If icon is already an absolute path, keep it.\n" +
            "          # Otherwise look it up in the index. Empty if not found.\n" +
            "          ipath = \"\"\n" +
            "          if (icon != \"\") {\n" +
            "            if (substr(icon, 1, 1) == \"/\") ipath = icon\n" +
            "            else if (icon in icons)        ipath = icons[icon]\n" +
            "          }\n" +
            "          printf \"%s\\t%s\\t%s\\t%s\\n\", name, exec, ipath, tolower(keys)\n" +
            "        }\n" +
            "      ' \"$f\"\n" +
            "    done\n" +
            "  } | sort -u > \"$CACHE.tmp\" && mv \"$CACHE.tmp\" \"$CACHE\"\n" +
            "  rm -f \"$ICON_INDEX\"\n" +
            "fi\n" +
            "\n" +
            "cat \"$CACHE\""
        ]
        stdout: SplitParser {
            onRead: {
                let parts = data.split("\t")
                if (parts.length >= 2 && parts[0].trim() !== "") {
                    let name = parts[0].trim()
                    if (popup.seenAppNames[name]) return
                    popup.seenAppNames[name] = true
                    let app = {
                        appName: name,
                        appExec: parts[1].trim(),
                        appIcon: parts.length > 2 ? parts[2].trim() : "",
                        appKeys: parts.length > 3 ? parts[3].trim().toLowerCase() : ""
                    }
                    appModel.append(app)
                    popup.onAppAdded(app)
                }
            }
        }
    }

    // OPTIMIZATION: allApps built incrementally by the loader (appended one-by-one),
    // not by rebuilding from scratch on every count change.
    property var allApps: []

    // filteredApps is now a stored property updated only when searchText changes,
    // not a computed binding that re-evaluates on every property access.
    property var filteredApps: []

    function rebuildFilteredApps() {
        let q = searchText.toLowerCase().trim()
        if (q === "") {
            filteredApps = allApps.slice(0, 80)
        } else {
            filteredApps = allApps.filter(e =>
                e.appName.toLowerCase().includes(q) || e.appKeys.includes(q)
            ).slice(0, 48)
        }
    }

    onSearchTextChanged: {
        rebuildFilteredApps()
        let q = searchText.trim()
        isCommandMode = q.length > 0 && (
            q.startsWith("/") || q.includes(" ") ||
            (filteredApps.length === 0 && q.length > 1))
    }

    // Called by the loader after each batch of apps is added
    function onAppAdded(app) {
        allApps.push(app)
        allApps = allApps  // trigger binding update
        rebuildFilteredApps()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ICON RESOLVER — picks a candidate file path for a freedesktop icon name.
    // Returns a list-style URL that Qt's Image element accepts; if the first
    // candidate doesn't exist Qt falls back via status === Image.Error which
    // we use to show the placeholder glyph in the delegate. We try the
    // common locations in priority order. NO `find` calls — pure path joins.
    // ─────────────────────────────────────────────────────────────────────────
    function resolveIconUrl(hint) {
        if (!hint || hint === "") return ""
        // Absolute path → use as-is
        if (hint.startsWith("/")) return "file://" + hint
        // Already a URL
        if (hint.startsWith("file://") || hint.startsWith("http")) return hint

        // Candidate roots in priority order. We only try the first couple
        // since Qt resolves them lazily and most apps use hicolor scalable.
        let home = Quickshell.env("HOME") || ""
        return "image://icon/" + hint   // see IconImage component below
    }

    // ═════════════════════════════════════════════════════════════════════════
    // NOTES
    // ═════════════════════════════════════════════════════════════════════════
    property bool   notesLoaded:  false
    property bool   notesLoading: false
    property bool   notesDirty:   false
    property string notesContent: ""
    property string notesBuf:     ""

    function loadNotes() {
        notesBuf = ""
        notesReadProc.running = true
    }

    Process {
        id: notesReadProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/quickshell/dock-notes.txt\"\n" +
            "mkdir -p \"$(dirname \"$f\")\"\n" +
            "[ -f \"$f\" ] && cat \"$f\" || true"
        ]
        stdout: SplitParser {
            onRead: {
                popup.notesBuf = popup.notesBuf === "" ? data : popup.notesBuf + "\n" + data
            }
        }
        onRunningChanged: {
            if (!running) {
                popup.notesLoading = true
                notesEdit.text     = popup.notesBuf
                popup.notesContent = popup.notesBuf
                popup.notesBuf     = ""
                popup.notesLoaded  = true
                popup.notesLoading = false
            }
        }
    }

    Process {
        id: notesWriteProc
        function write(content) {
            let b64 = Qt.btoa(unescape(encodeURIComponent(content)))
            command = ["python3", "-c",
                "import base64, pathlib\n" +
                "p = pathlib.Path.home() / '.config/quickshell/dock-notes.txt'\n" +
                "p.parent.mkdir(parents=True, exist_ok=True)\n" +
                "p.write_bytes(base64.b64decode('" + b64 + "'))\n"
            ]
            running = true
        }
    }

    Timer {
        id: notesDebounce; interval: 1500; repeat: false
        onTriggered: {
            notesWriteProc.write(popup.notesContent)
            popup.notesDirty = false
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // TODO
    // ═════════════════════════════════════════════════════════════════════════
    ListModel { id: todoModel }
    property bool todosLoaded:  false
    property bool todosLoading: false

    function loadTodos() {
        todosReadProc.running = true
    }

    Process {
        id: todosReadProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/quickshell/dock-todos.txt\"\n" +
            "mkdir -p \"$(dirname \"$f\")\"\n" +
            "[ -f \"$f\" ] && cat \"$f\" || true"
        ]
        stdout: SplitParser {
            onRead: {
                let l = data
                if (l.trim() === "") return
                let done = l.startsWith("[x] ")
                let txt  = (done || l.startsWith("[ ] ")) ? l.slice(4) : l
                todoModel.append({ todoText: txt, todoDone: done })
            }
        }
        onRunningChanged: {
            if (!running) popup.todosLoaded = true
        }
    }

    Process {
        id: todosWriteProc
        function write(content) {
            let b64 = Qt.btoa(unescape(encodeURIComponent(content)))
            command = ["python3", "-c",
                "import base64, pathlib\n" +
                "p = pathlib.Path.home() / '.config/quickshell/dock-todos.txt'\n" +
                "p.parent.mkdir(parents=True, exist_ok=True)\n" +
                "p.write_bytes(base64.b64decode('" + b64 + "'))\n"
            ]
            running = true
        }
    }

    function saveTodos() {
        let lines = []
        for (let i = 0; i < todoModel.count; i++) {
            let t = todoModel.get(i)
            lines.push((t.todoDone ? "[x] " : "[ ] ") + t.todoText)
        }
        todosWriteProc.write(lines.join("\n"))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ICON IMAGE — the cache already stores absolute paths, so we just load
    // them directly. No candidate walking needed because the bulk find at
    // cache-build time has already resolved every icon to its best variant.
    // ─────────────────────────────────────────────────────────────────────────
    component IconImage: Item {
        id: iconRoot
        property string iconHint: ""   // already absolute path from cache
        property bool ready: img.status === Image.Ready

        Image {
            id: img
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            source: iconRoot.iconHint && iconRoot.iconHint !== ""
                ? "file://" + iconRoot.iconHint
                : ""
        }
    }

    // ── CONTAINER ────────────────────────────────────────────────────────────
    Rectangle {
        id: container
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        anchors.left: parent.left
        anchors.leftMargin: parent.width > 700 ? parent.width / 2 - 350 : 40
        anchors.right: parent.right
        anchors.rightMargin: parent.width > 700 ? parent.width / 2 - 350 : 40
        height: 520
        radius: 28; color: "transparent"; clip: false

        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Theme.background; opacity: 0.8
            border.color: Theme.primary; border.width: 1.5
        }
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 14

            // ── TAB BAR ──────────────────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter; spacing: 8
                Repeater {
                    model: [
                        { label: "󰍉  Apps",  idx: 0 },
                        { label: "󰎚  Notes", idx: 1 },
                        { label: "󰄳  Todo",  idx: 2 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        property bool sel: popup.activeTab === modelData.idx
                        width: tabLbl.implicitWidth + 28; height: 32; radius: 16
                        color: sel ? Theme.primary : "transparent"
                        border.color: Theme.primary; border.width: sel ? 0 : 1
                        Text {
                            id: tabLbl; anchors.centerIn: parent
                            text: modelData.label
                            color: sel ? Theme.background : Theme.primary
                            font.pixelSize: 12; font.bold: sel
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                popup.activeTab = modelData.idx
                                if (modelData.idx === 0) searchField.forceActiveFocus()
                                if (modelData.idx === 1) notesEdit.forceActiveFocus()
                                if (modelData.idx === 2) todoInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // ── SEARCH BAR ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 44; radius: 14
                color: Theme.background; border.color: Theme.primary; border.width: 1
                visible: popup.activeTab === 0
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                    Text {
                        text: popup.isCommandMode ? "󰆍" : "󰍉"
                        color: popup.isCommandMode ? Theme.accent : Theme.primary
                        font.pixelSize: 18; verticalAlignment: Text.AlignVCenter
                    }
                    TextInput {
                        id: searchField; Layout.fillWidth: true
                        color: Theme.primary; font.pixelSize: 15
                        selectionColor: Theme.primary; selectedTextColor: Theme.background
                        verticalAlignment: TextInput.AlignVCenter; height: parent.height; clip: true
                        focus: popup.activeTab === 0 && popup.active
                        onTextChanged: popup.searchText = text
                        Keys.onReturnPressed: {
                            if (popup.isCommandMode)
                                executor.run(["kitty", "--", "bash", "-c",
                                    searchField.text + "; echo; read -rsp 'Press any key…' -n1"])
                            else if (popup.filteredApps.length > 0)
                                executor.run(["bash", "-c", popup.filteredApps[0].appExec])
                            popup.active = false
                        }
                        Keys.onEscapePressed: popup.active = false
                        Text {
                            anchors.fill: parent
                            text: "Search apps or type a command\u2026"
                            color: Theme.primary; opacity: 0.35; font.pixelSize: 15
                            verticalAlignment: Text.AlignVCenter
                            visible: searchField.text.length === 0
                        }
                    }
                    Rectangle {
                        visible: popup.isCommandMode
                        width: cmdBadge.implicitWidth + 16; height: 24; radius: 12
                        color: Theme.accent; opacity: 0.85
                        Text { id: cmdBadge; anchors.centerIn: parent; text: "TERMINAL"
                               color: Theme.background; font.pixelSize: 10; font.bold: true }
                    }
                    Text {
                        visible: !popup.isCommandMode && searchField.text.length === 0
                        text: appModel.count + " apps"
                        color: Theme.primary; opacity: 0.28; font.pixelSize: 11
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: "󰅖"; color: Theme.primary; font.pixelSize: 16; opacity: 0.5
                        visible: searchField.text.length > 0; verticalAlignment: Text.AlignVCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                        }
                    }
                }
            }

            // ── CONTENT ───────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                // TAB 0 — APPS
                Item {
                    anchors.fill: parent; visible: popup.activeTab === 0

                    Item {
                        anchors.fill: parent; visible: popup.isCommandMode
                        Column {
                            anchors.centerIn: parent; spacing: 22
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "󰆍"; color: Theme.primary; font.pixelSize: 60; opacity: 0.22 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "Run in Kitty terminal"
                                   color: Theme.primary; font.pixelSize: 14; opacity: 0.45 }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(runLbl.implicitWidth + 48, 620); height: 46; radius: 23
                                color: Theme.primary
                                Text { id: runLbl; anchors.centerIn: parent
                                       text: "  " + popup.searchText; color: Theme.background
                                       font.pixelSize: 14; font.family: "monospace"; font.bold: true
                                       elide: Text.ElideRight; width: Math.min(implicitWidth, 570) }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        executor.run(["kitty", "--", "bash", "-c",
                                            popup.searchText + "; echo; read -rsp 'Press any key…' -n1"])
                                        popup.active = false
                                    }
                                }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "Press Enter or click above"
                                   color: Theme.primary; font.pixelSize: 11; opacity: 0.28 }
                        }
                    }

                    Item {
                        anchors.fill: parent; visible: !popup.isCommandMode

                        Column {
                            anchors.centerIn: parent; spacing: 12
                            visible: appModel.count === 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "󰍉"; color: Theme.primary; font.pixelSize: 48; opacity: 0.15 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "Loading apps\u2026"; color: Theme.primary; font.pixelSize: 14; opacity: 0.35 }
                        }

                        Column {
                            anchors.centerIn: parent; spacing: 10
                            visible: popup.filteredApps.length === 0 && appModel.count > 0 &&
                                     popup.searchText.length > 0 && !popup.isCommandMode
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "󰍉"; color: Theme.primary; font.pixelSize: 44; opacity: 0.18 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "No apps found"; color: Theme.primary; font.pixelSize: 13; opacity: 0.4 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter
                                   text: "Add a space to switch to terminal mode"
                                   color: Theme.primary; font.pixelSize: 11; opacity: 0.28 }
                        }

                        GridView {
                            id: appGrid
                            property int cols: Math.max(1, Math.floor(parent.width / 118))
                            width: cols * 118; height: parent.height
                            anchors.horizontalCenter: parent.horizontalCenter
                            clip: true
                            visible: popup.filteredApps.length > 0 || appModel.count === 0
                            cellWidth: 118; cellHeight: 118
                            model: popup.filteredApps.length

                            delegate: Item {
                                width: appGrid.cellWidth; height: appGrid.cellHeight
                                property var app: popup.filteredApps[index] || {}

                                Rectangle {
                                    anchors.centerIn: parent; width: 108; height: 108; radius: 20
                                    color: Theme.background; border.color: Theme.background; border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                                        Item {
                                            Layout.alignment: Qt.AlignHCenter; width: 44; height: 44

                                            // Icon resolved on-demand from candidate paths
                                            IconImage {
                                                id: icon
                                                anchors.fill: parent
                                                iconHint: app.appIcon || ""
                                            }
                                            Text {
                                                anchors.centerIn: parent; text: "󰣆"
                                                color: Theme.primary; font.pixelSize: 30; opacity: 0.28
                                                visible: !icon.ready
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; text: app.appName || ""
                                            color: Theme.primary; font.pixelSize: 11; font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight; wrapMode: Text.WordWrap; maximumLineCount: 2
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; hoverEnabled: true
                                        onEntered: parent.border.color = Theme.primary
                                        onExited:  parent.border.color = Theme.background
                                        onClicked: { executor.run(["bash", "-c", app.appExec]); popup.active = false }
                                    }
                                }
                            }
                        }
                    }
                }

                // TAB 1 — NOTES
                Item {
                    anchors.fill: parent; visible: popup.activeTab === 1

                    ColumnLayout { anchors.fill: parent; spacing: 10

                        RowLayout { Layout.fillWidth: true
                            Text { text: "󰎚  Quick Notes"; color: Theme.primary; font.pixelSize: 14; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text { visible: popup.notesDirty;  text: "Saving\u2026"
                                   color: Theme.primary; font.pixelSize: 11; opacity: 0.4 }
                            Text { visible: !popup.notesDirty && popup.notesLoaded; text: "Auto-saved"
                                   color: Theme.primary; font.pixelSize: 11; opacity: 0.3 }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 16
                            color: Theme.background; border.color: Theme.primary; border.width: 1

                            ScrollView {
                                anchors.fill: parent; anchors.margins: 14
                                clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                TextEdit {
                                    id: notesEdit
                                    width: parent.width
                                    color: Theme.primary; font.pixelSize: 14; wrapMode: TextEdit.Wrap
                                    selectionColor: Theme.primary; selectedTextColor: Theme.background
                                    focus: popup.activeTab === 1 && popup.active

                                    Text {
                                        anchors.fill: parent
                                        text: "Start typing your notes here\u2026\n\nAuto-saved to ~/.config/quickshell/dock-notes.txt"
                                        color: Theme.primary; opacity: 0.25; font.pixelSize: 14
                                        wrapMode: Text.Wrap; visible: notesEdit.text.length === 0
                                    }

                                    onTextChanged: {
                                        if (!popup.notesLoading) {
                                            popup.notesContent = text
                                            popup.notesDirty   = true
                                            notesDebounce.restart()
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout { Layout.fillWidth: true; spacing: 8
                            Rectangle {
                                width: 36; height: 36; radius: 10
                                color: Theme.background; border.color: Theme.primary; border.width: 1
                                Text { anchors.centerIn: parent; text: "󰆒"; color: Theme.primary; font.pixelSize: 16 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: executor.run(["bash", "-c",
                                        "printf '%s' " + JSON.stringify(notesEdit.text) + " | wl-copy"])
                                }
                            }
                            Rectangle {
                                width: 36; height: 36; radius: 10
                                color: Theme.background; border.color: Theme.primary; border.width: 1
                                Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 16 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        notesEdit.text     = ""
                                        popup.notesContent = ""
                                        notesWriteProc.write("")
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: notesEdit.text.length + " chars"
                                color: Theme.primary; font.pixelSize: 11; opacity: 0.3
                            }
                        }
                    }
                }

                // TAB 2 — TODO
                Item {
                    anchors.fill: parent; visible: popup.activeTab === 2

                    ColumnLayout { anchors.fill: parent; spacing: 12

                        RowLayout { Layout.fillWidth: true
                            Text { text: "󰄳  Tasks"; color: Theme.primary; font.pixelSize: 14; font.bold: true }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: {
                                    let done = 0
                                    for (let i = 0; i < todoModel.count; i++)
                                        if (todoModel.get(i).todoDone) done++
                                    return done + " / " + todoModel.count + " done"
                                }
                                color: Theme.primary; font.pixelSize: 11; opacity: 0.4
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 44; radius: 14
                            color: Theme.background; border.color: Theme.primary; border.width: 1
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; spacing: 8
                                Text { text: "󰐕"; color: Theme.primary; font.pixelSize: 18; opacity: 0.5 }
                                TextInput {
                                    id: todoInput; Layout.fillWidth: true
                                    color: Theme.primary; font.pixelSize: 14
                                    selectionColor: Theme.primary; selectedTextColor: Theme.background
                                    verticalAlignment: TextInput.AlignVCenter; height: parent.height; clip: true
                                    focus: popup.activeTab === 2 && popup.active

                                    Keys.onReturnPressed: {
                                        let t = todoInput.text.trim()
                                        if (t !== "") {
                                            todoModel.append({ todoText: t, todoDone: false })
                                            saveTodos()
                                            todoInput.text = ""
                                        }
                                    }
                                    Keys.onEscapePressed: popup.active = false

                                    Text {
                                        anchors.fill: parent
                                        text: "Add a task and press Enter\u2026"
                                        color: Theme.primary; opacity: 0.3; font.pixelSize: 14
                                        verticalAlignment: Text.AlignVCenter
                                        visible: todoInput.text.length === 0
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: todoModel.count === 0
                            Column {
                                anchors.centerIn: parent; spacing: 10
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: "󰄳"; color: Theme.primary; font.pixelSize: 44; opacity: 0.12 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: "No tasks yet"
                                       color: Theme.primary; font.pixelSize: 13; opacity: 0.3 }
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: todoModel.count > 0
                            clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            Column {
                                width: parent.width; spacing: 6; bottomPadding: 8

                                Repeater {
                                    model: todoModel

                                    delegate: Rectangle {
                                        required property int    index
                                        required property string todoText
                                        required property bool   todoDone

                                        width: parent.width; height: 46; radius: 13
                                        color: Theme.background
                                        border.color: Theme.primary
                                        border.width: todoDone ? 0 : 1
                                        opacity: todoDone ? 0.5 : 1.0

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 10

                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: todoDone ? Theme.primary : "transparent"
                                                border.color: Theme.primary; border.width: 1.5
                                                Layout.alignment: Qt.AlignVCenter
                                                Text { anchors.centerIn: parent; text: "󰄬"
                                                       color: Theme.background; font.pixelSize: 12
                                                       visible: todoDone }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        todoModel.setProperty(index, "todoDone", !todoDone)
                                                        saveTodos()
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true; text: todoText
                                                color: Theme.primary; font.pixelSize: 13
                                                elide: Text.ElideRight; font.strikeout: todoDone
                                                opacity: todoDone ? 0.5 : 1.0
                                            }

                                            Text {
                                                text: "󰅖"; color: Theme.primary; font.pixelSize: 15; opacity: 0.3
                                                Layout.alignment: Qt.AlignVCenter
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        todoModel.remove(index)
                                                        saveTodos()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; visible: todoModel.count > 0
                            Text {
                                text: "Clear done"; color: Theme.primary; font.pixelSize: 12; opacity: 0.4
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        for (let i = todoModel.count - 1; i >= 0; i--)
                                            if (todoModel.get(i).todoDone) todoModel.remove(i)
                                        saveTodos()
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Clear all"; color: Theme.primary; font.pixelSize: 12; opacity: 0.4
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { todoModel.clear(); saveTodos() }
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
