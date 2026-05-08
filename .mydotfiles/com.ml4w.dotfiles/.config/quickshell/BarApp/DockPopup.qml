import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

// DockPopup — Apps · Notes · Todo · Screenshot
PanelWindow {
    id: popup

    property bool active: false
    property var screen
    screen: popup.screen
    
    // 1. Wayland-safe exit animation state
    property bool isAnimating: false
    visible: active || isAnimating

    anchors { bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // ── FIX: Close when clicking outside the popup (backdrop) ──────────────
    MouseArea {
        anchors.fill: parent
        onClicked: popup.active = false
    }

    // ── FIX: Close on ESC key globally across all tabs ─────────────────────
    Shortcut {
        sequence: "Escape"
        onActivated: popup.active = false
    }
    // ───────────────────────────────────────────────────────────────────────

    implicitHeight: 580
    width: screen ? screen.width : 800

    margins { bottom: popup.currentBottomMargin }
    property real currentBottomMargin: active ? 0 : -580

    Behavior on currentBottomMargin {
        NumberAnimation {
            id: slideAnim
            duration: 350
            easing.type: Easing.OutExpo
            onRunningChanged: if (!running && !popup.active) popup.isAnimating = false
        }
    }

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
            isAnimating      = true // Trigger entrance animation safety
            activeTab        = 0
            searchText       = ""
            isCommandMode    = false
            searchField.text = ""
            if (appModel.count === 0) appLoader.running = true
            if (!notesLoaded)         loadNotes()
            if (!todosLoaded)         loadTodos()
            if (!screenshotsLoaded)   loadScreenshots()
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // APP MODEL — fast loader
    // ═════════════════════════════════════════════════════════════════════════
    ListModel { id: appModel }
    property var seenAppNames: ({})

    Process {
        id: appLoader
        command: ["bash", "-c",
            "CACHE=\"$HOME/.cache/quickshell/dock-apps-v2.tsv\"\n" +
            "mkdir -p \"$(dirname \"$CACHE\")\"\n" +
            "rm -f \"$HOME/.cache/quickshell/dock-apps.tsv\" 2>/dev/null\n" +
            "rebuild=0\n" +
            "if [ ! -f \"$CACHE\" ]; then\n" +
            "  rebuild=1\n" +
            "else\n" +
            "  newer=$(find /usr/share/applications /usr/local/share/applications \"$HOME/.local/share/applications\" \\\n" +
            "    -maxdepth 1 -name '*.desktop' -newer \"$CACHE\" -print -quit 2>/dev/null)\n" +
            "  [ -n \"$newer\" ] && rebuild=1\n" +
            "fi\n" +
            "if [ \"$rebuild\" = \"1\" ]; then\n" +
            "  ICON_INDEX=$(mktemp)\n" +
            "  find /usr/share/icons /usr/share/pixmaps \"$HOME/.local/share/icons\" \\\n" +
            "    -type f \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) 2>/dev/null \\\n" +
            "    | awk '\n" +
            "        {\n" +
            "          path = $0\n" +
            "          n = split(path, parts, \"/\")\n" +
            "          base = parts[n]\n" +
            "          sub(/\\.(png|svg|xpm)$/, \"\", base)\n" +
            "          prio = 0\n" +
            "          if (path ~ /scalable/) prio = 1000\n" +
            "          else if (path ~ /256/)  prio = 900\n" +
            "          else if (path ~ /128/)  prio = 800\n" +
            "          else if (path ~ /96/)   prio = 700\n" +
            "          else if (path ~ /64/)   prio = 600\n" +
            "          else if (path ~ /48/)   prio = 500\n" +
            "          else if (path ~ /32/)   prio = 400\n" +
            "          else                    prio = 100\n" +
            "          if (path ~ /\\/apps\\//) prio += 50\n" +
            "          if (!(base in best) || prio > bestp[base]) {\n" +
            "            best[base] = path; bestp[base] = prio\n" +
            "          }\n" +
            "        }\n" +
            "        END { for (k in best) print k \"\\t\" best[k] }\n" +
            "      ' > \"$ICON_INDEX\"\n" +
            "  {\n" +
            "    for f in /usr/share/applications/*.desktop \\\n" +
            "             /usr/local/share/applications/*.desktop \\\n" +
            "             \"$HOME/.local/share/applications\"/*.desktop; do\n" +
            "      [ -f \"$f\" ] || continue\n" +
            "      awk -F= -v idx=\"$ICON_INDEX\" '\n" +
            "        BEGIN {\n" +
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

    property var allApps: []
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

    function onAppAdded(app) {
        allApps.push(app)
        allApps = allApps
        rebuildFilteredApps()
    }

    // ═════════════════════════════════════════════════════════════════════════
    // ICON IMAGE
    // ═════════════════════════════════════════════════════════════════════════
    component IconImage: Item {
        id: iconRoot
        property string iconHint: ""
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

    // ═════════════════════════════════════════════════════════════════════════
    // SCREENSHOTS
    // ═════════════════════════════════════════════════════════════════════════
    property bool   screenshotsLoaded: false
    property bool   screenshotCapturing: false
    property string screenshotMode:  "area"
    property int    screenshotDelay: 0
    ListModel { id: screenshotModel }
    property string _ssBuf: ""

    function loadScreenshots() {
        _ssBuf = ""
        screenshotModel.clear()
        screenshotsLoader.running = true
    }

    Process {
        id: screenshotsLoader
        command: ["bash", "-c",
            "DIR=\"$HOME/Pictures/Screenshots\"\n" +
            "mkdir -p \"$DIR\"\n" +
            "find \"$DIR\" -maxdepth 1 -type f \\\n" +
            "  \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) \\\n" +
            "  -printf '%T@\\t%p\\n' 2>/dev/null \\\n" +
            "  | sort -rn | head -30 | cut -f2-\n"
        ]
        stdout: SplitParser {
            onRead: { popup._ssBuf += data + "\n" }
        }
        onRunningChanged: {
            if (running) return
            let lines = popup._ssBuf.trim().split("\n")
            popup._ssBuf = ""
            for (let p of lines) {
                let path = p.trim()
                if (!path) continue
                let name = path.split("/").pop()
                screenshotModel.append({ ssPath: path, ssName: name })
            }
            popup.screenshotsLoaded = true
        }
    }

    Process {
        id: screenshotCapture
        function shoot(mode, delay) {
            popup.screenshotCapturing = true
            popup.active = false
            
            let preWait = parseFloat(delay) + 0.4
            let cmd = `
                DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
                mkdir -p "$DIR"
                FILENAME="screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
                TEMP_FILE="/tmp/$FILENAME"
                FINAL_FILE="$DIR/$FILENAME"

                sleep ${preWait}

                success=false
                if [ "${mode}" = "screen" ]; then
                    if grim "$TEMP_FILE"; then success=true; fi
                elif [ "${mode}" = "active" ]; then
                    GEOM=$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(f"{w[\\"at\\"][0]},{w[\\"at\\"][1]} {w[\\"size\\"][0]}x{w[\\"size\\"][1]}")' 2>/dev/null)
                    if [ ! -z "$GEOM" ]; then
                        if grim -g "$GEOM" "$TEMP_FILE"; then success=true; fi
                    else
                        if grimblast save active "$TEMP_FILE"; then success=true; fi
                    fi
                elif [ "${mode}" = "area" ]; then
                    if grimblast save area "$TEMP_FILE"; then success=true; fi
                fi

                if [ "$success" = true ] && [ -f "$TEMP_FILE" ]; then
                    mv "$TEMP_FILE" "$FINAL_FILE"
                    if command -v wl-copy >/dev/null; then wl-copy < "$FINAL_FILE"; fi
                    if command -v notify-send >/dev/null; then
                        notify-send -a "Screen Capture" -i "$FINAL_FILE" "Screenshot saved & copied" "$FILENAME" &
                    fi
                    echo "$FINAL_FILE"
                fi
            `
            command = ["bash", "-c", cmd]
            running = true
        }
        stdout: SplitParser { onRead: {} }
        onRunningChanged: {
            if (!running) {
                popup.screenshotCapturing = false
                popup.loadScreenshots()
            }
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
        
        // Smooth Opacity Fade on the Container
        opacity: popup.active ? 1.0 : 0.0
        Behavior on opacity { 
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic } 
        }

        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Theme.background; opacity: 0.8
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8); border.width: 1.5
        }
        // Prevents clicks from falling through the container and closing the menu
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 14

            // ── TAB BAR ──────────────────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter; spacing: 8
                Repeater {
                    model: [
                        { label: "󰍉  Apps",        idx: 0 },
                        { label: "󰎚  Notes",       idx: 1 },
                        { label: "󰄳  Todo",        idx: 2 },
                        { label: "󰄀  Screenshot",  idx: 3 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        property bool sel: popup.activeTab === modelData.idx
                        width: tabLbl.implicitWidth + 28; height: 32; radius: 16
                        
                        // Smooth tactile tab selection
                        color: sel ? Theme.primary : (tabMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent")
                        border.color: Theme.primary; border.width: sel ? 0 : 1
                        
                        scale: tabMouse.pressed ? 0.95 : (tabMouse.containsMouse && !sel ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: tabLbl; anchors.centerIn: parent
                            text: modelData.label
                            color: sel ? Theme.background : Theme.primary
                            font.pixelSize: 12; font.bold: sel
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                popup.activeTab = modelData.idx
                                if (modelData.idx === 0) searchField.forceActiveFocus()
                                if (modelData.idx === 1) notesEdit.forceActiveFocus()
                                if (modelData.idx === 2) todoInput.forceActiveFocus()
                                if (modelData.idx === 3) popup.loadScreenshots()
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
                    
                    // Clear search button
                    Text {
                        text: "󰅖"; color: Theme.primary; font.pixelSize: 16
                        opacity: clearSearchMouse.containsMouse ? 0.8 : 0.5
                        scale: clearSearchMouse.pressed ? 0.9 : 1.0
                        visible: searchField.text.length > 0; verticalAlignment: Text.AlignVCenter
                        
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        MouseArea {
                            id: clearSearchMouse
                            anchors.fill: parent
                            hoverEnabled: true
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
                            
                            // Run terminal command button
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(runLbl.implicitWidth + 48, 620); height: 46; radius: 23
                                
                                color: runCmdMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8) : Theme.primary
                                scale: runCmdMouse.pressed ? 0.98 : (runCmdMouse.containsMouse ? 1.02 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text { id: runLbl; anchors.centerIn: parent
                                       text: "  " + popup.searchText; color: Theme.background
                                       font.pixelSize: 14; font.family: "monospace"; font.bold: true
                                       elide: Text.ElideRight; width: Math.min(implicitWidth, 570) }
                                MouseArea {
                                    id: runCmdMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
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

                                // Tactile App Icon
                                Rectangle {
                                    anchors.centerIn: parent; width: 108; height: 108; radius: 20
                                    
                                    color: appMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Theme.background
                                    border.color: appMouse.containsMouse ? Theme.primary : Theme.background
                                    border.width: 1
                                    
                                    scale: appMouse.pressed ? 0.92 : (appMouse.containsMouse ? 1.05 : 1.0)
                                    
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                                        Item {
                                            Layout.alignment: Qt.AlignHCenter; width: 44; height: 44
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
                                        id: appMouse
                                        anchors.fill: parent; hoverEnabled: true
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
                                    
                                    // ── FIX: Ensure ESC key works while typing in Notes ──────────────────
                                    Keys.onEscapePressed: popup.active = false

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
                            
                            // Copy Notes Button
                            Rectangle {
                                width: 36; height: 36; radius: 10
                                color: copyNotesMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.background
                                border.color: Theme.primary; border.width: 1
                                
                                scale: copyNotesMouse.pressed ? 0.9 : (copyNotesMouse.containsMouse ? 1.1 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text { anchors.centerIn: parent; text: "󰆒"; color: Theme.primary; font.pixelSize: 16 }
                                MouseArea {
                                    id: copyNotesMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: executor.run(["bash", "-c",
                                        "printf '%s' " + JSON.stringify(notesEdit.text) + " | wl-copy"])
                                }
                            }
                            
                            // Clear Notes Button
                            Rectangle {
                                width: 36; height: 36; radius: 10
                                color: clearNotesMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.background
                                border.color: Theme.primary; border.width: 1

                                scale: clearNotesMouse.pressed ? 0.9 : (clearNotesMouse.containsMouse ? 1.1 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 16 }
                                MouseArea {
                                    id: clearNotesMouse
                                    anchors.fill: parent; hoverEnabled: true
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
                                        
                                        // Subtle hover over entire task
                                        color: todoMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05) : Theme.background
                                        border.color: Theme.primary
                                        border.width: todoDone ? 0 : 1
                                        opacity: todoDone ? 0.5 : 1.0
                                        
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        MouseArea {
                                            id: todoMouse
                                            anchors.fill: parent; hoverEnabled: true
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 10

                                            // Bouncy Checkbox
                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: todoDone ? Theme.primary : "transparent"
                                                border.color: Theme.primary; border.width: 1.5
                                                Layout.alignment: Qt.AlignVCenter
                                                
                                                scale: checkMouse.pressed ? 0.8 : (checkMouse.containsMouse ? 1.15 : 1.0)
                                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                                Text { anchors.centerIn: parent; text: "󰄬"
                                                       color: Theme.background; font.pixelSize: 12
                                                       visible: todoDone }
                                                MouseArea {
                                                    id: checkMouse
                                                    anchors.fill: parent; hoverEnabled: true
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

                                            // Delete Task Button
                                            Text {
                                                text: "󰅖"; color: Theme.primary; font.pixelSize: 15
                                                opacity: delTaskMouse.containsMouse ? 0.8 : 0.3
                                                scale: delTaskMouse.pressed ? 0.8 : (delTaskMouse.containsMouse ? 1.2 : 1.0)
                                                Layout.alignment: Qt.AlignVCenter
                                                
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                                MouseArea {
                                                    id: delTaskMouse
                                                    anchors.fill: parent; hoverEnabled: true
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
                                text: "Clear done"; color: Theme.primary; font.pixelSize: 12
                                opacity: clearDoneMouse.containsMouse ? 0.8 : 0.4
                                scale: clearDoneMouse.pressed ? 0.95 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                MouseArea {
                                    id: clearDoneMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        for (let i = todoModel.count - 1; i >= 0; i--)
                                            if (todoModel.get(i).todoDone) todoModel.remove(i)
                                        saveTodos()
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Clear all"; color: Theme.primary; font.pixelSize: 12
                                opacity: clearAllMouse.containsMouse ? 0.8 : 0.4
                                scale: clearAllMouse.pressed ? 0.95 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                MouseArea {
                                    id: clearAllMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: { todoModel.clear(); saveTodos() }
                                }
                            }
                        }
                    }
                }

                // ════════════════════════════════════════════════════════════
                // TAB 3 — SCREENSHOT
                // ════════════════════════════════════════════════════════════
                Item {
                    anchors.fill: parent; visible: popup.activeTab === 3

                    RowLayout {
                        anchors.fill: parent; spacing: 16

                        // ── LEFT — controls ────────────────────────────────
                        ColumnLayout {
                            Layout.preferredWidth: 280
                            Layout.fillHeight: true
                            spacing: 14

                            Text {
                                text: "󰄀  Screenshot"
                                color: Theme.primary; font.pixelSize: 14; font.bold: true
                            }

                            // ─ Mode picker ────────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text: "AREA"; color: Theme.primary; opacity: 0.45; font.pixelSize: 9; font.bold: true }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { id: "screen", icon: "󰍹", label: "Full" },
                                            { id: "area",   icon: "󰒓", label: "Area" },
                                            { id: "active", icon: "󱂬", label: "Window" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: popup.screenshotMode === modelData.id
                                            width: 84; height: 60; radius: 12
                                            
                                            // Interactive Mode Buttons
                                            color: sel ? Theme.primary : (modeMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.background)
                                            border.color: Theme.primary; border.width: sel ? 0 : 1
                                            
                                            scale: modeMouse.pressed ? 0.92 : (modeMouse.containsMouse && !sel ? 1.05 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                            Column {
                                                anchors.centerIn: parent; spacing: 4
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.icon
                                                    color: parent.parent.sel ? Theme.background : Theme.primary
                                                    font.pixelSize: 18
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: modelData.label
                                                    color: parent.parent.sel ? Theme.background : Theme.primary
                                                    font.pixelSize: 10; font.bold: parent.parent.sel
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }
                                            MouseArea {
                                                id: modeMouse
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: popup.screenshotMode = modelData.id
                                            }
                                        }
                                    }
                                }
                            }

                            // ─ Delay picker ───────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text: "DELAY"; color: Theme.primary; opacity: 0.45; font.pixelSize: 9; font.bold: true }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { val: 0,  label: "Now" },
                                            { val: 3,  label: "3s" },
                                            { val: 5,  label: "5s" },
                                            { val: 10, label: "10s" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            property bool sel: popup.screenshotDelay === modelData.val
                                            width: 60; height: 32; radius: 10
                                            
                                            color: sel ? Theme.primary : (delayMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : Theme.background)
                                            border.color: Theme.primary; border.width: sel ? 0 : 1
                                            
                                            scale: delayMouse.pressed ? 0.92 : (delayMouse.containsMouse && !sel ? 1.05 : 1.0)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: parent.sel ? Theme.background : Theme.primary
                                                font.pixelSize: 11; font.bold: parent.sel
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }
                                            MouseArea {
                                                id: delayMouse
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: popup.screenshotDelay = modelData.val
                                            }
                                        }
                                    }
                                }
                            }

                            // ─ Capture button ─────────────────────────────
                            Rectangle {
                                Layout.fillWidth: true; height: 52; radius: 14
                                
                                color: popup.screenshotCapturing ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : (capMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9) : Theme.primary)
                                scale: capMouse.pressed ? 0.96 : (capMouse.containsMouse ? 1.02 : 1.0)
                                
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                RowLayout {
                                    anchors.centerIn: parent; spacing: 10
                                    Text {
                                        text: popup.screenshotCapturing ? "󱎫" : "󰄀"
                                        color: Theme.background
                                        font.pixelSize: 20
                                    }
                                    Text {
                                        text: popup.screenshotCapturing
                                            ? (popup.screenshotDelay > 0
                                                ? "Capturing in " + popup.screenshotDelay + "s\u2026"
                                                : "Capturing\u2026")
                                            : "Capture"
                                        color: Theme.background
                                        font.pixelSize: 14; font.bold: true
                                    }
                                }
                                MouseArea {
                                    id: capMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    enabled: !popup.screenshotCapturing
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        screenshotCapture.shoot(
                                            popup.screenshotMode,
                                            popup.screenshotDelay)
                                    }
                                }
                            }

                            // ─ Hint footer ────────────────────────────────
                            Column {
                                Layout.fillWidth: true; spacing: 4
                                Text { text: "󰈙  Saved to ~/Pictures/Screenshots"; color: Theme.primary; opacity: 0.5; font.pixelSize: 10 }
                                Text { text: "󰆒  Auto-copied to clipboard"; color: Theme.primary; opacity: 0.5; font.pixelSize: 10 }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        // Vertical separator
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            color: Theme.primary; opacity: 0.1
                        }

                        // ── RIGHT — recent shots ───────────────────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "RECENT"
                                    color: Theme.primary; opacity: 0.45
                                    font.pixelSize: 9; font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                
                                // Refresh Shots Button
                                Rectangle {
                                    width: 24; height: 24; radius: 7
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    scale: refShotsMouse.pressed ? 0.85 : (refShotsMouse.containsMouse ? 1.15 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                    Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 12 }
                                    MouseArea {
                                        id: refShotsMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: popup.loadScreenshots()
                                    }
                                }
                                
                                // Open Shots Folder Button
                                Rectangle {
                                    width: 24; height: 24; radius: 7
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    scale: openFolderMouse.pressed ? 0.85 : (openFolderMouse.containsMouse ? 1.15 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                    Text { anchors.centerIn: parent; text: "󰉋"; color: Theme.primary; font.pixelSize: 12 }
                                    MouseArea {
                                        id: openFolderMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            executor.run(["bash", "-c",
                                                "DIR=\"$(xdg-user-dir PICTURES 2>/dev/null || echo \"$HOME/Pictures\")/Screenshots\"; " +
                                                "command -v nemo &>/dev/null && nemo \"$DIR\" || xdg-open \"$DIR\""])
                                            popup.active = false
                                        }
                                    }
                                }
                            }

                            // Empty state
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                visible: screenshotModel.count === 0
                                Column {
                                    anchors.centerIn: parent; spacing: 8
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "󰋩"; color: Theme.primary; font.pixelSize: 44; opacity: 0.18
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "No screenshots yet"
                                        color: Theme.primary; font.pixelSize: 13; opacity: 0.4
                                    }
                                }
                            }

                            // List with thumbnails
                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: screenshotModel.count > 0
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                ListView {
                                    id: ssListView
                                    model: screenshotModel
                                    spacing: 6
                                    boundsBehavior: Flickable.StopAtBounds

                                    delegate: Rectangle {
                                        required property int    index
                                        required property string ssPath
                                        required property string ssName

                                        width: ssListView.width
                                        height: 64
                                        radius: 12
                                        
                                        color: rowHoverArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10) : Theme.background
                                        border.color: rowHoverArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                        border.width: 1
                                        
                                        // Slight scale down on click (not on hover because it's a full width list item)
                                        scale: rowHoverArea.pressed ? 0.98 : 1.0
                                        
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Behavior on border.color { ColorAnimation { duration: 120 } }
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 10

                                            // Thumbnail
                                            Rectangle {
                                                Layout.preferredWidth: 80
                                                Layout.preferredHeight: 52
                                                radius: 8
                                                color: Qt.rgba(0, 0, 0, 0.05)
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    source: "file://" + ssPath
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    cache: true
                                                    sourceSize.width: 160
                                                    sourceSize.height: 104
                                                }
                                            }

                                            // Action: open with default viewer
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: openImgMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                                
                                                scale: openImgMouse.pressed ? 0.9 : (openImgMouse.containsMouse ? 1.15 : 1.0)
                                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text { anchors.centerIn: parent; text: "󰏋"; color: Theme.primary; font.pixelSize: 14 }
                                                MouseArea {
                                                    id: openImgMouse
                                                    anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        executor.run(["xdg-open", ssPath])
                                                        popup.active = false
                                                    }
                                                }
                                            }

                                            // Action: reveal in nemo
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                radius: 8
                                                color: revealImgMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                                
                                                scale: revealImgMouse.pressed ? 0.9 : (revealImgMouse.containsMouse ? 1.15 : 1.0)
                                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text { anchors.centerIn: parent; text: "󰉋"; color: Theme.primary; font.pixelSize: 14 }
                                                MouseArea {
                                                    id: revealImgMouse
                                                    anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let dir = ssPath.substring(0, ssPath.lastIndexOf("/"))
                                                        executor.run(["bash", "-c",
                                                            "command -v nemo &>/dev/null && nemo \"" + dir + "\" || xdg-open \"" + dir + "\""])
                                                        popup.active = false
                                                    }
                                                }
                                            }
                                        }

                                        // Row-level hover + click-to-copy-path
                                        MouseArea {
                                            id: rowHoverArea
                                            anchors.fill: parent
                                            anchors.rightMargin: 80   // leave action buttons clickable
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                executor.run(["bash", "-c",
                                                    "command -v wl-copy &>/dev/null && printf '%s' " +
                                                    JSON.stringify(ssPath) + " | wl-copy"])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}