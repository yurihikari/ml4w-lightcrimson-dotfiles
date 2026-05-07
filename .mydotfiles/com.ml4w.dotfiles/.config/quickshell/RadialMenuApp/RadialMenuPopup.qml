import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../CustomTheme"

// RadialMenuPopup — cursor-positioned 8-icon radial launcher.
//
// Wire-up in ScreenFrame:
//   RadialMenuPopup { id: radial; screen: root.screen }
//
// Hyprland binding (in hyprland.conf):
//   bind = SUPER, R, exec, qs ipc call radialMenu open
//
// User config file: ~/.config/quickshell/radial-menu.json
//   The default file is written automatically on first run. Edit the
//   `recent` and `frequent` arrays (4 entries each). Each entry is:
//     { "name": "Display label", "exec": "bash command", "icon": "iconname-or-path" }
//   The icon can be a freedesktop icon name (e.g. "firefox") or an
//   absolute path. Save and re-open the menu to apply.
PanelWindow {
    id: popup

    property var screen
    screen: popup.screen

    // `active` controls visibility, but with a collapse animation: when
    // set to false we play the bloom-in-reverse, then actually hide the
    // panel via `_visible`.
    property bool active: false
    property bool _visible: false
    visible: _visible

    // Cover the whole screen so we can position the ring anywhere
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: _visible ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // ── GEOMETRY ─────────────────────────────────────────────────────────────
    property real centerX: 0
    property real centerY: 0
    property real ringRadius: 110
    property real itemSize:   60
    property real edgePad:    20

    // ── STATE ────────────────────────────────────────────────────────────────
    property var recentApps:   []
    property var frequentApps: []
    property bool configLoaded: false

    // Icon-name → absolute-path map, populated once on first menu open
    property var iconIndex: ({})
    property bool iconIndexBuilt: false

    // ═══════════════════════════════════════════════════════════════════════
    //  IPC — Hyprland triggers this from a keybind
    // ═══════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "radialMenu"
        function open() { popup.openAtCursor() }
        function close() { popup.beginClose() }
        function toggle() {
            if (popup.active) popup.beginClose()
            else popup.openAtCursor()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONFIG LOADING
    //  Reads ~/.config/quickshell/radial-menu.json. If the file doesn't
    //  exist yet, writes a default one so the user can immediately edit it.
    // ═══════════════════════════════════════════════════════════════════════
    property string _configBuf: ""

    Process {
        id: configReader
        running: true   // load once at startup
        command: ["bash", "-c",
            "f=\"./radial-menu.json\"\n" +
            "mkdir -p \"$(dirname \"$f\")\"\n" +
            "if [ ! -f \"$f\" ]; then\n" +
            "  cat > \"$f\" <<'EOF'\n" +
            "{\n" +
            "  \"_comment\": \"Edit this file to customize your radial menu. Save and reopen the menu to apply. Icons can be a freedesktop name, absolute path, or empty.\",\n" +
            "  \"recent\": [\n" +
            "    { \"name\": \"Files\",    \"exec\": \"nemo\",       \"icon\": \"system-file-manager\" },\n" +
            "    { \"name\": \"Browser\",  \"exec\": \"brave\",    \"icon\": \"brave\" },\n" +
            "    { \"name\": \"Terminal\", \"exec\": \"kitty\",      \"icon\": \"kitty\" },\n" +
            "    { \"name\": \"Editor\",   \"exec\": \"code\",       \"icon\": \"code\" }\n" +
            "  ],\n" +
            "  \"frequent\": [\n" +
            "    { \"name\": \"Settings\", \"exec\": \"nwg-look\",   \"icon\": \"preferences-desktop\" },\n" +
            "    { \"name\": \"Music\",    \"exec\": \"pear-desktop\",    \"icon\": \"pear-desktop\" },\n" +
            "    { \"name\": \"Discord\",  \"exec\": \"vesktop\",    \"icon\": \"discord\" },\n" +
            "    { \"name\": \"System\",   \"exec\": \"kitty -e btop\", \"icon\": \"utilities-system-monitor\" }\n" +
            "  ]\n" +
            "}\n" +
            "EOF\n" +
            "fi\n" +
            "cat \"$f\""
        ]
        stdout: SplitParser { onRead: { popup._configBuf += data + "\n" } }
        onRunningChanged: {
            if (running) return
            try {
                let cfg = JSON.parse(popup._configBuf)
                popup._configBuf = ""
                popup.recentApps   = (cfg.recent   || []).slice(0, 4)
                popup.frequentApps = (cfg.frequent || []).slice(0, 4)
            } catch (e) {
                console.log("RadialMenu: failed to parse config:", e)
            }
            popup.configLoaded = true
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  ICON INDEX BUILDER
    //  One bulk find over icon directories, builds a name→best-path map.
    //  Same approach as DockPopup. Built lazily on first open.
    // ═══════════════════════════════════════════════════════════════════════
    property string _iconBuf: ""
    Process {
        id: iconIndexer
        command: ["bash", "-c",
            "find /usr/share/icons /usr/share/pixmaps \"$HOME/.local/share/icons\" \\\n" +
            "  -type f \\( -name '*.png' -o -name '*.svg' \\) 2>/dev/null \\\n" +
            "  | awk '\n" +
            "      {\n" +
            "        path = $0\n" +
            "        n = split(path, parts, \"/\")\n" +
            "        base = parts[n]\n" +
            "        sub(/\\.(png|svg)$/, \"\", base)\n" +
            "        prio = 0\n" +
            "        if (path ~ /scalable/) prio = 1000\n" +
            "        else if (path ~ /256/)  prio = 900\n" +
            "        else if (path ~ /128/)  prio = 800\n" +
            "        else if (path ~ /64/)   prio = 700\n" +
            "        else if (path ~ /48/)   prio = 600\n" +
            "        else                    prio = 100\n" +
            "        if (path ~ /\\/apps\\//) prio += 50\n" +
            "        if (!(base in best) || prio > bestp[base]) {\n" +
            "          best[base] = path; bestp[base] = prio\n" +
            "        }\n" +
            "      }\n" +
            "      END { for (k in best) print k \"\\t\" best[k] }\n" +
            "    '"
        ]
        stdout: SplitParser { onRead: { popup._iconBuf += data + "\n" } }
        onRunningChanged: {
            if (running) return
            let map = {}
            for (let line of popup._iconBuf.split("\n")) {
                let i = line.indexOf("\t")
                if (i < 1) continue
                map[line.substring(0, i)] = line.substring(i + 1)
            }
            popup._iconBuf = ""
            popup.iconIndex = map
            popup.iconIndexBuilt = true
        }
    }

    // Resolve an icon hint (name or absolute path) to an absolute path
    function resolveIcon(hint) {
        if (!hint) return ""
        if (hint.startsWith("/")) return hint
        if (popup.iconIndex[hint]) return popup.iconIndex[hint]
        return ""
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CURSOR POSITIONING
    //  Read cursor + monitor list via hyprctl, map global → screen-local,
    //  clamp to keep the ring inside screen bounds.
    // ═══════════════════════════════════════════════════════════════════════
    Process {
        id: cursorReader
        property string _buf: ""
        command: ["bash", "-c",
            "set +e\n" +
            "POS=$(hyprctl cursorpos 2>/dev/null)\n" +
            "echo \"cursor=$POS\"\n" +
            "echo \"---monitors---\"\n" +
            "hyprctl monitors -j 2>/dev/null"
        ]
        stdout: SplitParser { onRead: { cursorReader._buf += data + "\n" } }
        onRunningChanged: {
            if (running) return
            let raw = cursorReader._buf
            cursorReader._buf = ""

            let cursorMatch = raw.match(/cursor=\s*(-?\d+)\s*,\s*(-?\d+)/)
            if (!cursorMatch) {
                popup.centerX = popup.width / 2
                popup.centerY = popup.height / 2
                popup.armOpenAnim()
                return
            }
            let gx = parseInt(cursorMatch[1])
            let gy = parseInt(cursorMatch[2])

            let monStart = raw.indexOf("---monitors---")
            let localX = gx, localY = gy
            if (monStart >= 0) {
                let json = raw.substring(monStart + "---monitors---".length).trim()
                try {
                    let mons = JSON.parse(json)
                    for (let m of mons) {
                        let mx = m.x, my = m.y
                        let mw = m.width  / (m.scale || 1)
                        let mh = m.height / (m.scale || 1)
                        if (gx >= mx && gx < mx + mw && gy >= my && gy < my + mh) {
                            if (popup.screen && popup.screen.name && m.name !== popup.screen.name) {
                                popup._visible = false
                                popup.active = false
                                return
                            }
                            localX = gx - mx
                            localY = gy - my
                            break
                        }
                    }
                } catch (e) {}
            }

            // Edge-aware clamping. We add extra padding at the bottom for
            // the FREQUENT label and at the top for RECENT.
            let safeH = popup.ringRadius + popup.itemSize / 2 + popup.edgePad
            let safeT = safeH + 30   // extra room for top label
            let safeB = safeH + 50   // extra room for bottom label + hover labels
            if (localX < safeH)               localX = safeH
            if (localX > popup.width  - safeH) localX = popup.width  - safeH
            if (localY < safeT)               localY = safeT
            if (localY > popup.height - safeB) localY = popup.height - safeB

            popup.centerX = localX
            popup.centerY = localY
            popup.armOpenAnim()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  OPEN / CLOSE FLOW WITH COLLAPSE ANIMATION
    // ═══════════════════════════════════════════════════════════════════════
    function openAtCursor() {
        if (!popup.iconIndexBuilt) iconIndexer.running = true
        popup._visible = true
        popup.active = true
        popup.animProgress = 0
        cursorReader.running = true
    }

    function beginClose() {
        if (!popup.active) return
        popup.active = false           // triggers Behavior on animProgress to ease back to 0
        popup.animProgress = 0
        // Wait for animation to finish before truly hiding the panel
        closeHideTimer.restart()
    }

    Timer {
        id: closeHideTimer
        interval: 220
        repeat: false
        onTriggered: popup._visible = false
    }

    // The bloom driver. 0 = collapsed at center, 1 = fully expanded ring.
    property real animProgress: 0
    Behavior on animProgress {
        NumberAnimation {
            duration: popup.active ? 280 : 200
            easing.type: popup.active ? Easing.OutBack : Easing.InBack
            easing.overshoot: 1.4
        }
    }

    function armOpenAnim() {
        animProgress = 0
        animKickoffTimer.restart()
    }
    Timer {
        id: animKickoffTimer
        interval: 16; repeat: false
        onTriggered: popup.animProgress = 1
    }

    function launchAndClose(exec, name, icon) {
        executor.run(["bash", "-c", exec])
        popup.beginClose()
    }

    Process {
        id: executor
        function run(args) { command = args; running = true }
    }

    // Backdrop click closes
    MouseArea {
        anchors.fill: parent
        onClicked: popup.beginClose()
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  RADIAL ITEM COMPONENT
    // ═══════════════════════════════════════════════════════════════════════
    component RadialItem: Item {
        id: ri
        property real angleDeg: 0
        property int  staggerIdx: 0
        property string itemName: ""
        property string itemExec: ""
        property string itemIcon: ""
        property bool   isBottom: false   // if true, hover label appears ABOVE the item
        property bool   hovered: false

        width: popup.itemSize
        height: popup.itemSize

        // Bring hovered item to the top so its glow + label cover other items
        z: hovered ? 100 : 0

        property real targetX: popup.centerX + Math.cos(angleDeg * Math.PI / 180) * popup.ringRadius - width / 2
        property real targetY: popup.centerY + Math.sin(angleDeg * Math.PI / 180) * popup.ringRadius - height / 2
        property real centerXAtCenter: popup.centerX - width / 2
        property real centerYAtCenter: popup.centerY - height / 2

        // Per-item progress, staggered for the bloom cascade
        readonly property real localProgress: {
            let staggerOffset = staggerIdx * 0.08
            let p = (popup.animProgress - staggerOffset) / Math.max(0.01, 1 - staggerOffset)
            return Math.max(0, Math.min(1, p))
        }

        x: centerXAtCenter + (targetX - centerXAtCenter) * localProgress
        y: centerYAtCenter + (targetY - centerYAtCenter) * localProgress
        opacity: localProgress
        scale:   0.4 + 0.6 * localProgress

        // Soft glow halo on hover
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width  + 24
            height: parent.height + 24
            radius: width / 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, ri.hovered ? 0.30 : 0.0)
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        // The circle — glass background by default, Theme.primary fill on hover
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ri.hovered
                ? Theme.primary
                : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
            border.color: Theme.primary
            border.width: 2
            antialiasing: true
            Behavior on color { ColorAnimation { duration: 140 } }

            // Icon — uses the resolved absolute path from the icon index
            Image {
                anchors.centerIn: parent
                width:  parent.width * 0.50
                height: parent.width * 0.50
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                property string resolved: popup.resolveIcon(ri.itemIcon)
                source: resolved !== "" ? "file://" + resolved : ""
                visible: status === Image.Ready
            }
            // Fallback glyph when icon resolution fails
            Text {
                anchors.centerIn: parent
                text: "󰣆"
                color: ri.hovered ? Theme.background : Theme.primary
                font.pixelSize: parent.width * 0.42
                visible: popup.resolveIcon(ri.itemIcon) === ""
            }
        }

        // Floating label — appears ABOVE for bottom items, BELOW for top items,
        // so it never gets covered by adjacent items in the same group.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            // Switch position based on which half the item lives in
            anchors.bottom: ri.isBottom ? parent.top : undefined
            anchors.bottomMargin: ri.isBottom ? 8 : 0
            anchors.top: ri.isBottom ? undefined : parent.bottom
            anchors.topMargin: ri.isBottom ? 0 : 8

            width: lblText.implicitWidth + 16
            height: 22; radius: 11
            color: Theme.primary
            opacity: ri.hovered ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Text {
                id: lblText
                anchors.centerIn: parent
                text: ri.itemName
                color: Theme.background
                font.pixelSize: 11; font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: ri.hovered = true
            onExited:  ri.hovered = false
            onClicked: popup.launchAndClose(ri.itemExec, ri.itemName, ri.itemIcon)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  RADIAL LAYOUT
    //  Top half (recent): NW → NE arc
    //  Bottom half (frequent): SE → SW arc
    // ═══════════════════════════════════════════════════════════════════════
    readonly property var recentAngles:   [-160, -120, -60, -20]   // top
    readonly property var frequentAngles: [ 160,  120,  60,  20]   // bottom

    Repeater {
        model: popup.recentApps
        delegate: RadialItem {
            required property var modelData
            required property int index
            angleDeg:    popup.recentAngles[index] || 0
            staggerIdx:  index
            itemName:    modelData.name
            itemExec:    modelData.exec
            itemIcon:    modelData.icon
            isBottom:    false
        }
    }

    Repeater {
        model: popup.frequentApps
        delegate: RadialItem {
            required property var modelData
            required property int index
            angleDeg:    popup.frequentAngles[index] || 0
            staggerIdx:  index
            itemName:    modelData.name
            itemExec:    modelData.exec
            itemIcon:    modelData.icon
            isBottom:    true   // labels render ABOVE the item, not below
        }
    }

    // ── CENTER CLOSE BUTTON ───────────────────────────────────────────────
    Rectangle {
        id: centerBtn
        width: 48; height: 48; radius: 24
        x: popup.centerX - width / 2
        y: popup.centerY - height / 2
        color: closeHover.containsMouse
            ? Theme.primary
            : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
        border.color: Theme.primary
        border.width: 2
        opacity: animProgress
        scale: 0.4 + 0.6 * animProgress
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "󰅖"
            color: closeHover.containsMouse ? Theme.background : Theme.primary
            font.pixelSize: 22
            font.bold: true
        }

        MouseArea {
            id: closeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.beginClose()
        }
    }
}
