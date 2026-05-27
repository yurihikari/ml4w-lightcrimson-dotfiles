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
    
    // Allows typing into the popup
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

    // Video Game Wheel Selection States
    property int selectedIndex: -1
    property bool centerHovered: false
    
    // Continuous angle tracks the mouse mathematically to prevent snap-glitching
    // when crossing the 180 / -180 degree boundary.
    property real continuousAngle: 0 

    // Global Floating Phase (Optimized continuous animation)
    // Runs ONLY when menu is visible to save battery/CPU.
    property real globalFloatPhase: 0
    NumberAnimation on globalFloatPhase {
        from: 0; to: 360; duration: 4000
        loops: Animation.Infinite
        running: popup._visible
        easing.type: Easing.Linear 
    }

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
    // ═══════════════════════════════════════════════════════════════════════
    property string _iconBuf: ""
    Process {
        id: iconIndexer
        running: true // Pre-loads icons in background on boot
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

    function resolveIcon(hint) {
        if (!hint) return ""
        if (hint.startsWith("/")) return hint
        if (popup.iconIndex[hint]) return popup.iconIndex[hint]
        return ""
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CURSOR POSITIONING
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

            let safeH = popup.ringRadius + popup.itemSize / 2 + popup.edgePad
            let safeT = safeH + 30 
            // INCREASED bottom padding so the text-input bar never gets cut off
            let safeB = safeH + 110 
            
            if (localX < safeH)                localX = safeH
            if (localX > popup.width  - safeH) localX = popup.width  - safeH
            if (localY < safeT)                localY = safeT
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
        popup.selectedIndex = -1
        popup.centerHovered = false
        popup._visible = true
        popup.active = true
        popup.animProgress = 0
        
        // Reset command input and grab keyboard focus
        cmdInput.text = ""
        focusTimer.restart()
        
        cursorReader.running = true
    }

    // Delay grabbing focus slightly to ensure the window composite is ready
    Timer {
        id: focusTimer
        interval: 30
        onTriggered: cmdInput.forceActiveFocus()
    }

    function beginClose() {
        if (!popup.active) return
        popup.selectedIndex = -1
        popup.centerHovered = false
        popup.active = false
        popup.animProgress = 0
        cmdInput.focus = false // Release keyboard
        closeHideTimer.restart()
    }

    Timer {
        id: closeHideTimer
        interval: 220
        repeat: false
        onTriggered: popup._visible = false
    }

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

    // ═══════════════════════════════════════════════════════════════════════
    //  VIDEO GAME WHEEL LOGIC (GLOBAL MOUSE AREA)
    // ═══════════════════════════════════════════════════════════════════════
    function updateSelection(mx, my) {
        let dx = mx - popup.centerX
        let dy = my - popup.centerY
        let dist = Math.sqrt(dx * dx + dy * dy)

        // Deadzone: If cursor is within 40px of center, highlight the cancel button instead
        if (dist < 40) {
            popup.selectedIndex = -1
            popup.centerHovered = true
            return
        }

        popup.centerHovered = false

        // Calculate angle (-180 to 180 degrees, matching our array formats)
        let angle = Math.atan2(dy, dx) * 180 / Math.PI

        // -- CONTINUOUS ANGLE MATH FOR PLANET ROTATION --
        // This prevents the planets from glitch-snapping when crossing the bottom 180-degree line
        let diff = angle - (popup.continuousAngle % 360)
        if (diff > 180) diff -= 360
        if (diff < -180) diff += 360
        popup.continuousAngle += diff
        
        let minDiff = 999
        let bestIdx = -1

        // Helper to find absolute difference between two angles
        let angleDiff = function(a, b) {
            let d = Math.abs(a - b) % 360
            return d > 180 ? 360 - d : d
        }

        // Check recent apps (Indexes 0-3)
        for (let i = 0; i < popup.recentApps.length; i++) {
            let diff2 = angleDiff(angle, popup.recentAngles[i])
            if (diff2 < minDiff) {
                minDiff = diff2
                bestIdx = i
            }
        }

        // Check frequent apps (Indexes 4-7)
        for (let i = 0; i < popup.frequentApps.length; i++) {
            let diff2 = angleDiff(angle, popup.frequentAngles[i])
            if (diff2 < minDiff) {
                minDiff = diff2
                bestIdx = i + popup.recentApps.length
            }
        }

        popup.selectedIndex = bestIdx
    }

    // Global backdrop captures all hover and clicks
    MouseArea {
        id: globalMouseArea
        anchors.fill: parent
        hoverEnabled: true
        
        // Hide the system cursor so we can draw our own
        cursorShape: Qt.BlankCursor

        onPositionChanged: (mouse) => {
            if (!popup.active) return
            popup.updateSelection(mouse.x, mouse.y)
        }

        onClicked: {
            if (!popup.active) return
            
            if (popup.centerHovered) {
                popup.beginClose()
            } else if (popup.selectedIndex !== -1) {
                // Determine which item was selected via angle
                let isRecent = popup.selectedIndex < popup.recentApps.length
                let item = isRecent 
                    ? popup.recentApps[popup.selectedIndex] 
                    : popup.frequentApps[popup.selectedIndex - popup.recentApps.length]

                if (item) popup.launchAndClose(item.exec, item.name, item.icon)
            } else {
                popup.beginClose()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  RADIAL ITEMS CONNECTING ORBIT RING (FATTER WITH GLOW)
    // ═══════════════════════════════════════════════════════════════════════
    Item {
        z: 0
        width: popup.ringRadius * 2
        height: popup.ringRadius * 2
        x: popup.centerX - popup.ringRadius
        y: popup.centerY - popup.ringRadius

        // Blooms in perfectly with the items
        opacity: popup.animProgress 
        scale: 0.4 + 0.6 * popup.animProgress

        // Outer Glow Ring
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 6
            height: parent.height + 6
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
            border.width: 8
            antialiasing: true
        }

        // Inner Fatter Core Ring
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
            border.width: 3
            antialiasing: true
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  RADIAL ITEM COMPONENT
    // ═══════════════════════════════════════════════════════════════════════
    component RadialItem: Item {
        id: ri
        property int  globalIndex: -1
        property real angleDeg: 0
        property int  staggerIdx: 0
        property string itemName: ""
        property string itemExec: ""
        property string itemIcon: ""
        property bool   isBottom: false

        // Automatically determine hover state from the wheel's selected angle
        property bool hovered: popup.selectedIndex === ri.globalIndex

        width: popup.itemSize
        height: popup.itemSize
        z: hovered ? 100 : 10

        // ─── GEOMETRY MATH ─────────────────────────────────────────────────────
        // Base coordinate without any physics applied
        property real baseCX: popup.centerX + Math.cos(angleDeg * Math.PI / 180) * popup.ringRadius
        property real baseCY: popup.centerY + Math.sin(angleDeg * Math.PI / 180) * popup.ringRadius

        // Distance from item to actual mouse pointer
        property real distX: globalMouseArea.mouseX - baseCX
        property real distY: globalMouseArea.mouseY - baseCY
        property real rawDist: Math.sqrt(distX * distX + distY * distY)

        // ─── MAGNETIC GRAVITY ──────────────────────────────────────────────────
        // Only trigger within 160px. Calculates a 0-to-1 magnet strength.
        property real rawMagnet: popup.active ? Math.max(0, 1 - rawDist / 160) : 0
        
        // We smooth the magnet output so the pulling/releasing looks completely organic
        property real smoothMagnet: Math.pow(rawMagnet, 1.5) // Exponent eases the pull strength curve
        Behavior on smoothMagnet { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        // The exact pixels to shift the item (up to ~35% of the distance)
        property real pullX: distX * smoothMagnet * 0.35
        property real pullY: distY * smoothMagnet * 0.35

        // ─── CONTINUOUS FLOAT (FIGURE 8) ───────────────────────────────────────
        // Mathematical seamless Figure-8 orbit using the globalFloatPhase
        property real floatX: Math.cos((popup.globalFloatPhase + staggerIdx * 45) * Math.PI / 180) * 4
        property real floatY: Math.sin((popup.globalFloatPhase * 2 + staggerIdx * 75) * Math.PI / 180) * 4

        // ─── FINAL CALCULATED TARGET ───────────────────────────────────────────
        property real targetX: baseCX - width / 2 + floatX + pullX
        property real targetY: baseCY - height / 2 + floatY + pullY
        property real centerXAtCenter: popup.centerX - width / 2
        property real centerYAtCenter: popup.centerY - height / 2

        readonly property real localProgress: {
            let staggerOffset = staggerIdx * 0.08
            let p = (popup.animProgress - staggerOffset) / Math.max(0.01, 1 - staggerOffset)
            return Math.max(0, Math.min(1, p))
        }

        x: centerXAtCenter + (targetX - centerXAtCenter) * localProgress
        y: centerYAtCenter + (targetY - centerYAtCenter) * localProgress
        opacity: localProgress
        
        // Base scale bloom + dynamic scaling depending on magnetic gravity proximity!
        scale: (0.4 + 0.6 * localProgress) + (smoothMagnet * localProgress * 0.25)

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
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
                : Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
            border.color: Theme.primary
            border.width: 2
            antialiasing: true
            Behavior on color { ColorAnimation { duration: 140 } }

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
            Text {
                anchors.centerIn: parent
                text: "󰣆"
                color: ri.hovered ? Theme.background : Theme.primary
                font.pixelSize: parent.width * 0.42
                visible: popup.resolveIcon(ri.itemIcon) === ""
            }
        }

        // Floating label
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
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
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  RADIAL LAYOUT
    // ═══════════════════════════════════════════════════════════════════════
    readonly property var recentAngles:   [-160, -120, -60, -20]
    readonly property var frequentAngles: [ 160,  120,  60,  20]

    Repeater {
        model: popup.recentApps
        delegate: RadialItem {
            required property var modelData
            required property int index
            globalIndex: index // Indexes 0 to 3
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
            globalIndex: index + popup.recentApps.length // Indexes 4 to 7
            angleDeg:    popup.frequentAngles[index] || 0
            staggerIdx:  index
            itemName:    modelData.name
            itemExec:    modelData.exec
            itemIcon:    modelData.icon
            isBottom:    true
        }
    }

    // ── CENTER CLOSE BUTTON ───────────────────────────────────────────────
    Rectangle {
        id: centerBtn
        width: 48; height: 48; radius: 24
        x: popup.centerX - width / 2
        y: popup.centerY - height / 2
        color: popup.centerHovered
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
            color: popup.centerHovered ? Theme.background : Theme.primary
            font.pixelSize: 22
            font.bold: true
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  DYNAMIC COMMAND INPUT (Appears on typing)
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: cmdInputBg
        z: 9990
        
        // Dynamically size based on typed text (minimum 220px)
        width: Math.max(220, cmdInput.contentWidth + 60)
        height: 44
        radius: 22
        
        // Position beautifully beneath the radial menu
        x: popup.centerX - width / 2
        y: popup.centerY + popup.ringRadius + 50
        
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95)
        border.color: Theme.primary
        border.width: 2
        
        // Magic visibility triggers
        opacity: cmdInput.text.length > 0 ? 1.0 : 0.0
        scale: cmdInput.text.length > 0 ? 1.0 : 0.8
        
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

        // Icon Prompt
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Theme.primary
            font.pixelSize: 16
        }

        // Invisible text input that always listens
        TextInput {
            id: cmdInput
            anchors.left: parent.left
            anchors.leftMargin: 42
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            
            color: Theme.on_surface
            font.pixelSize: 16
            font.bold: true
            selectionColor: Theme.primary
            selectedTextColor: Theme.background
            
            // Execute the command!
            onAccepted: {
                if (text.trim().length > 0) {
                    popup.launchAndClose(text, "Command", "")
                }
            }
            
            // Escape clears text, or if empty, closes menu
            Keys.onEscapePressed: {
                if (text.length > 0) {
                    text = ""
                } else {
                    popup.beginClose()
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CUSTOM ANIMATED PLANETARY CURSOR
    // ═══════════════════════════════════════════════════════════════════════
    Item {
        id: customCursor
        // 0x0 size ensures x and y perfectly represent the center of the mouse
        width: 0; height: 0 
        x: globalMouseArea.mouseX
        y: globalMouseArea.mouseY
        z: 9999 // Make sure it renders on top of everything else

        // Only show if the popup is visible and the mouse is active on the screen
        visible: popup.active && globalMouseArea.containsMouse
        
        // Sync the scale with the menu opening bloom
        scale: popup.animProgress

        // Prevent the cursor shapes from blocking real mouse clicks
        enabled: false

        // --- Core Glow (Pulsing) ---
        Rectangle {
            anchors.centerIn: parent
            width: 24; height: 24; radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
            
            // Breathe animation for the core glow
            SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation { from: 0.8; to: 1.3; duration: 1000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.3; to: 0.8; duration: 1000; easing.type: Easing.InOutSine }
            }
        }

        // --- Core Solid ---
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; radius: 4
            color: Theme.primary
            border.color: Theme.background
            border.width: 1
        }

        // --- Orbit 1 (Inner, Secondary Color) ---
        Item {
            anchors.centerIn: parent
            width: 34; height: 34
            
            // Tracks the mouse 1:1, points the planet towards the center
            rotation: popup.continuousAngle + 90
            Behavior on rotation { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            // Orbital Ring
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: "transparent"; border.color: Theme.secondary
                border.width: 2; opacity: 0.7
                antialiasing: true
            }

            // Planet Container
            Item {
                width: 8; height: 8
                x: parent.width / 2 - width / 2; y: -height / 2
                
                // Planet Glow Halo
                Rectangle {
                    anchors.centerIn: parent
                    width: 20; height: 20; radius: 10
                    color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
                }
                // Planet Solid
                Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.secondary }
            }
        }

        // --- Orbit 2 (Middle, Tertiary Color) ---
        Item {
            anchors.centerIn: parent
            width: 56; height: 56
            
            // Tracks the mouse in REVERSE, at 1.5x speed
            rotation: -popup.continuousAngle * 1.5 + 45
            Behavior on rotation { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

            // Orbital Ring
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: "transparent"; border.color: Theme.tertiary
                border.width: 1.5; opacity: 0.6
                antialiasing: true
            }

            // Planet Container
            Item {
                width: 10; height: 10
                x: parent.width - width / 2; y: parent.height / 2 - height / 2
                
                // Planet Glow Halo
                Rectangle {
                    anchors.centerIn: parent
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(Theme.tertiary.r, Theme.tertiary.g, Theme.tertiary.b, 0.4)
                }
                // Planet Solid
                Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.tertiary }
            }
        }

        // --- Orbit 3 (Outer, Primary Container Color) ---
        Item {
            anchors.centerIn: parent
            width: 80; height: 80
            
            // Tracks the mouse forward, slightly slower
            rotation: popup.continuousAngle * 0.7 - 45
            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }

            // Orbital Ring
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: "transparent"; border.color: Theme.primary_container
                border.width: 1.5; opacity: 0.5
                antialiasing: true
            }

            // Planet Container
            Item {
                width: 6; height: 6
                x: parent.width / 2 - width / 2; y: parent.height - height / 2
                
                // Planet Glow Halo
                Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16; radius: 8
                    color: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.4)
                }
                // Planet Solid
                Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.primary_container }
            }
        }
    }
}