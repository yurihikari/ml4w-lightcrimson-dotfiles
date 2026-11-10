import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

// DockPopup — Apps · Notes · Todo (screenshots: the Capture corner)
PanelWindow {
    id: popup

    property bool active: false
    property var screen
    screen: popup.screen
    
    // 1. Wayland-safe exit animation state
    property bool isAnimating: false
    visible: active || isAnimating

    // Covers the screen so the dock's outline can run round the frame, and so
    // a click anywhere outside the dock closes it (like the bar popups).
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    // Slides out of the frame on its own: Hyprland's layer animation is off
    // for this namespace (hypr/conf/custom/style.lua), or it slid in twice.
    WlrLayershell.namespace: "quickshell-drawer"
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // The frame stays clickable while the dock is open; whatever a click on
    // it opens takes over (FrameState).
    mask: FrameHoleMask { window: popup }
    readonly property string claimKey: "dock:" + (popup.screen ? popup.screen.name : "")
    Connections {
        target: FrameState
        function onClaimed(k) { if (k !== popup.claimKey) popup.active = false }
    }

    IpcHandler {
        target: "dock"
        function toggle(): void { popup.active = !popup.active }
        function open(): void { popup.active = true }
        function close(): void { popup.active = false }
        // 0 apps, 1 notes, 2 todo
        function openTab(tab: int): void { popup.active = true; popup.openTab(tab) }
    }

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

    // The window stays put; the dock rises out of the bottom frame (FrameDrawer
    // below) and the window unmaps once that has slid back in.

    // ── GLOBAL STATE ─────────────────────────────────────────────────────────
    property int    activeTab:    0
    property string searchText:   ""
    property bool   isCommandMode: false

    onActiveChanged: {
        if (active) {
            FrameState.claim(claimKey)
            isAnimating      = true // Trigger entrance animation safety
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
        appGrid.currentIndex = 0   // keep keyboard highlight on the top match
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

    // Written as UTF-8 by Quickshell itself. (It used to go through
    // Qt.btoa after a manual UTF-8 step, which encoded accented letters
    // twice on every save, so "é" kept growing into "ÃƒÂ©…".)
    FileView {
        id: notesWriteProc
        path: Quickshell.env("HOME") + "/.config/quickshell/dock-notes.txt"
        printErrors: false
        blockLoading: false
        preload: false
        function write(content) { setText(content) }
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

    // Written as UTF-8 by Quickshell itself. (It used to go through
    // Qt.btoa after a manual UTF-8 step, which encoded accented letters
    // twice on every save, so "é" kept growing into "ÃƒÂ©…".)
    FileView {
        id: todosWriteProc
        path: Quickshell.env("HOME") + "/.config/quickshell/dock-todos.txt"
        printErrors: false
        blockLoading: false
        preload: false
        function write(content) { setText(content) }
    }

    function saveTodos() {
        let lines = []
        for (let i = 0; i < todoModel.count; i++) {
            let t = todoModel.get(i)
            lines.push((t.todoDone ? "[x] " : "[ ] ") + t.todoText)
        }
        todosWriteProc.write(lines.join("\n"))
    }

    // Done count for the Todo header (the model has no aggregate of its own)
    property int todoDoneCount: 0
    function countDone() {
        let n = 0
        for (let i = 0; i < todoModel.count; i++) if (todoModel.get(i).todoDone) n++
        todoDoneCount = n
    }
    Connections {
        target: todoModel
        function onCountChanged() { popup.countDone() }
        function onDataChanged() { popup.countDone() }
    }

    function openTab(i) {
        activeTab = i
        if (i === 0) searchField.forceActiveFocus()
        else if (i === 1) notesEdit.forceActiveFocus()
        else if (i === 2) todoInput.forceActiveFocus()
    }
    function addTodo() {
        const t = todoInput.text.trim()
        if (t === "") return
        todoModel.append({ todoText: t, todoDone: false })
        saveTodos()
        todoInput.text = ""
    }
    function launch(app) {
        Sys.run(["bash", "-c", app.appExec])
        popup.active = false
    }
    function runCommand() {
        Sys.run(["kitty", "--", "bash", "-c", searchText + "; echo; read -rsp 'Press any key…' -n1"])
        popup.active = false
    }

    Shortcut { sequence: "Ctrl+Tab"; enabled: popup.active; onActivated: popup.openTab((popup.activeTab + 1) % 3) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; enabled: popup.active; onActivated: popup.openTab((popup.activeTab + 2) % 3) }

    // A text button that asks for a second click before doing something that
    // can't be undone (clearing notes or the task list).
    component ConfirmChip: Chip {
        id: cc
        property string confirmText: "Sure?"
        property bool armed: false
        signal confirmed()
        selected: armed
        onClicked: {
            if (armed) { armed = false; disarm.stop(); confirmed() }
            else { armed = true; disarm.restart() }
        }
        Timer { id: disarm; interval: 3000; onTriggered: cc.armed = false }
        Binding on text { when: cc.armed; value: cc.confirmText }
    }

    // ── CONTAINER ────────────────────────────────────────────────────────────
    // Rises out of the bottom frame as part of it, laid out like the other
    // drawers: tonal surfaces, no outlines inside, the same type scale.
    FrameDrawer {
        open: popup.active
        onClosed: popup.isAnimating = false
        edge: "bottom"
        duration: 350
        hAlign: "center"
        panelWidth: container.width
        panelHeight: container.height

    Item {
        id: container
        width: Math.min(720, popup.width - 80)
        // Fits four rows of apps exactly under the search field
        height: 2 * PanelStyle.pad + 40 + 46 + 2 * PanelStyle.gap + 400
        // Swallow clicks, so the backdrop only gets the ones outside
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: PanelStyle.pad
            spacing: PanelStyle.gap

            // ── Header: tabs, what the tab holds, capture ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Segmented tabs: a tonal track with a pill sliding under the
                // selected one.
                Rectangle {
                    implicitWidth: tabRow.implicitWidth + 8
                    implicitHeight: 40
                    radius: PanelStyle.radiusControl
                    color: PanelStyle.fieldFill

                    Rectangle {
                        readonly property Item target: tabRepeater.count > popup.activeTab ? tabRepeater.itemAt(popup.activeTab) : null
                        x: 4 + (target ? target.x : 0)
                        y: 4
                        width: target ? target.width : 0
                        height: 32
                        radius: PanelStyle.radiusControl - 3
                        color: Theme.withAlpha(Theme.primary, 0.16)
                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }

                    Row {
                        id: tabRow
                        x: 4; y: 4
                        spacing: 2
                        Repeater {
                            id: tabRepeater
                            model: [
                                { icon: "󰀻", label: "Apps" },
                                { icon: "󰎚", label: "Notes" },
                                { icon: "󰄲", label: "Todo" }
                            ]
                            Item {
                                id: tab
                                required property var modelData
                                required property int index
                                readonly property bool sel: popup.activeTab === index
                                width: tabContent.implicitWidth + 28
                                height: 32
                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tab.modelData.icon
                                        color: Theme.primary
                                        font.pixelSize: 15
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tab.modelData.label
                                        color: Theme.primary
                                        font.pixelSize: 13; font.bold: true
                                    }
                                    opacity: tab.sel ? 1 : (tabMouse.containsMouse ? 0.8 : PanelStyle.dim)
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.openTab(tab.index)
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: popup.activeTab === 0 ? (popup.isCommandMode ? "Runs in Kitty" : appModel.count + " apps")
                        : popup.activeTab === 1 ? (popup.notesDirty ? "Saving…" : popup.notesLoaded ? "Saved" : "")
                        : todoModel.count === 0 ? "" : popup.todoDoneCount + " of " + todoModel.count + " done"
                    color: Theme.primary; opacity: PanelStyle.dim
                    font.pixelSize: PanelStyle.subtitleSize
                    elide: Text.ElideRight
                }

                // Screenshots and recording live in the bottom-right corner now
                IconButton {
                    icon: "󰄀"; size: 32; iconSize: 15
                    onClicked: {
                        popup.active = false
                        Corners.open("capture", popup.screen ? popup.screen.name : Corners.focusedScreen(), true)
                    }
                }
            }

            // ── Content ───────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ════════════════════════════════════════════════════════════
                // APPS
                // ════════════════════════════════════════════════════════════
                ColumnLayout {
                    anchors.fill: parent
                    visible: popup.activeTab === 0
                    spacing: PanelStyle.gap

                    PanelField {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        focused: searchField.activeFocus
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 12
                            spacing: 10
                            Text {
                                text: popup.isCommandMode ? "󰆍" : "󰍉"
                                color: popup.isCommandMode ? Theme.accent : Theme.primary
                                opacity: popup.isCommandMode ? 1 : 0.7
                                font.pixelSize: 17
                            }
                            TextInput {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Theme.primary
                                font.pixelSize: 14
                                selectionColor: Theme.primary; selectedTextColor: Theme.background
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                focus: popup.activeTab === 0 && popup.active
                                onTextChanged: popup.searchText = text
                                Keys.onReturnPressed: {
                                    if (popup.isCommandMode) popup.runCommand()
                                    else if (popup.filteredApps.length > 0)
                                        popup.launch(popup.filteredApps[Math.max(0, appGrid.currentIndex)])
                                }
                                Keys.onEscapePressed: popup.active = false

                                // Arrow keys move over the grid; in command
                                // mode left/right stay with the caret.
                                Keys.onDownPressed: (event) => {
                                    if (!popup.isCommandMode) { appGrid.moveCurrentIndexDown(); event.accepted = true }
                                }
                                Keys.onUpPressed: (event) => {
                                    if (!popup.isCommandMode) { appGrid.moveCurrentIndexUp(); event.accepted = true }
                                }
                                Keys.onRightPressed: (event) => {
                                    if (!popup.isCommandMode) { appGrid.moveCurrentIndexRight(); event.accepted = true }
                                    else event.accepted = false
                                }
                                Keys.onLeftPressed: (event) => {
                                    if (!popup.isCommandMode) { appGrid.moveCurrentIndexLeft(); event.accepted = true }
                                    else event.accepted = false
                                }
                                Keys.onTabPressed: (event) => {
                                    if (!popup.isCommandMode && popup.filteredApps.length > 0) {
                                        appGrid.currentIndex = (appGrid.currentIndex + 1) % popup.filteredApps.length
                                        event.accepted = true
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchField.text.length === 0
                                    text: "Search apps, or type a command"
                                    color: Theme.primary; opacity: PanelStyle.faint
                                    font.pixelSize: 14
                                }
                            }
                            Rectangle {
                                visible: popup.isCommandMode
                                implicitWidth: cmdBadge.implicitWidth + 16
                                implicitHeight: 22
                                radius: 11
                                color: Theme.withAlpha(Theme.accent, 0.18)
                                Text {
                                    id: cmdBadge
                                    anchors.centerIn: parent
                                    text: "Terminal"
                                    color: Theme.accent
                                    font.pixelSize: 10; font.bold: true
                                }
                            }
                            IconButton {
                                visible: searchField.text.length > 0
                                icon: "󰅖"; size: 26; iconSize: 13
                                onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Command mode
                        Column {
                            anchors.centerIn: parent
                            visible: popup.isCommandMode
                            spacing: 14
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰆍"; color: Theme.accent
                                font.pixelSize: 40; opacity: 0.6
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(runLbl.implicitWidth + 36, container.width - 120)
                                height: 44
                                radius: PanelStyle.radiusControl
                                color: runMouse.containsMouse ? PanelStyle.cardHover : PanelStyle.cardFill
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    id: runLbl
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 36)
                                    text: "$ " + popup.searchText
                                    color: Theme.primary
                                    font.pixelSize: 13; font.family: "monospace"
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    id: runMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.runCommand()
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Enter runs it in Kitty"
                                color: Theme.primary; opacity: PanelStyle.faint
                                font.pixelSize: 11
                            }
                        }

                        // Loading / nothing found
                        Column {
                            anchors.centerIn: parent
                            visible: !popup.isCommandMode && (appModel.count === 0
                                     || (popup.filteredApps.length === 0 && popup.searchText.length > 0))
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰍉"; color: Theme.primary
                                font.pixelSize: 36; opacity: 0.2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: appModel.count === 0 ? "Loading apps…" : "No apps found"
                                color: Theme.primary; opacity: PanelStyle.dim
                                font.pixelSize: PanelStyle.bodySize
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: appModel.count > 0
                                text: "Add a space to run it as a command"
                                color: Theme.primary; opacity: PanelStyle.faint
                                font.pixelSize: 11
                            }
                        }

                        GridView {
                            id: appGrid
                            readonly property int cols: Math.max(1, Math.floor(parent.width / 112))
                            anchors.fill: parent
                            visible: !popup.isCommandMode && popup.filteredApps.length > 0
                            clip: true
                            cellWidth: width / cols
                            cellHeight: 100
                            model: popup.filteredApps.length
                            keyNavigationWraps: false
                            highlightMoveDuration: 0
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                id: appCell
                                required property int index
                                readonly property var app: popup.filteredApps[index] || {}
                                readonly property bool current: GridView.isCurrentItem
                                width: appGrid.cellWidth
                                height: appGrid.cellHeight

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: PanelStyle.radiusCard
                                    color: appMouse.containsMouse ? PanelStyle.cardHover
                                         : appCell.current ? PanelStyle.cardFill : "transparent"
                                    border.width: 1
                                    border.color: appCell.current && searchField.text.length > 0
                                        ? PanelStyle.fieldRing : "transparent"
                                    scale: appMouse.pressed ? 0.95 : 1
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                    Column {
                                        anchors.centerIn: parent
                                        width: parent.width - 16
                                        spacing: 8
                                        Item {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 44; height: 44
                                            IconImage {
                                                id: icon
                                                anchors.fill: parent
                                                iconHint: appCell.app.appIcon || ""
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: !icon.ready
                                                radius: PanelStyle.radiusControl
                                                color: PanelStyle.cardFill
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (appCell.app.appName || "?").charAt(0).toUpperCase()
                                                    color: Theme.primary; opacity: 0.6
                                                    font.pixelSize: 18; font.bold: true
                                                }
                                            }
                                        }
                                        Text {
                                            width: parent.width
                                            text: appCell.app.appName || ""
                                            color: Theme.primary
                                            opacity: appMouse.containsMouse || appCell.current ? 1 : 0.8
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Keep the keyboard highlight with the mouse
                                    onContainsMouseChanged: if (containsMouse) appGrid.currentIndex = appCell.index
                                    onClicked: popup.launch(appCell.app)
                                }
                            }
                        }
                    }
                }

                // ════════════════════════════════════════════════════════════
                // NOTES
                // ════════════════════════════════════════════════════════════
                ColumnLayout {
                    anchors.fill: parent
                    visible: popup.activeTab === 1
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: PanelStyle.radiusCard
                        color: notesEdit.activeFocus ? PanelStyle.fieldFocus : PanelStyle.cardFill
                        Behavior on color { ColorAnimation { duration: 150 } }

                        ScrollView {
                            id: notesScroll
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.rightMargin: 8
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            TextEdit {
                                id: notesEdit
                                width: notesScroll.availableWidth - 8
                                color: Theme.primary
                                font.pixelSize: 14
                                wrapMode: TextEdit.Wrap
                                selectionColor: Theme.primary; selectedTextColor: Theme.background
                                focus: popup.activeTab === 1 && popup.active
                                Keys.onEscapePressed: popup.active = false

                                Text {
                                    anchors.fill: parent
                                    visible: notesEdit.text.length === 0
                                    text: "Jot something down…"
                                    color: Theme.primary; opacity: PanelStyle.faint
                                    font.pixelSize: 14
                                }

                                onTextChanged: {
                                    if (!popup.notesLoading) {
                                        popup.notesContent = text
                                        popup.notesDirty = true
                                        notesDebounce.restart()
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            icon: "󰆏"; text: "Copy"
                            enabled: notesEdit.text.length > 0
                            onClicked: Sys.run(["bash", "-c", "printf '%s' \"$1\" | wl-copy", "copy", notesEdit.text])
                        }
                        ConfirmChip {
                            icon: "󰆴"; text: "Clear"
                            confirmText: "Clear the notes?"
                            enabled: notesEdit.text.length > 0
                            onConfirmed: {
                                notesEdit.text = ""
                                popup.notesContent = ""
                                notesWriteProc.write("")
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            readonly property int words: notesEdit.text.trim() === "" ? 0 : notesEdit.text.trim().split(/\s+/).length
                            text: words + (words === 1 ? " word" : " words")
                            color: Theme.primary; opacity: PanelStyle.faint
                            font.pixelSize: 11
                        }
                    }
                }

                // ════════════════════════════════════════════════════════════
                // TODO
                // ════════════════════════════════════════════════════════════
                ColumnLayout {
                    anchors.fill: parent
                    visible: popup.activeTab === 2
                    spacing: 10

                    PanelField {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        focused: todoInput.activeFocus
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 8
                            spacing: 10
                            Text { text: "󰐕"; color: Theme.primary; opacity: 0.7; font.pixelSize: 17 }
                            TextInput {
                                id: todoInput
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Theme.primary
                                font.pixelSize: 14
                                selectionColor: Theme.primary; selectedTextColor: Theme.background
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                focus: popup.activeTab === 2 && popup.active
                                Keys.onReturnPressed: popup.addTodo()
                                Keys.onEnterPressed: popup.addTodo()
                                Keys.onEscapePressed: popup.active = false
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: todoInput.text.length === 0
                                    text: "Add a task"
                                    color: Theme.primary; opacity: PanelStyle.faint
                                    font.pixelSize: 14
                                }
                            }
                            Chip {
                                visible: todoInput.text.trim().length > 0
                                text: "Add"
                                selected: true
                                onClicked: popup.addTodo()
                            }
                        }
                    }

                    // Progress
                    Rectangle {
                        Layout.fillWidth: true
                        visible: todoModel.count > 0
                        implicitHeight: 4
                        radius: 2
                        color: PanelStyle.cardFill
                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: todoModel.count > 0 ? parent.width * popup.todoDoneCount / todoModel.count : 0
                            color: Theme.primary
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    // Empty
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: todoModel.count === 0
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰄲"; color: Theme.primary
                                font.pixelSize: 36; opacity: 0.2
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Nothing to do"
                                color: Theme.primary; opacity: PanelStyle.dim
                                font.pixelSize: PanelStyle.bodySize
                            }
                        }
                    }

                    ListView {
                        id: todoList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: todoModel.count > 0
                        clip: true
                        spacing: 6
                        model: todoModel
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: task
                            required property int index
                            required property string todoText
                            required property bool todoDone
                            width: todoList.width
                            height: 44
                            radius: PanelStyle.radiusControl
                            color: rowHover.hovered ? PanelStyle.cardHover : PanelStyle.cardFill
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler { id: rowHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 8
                                spacing: 12

                                // Check
                                Rectangle {
                                    implicitWidth: 20; implicitHeight: 20
                                    radius: 10
                                    color: task.todoDone ? Theme.primary : "transparent"
                                    border.width: task.todoDone ? 0 : 1.5
                                    border.color: Theme.withAlpha(Theme.primary, checkMouse.containsMouse ? 0.9 : 0.5)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: task.todoDone
                                        text: "󰄬"
                                        color: Theme.background
                                        font.pixelSize: 12; font.bold: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: task.todoText
                                    color: Theme.primary
                                    opacity: task.todoDone ? PanelStyle.faint + 0.1 : 1
                                    font.pixelSize: PanelStyle.bodySize
                                    font.strikeout: task.todoDone
                                    elide: Text.ElideRight
                                }

                                IconButton {
                                    icon: "󰅖"; size: 26; iconSize: 13
                                    opacity: rowHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    onClicked: { todoModel.remove(task.index); popup.saveTodos() }
                                }
                            }

                            // Click the row (not the delete button) to tick it
                            MouseArea {
                                id: checkMouse
                                anchors.fill: parent
                                anchors.rightMargin: 40
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    todoModel.setProperty(task.index, "todoDone", !task.todoDone)
                                    popup.saveTodos()
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: todoModel.count > 0
                        spacing: 6
                        Chip {
                            icon: "󰄬"; text: "Clear done"
                            enabled: popup.todoDoneCount > 0
                            onClicked: {
                                for (let i = todoModel.count - 1; i >= 0; i--)
                                    if (todoModel.get(i).todoDone) todoModel.remove(i)
                                popup.saveTodos()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        ConfirmChip {
                            icon: "󰆴"; text: "Clear all"
                            confirmText: "Remove every task?"
                            onConfirmed: { todoModel.clear(); popup.saveTodos() }
                        }
                    }
                }
            }
        }
    }
    } // FrameDrawer
}
