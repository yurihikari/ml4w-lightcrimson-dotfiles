import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.components
import qs.BarApp.services
import qs.AssistantApp.services
import qs.AssistantApp.components

// AI assistant (META+SHIFT+SPACE): a chat drawer on the right, backed by the
// Claude CLI (services/Assistant.qml). "Assistant" is a plain assistant;
// "Personal" talks as one of the user's own assistants, made with the form
// here (name, what they call you, personality: Claude writes their lines) and
// kept in ~/.local/share/ml4w-assistant/personas/. When one has character
// files, the character stands next to the panel: click it to make it talk,
// pat its head to see it react (character/).
//
// It is a FrameDrawer like the sidebar, so each theme draws it its own way
// (out of the frame in LightCrimson, a floating plate in the BA themes). It
// only takes input over the panel itself, so the character and the windows
// stay clickable while it's open; Esc or the close button hides it.
//
// It can also float: a card dragged by its header, with the character
// following it, that stays open while other popups come and go. Opening
// another popup (by hand or by the assistant, which can drive the desktop)
// makes it float instead of closing; the dock button puts it back.
PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }

    // Sizes: resizable (the left edge docked, the sides and bottom corners
    // floating), kept in state.json
    readonly property real minWidth: 340
    readonly property real minHeight: 360
    property real dockWidth: Assistant.ui.dockWidth || PanelStyle.narrowWidth
    property real floatW: Assistant.ui.floatWidth || PanelStyle.narrowWidth
    property real floatH: Assistant.ui.floatHeight || 780
    readonly property real panelWidth: floating ? floatW : dockWidth
    property bool isOpen: false
    property bool animating: false
    visible: isOpen || animating
    // Input only over the panel. Floating, the region is computed from the
    // card's position: a Region following the card item kept the spot where
    // the card was, so after a drag its header was out of it.
    mask: floating ? floatRegion : dockRegion
    property Region dockRegion: Region { item: body }
    property Region floatRegion: Region { x: root.floatX; y: root.floatY; width: root.floatW; height: root.floatH }

    // ── Monitor ──
    // It opens on the focused monitor, and a floating card dropped on another
    // monitor moves there (see dropFloat). Only while no drawer is out: the
    // frame's corners and shadow are per monitor.
    function screenNamed(name) {
        for (const s of Quickshell.screens) if (s.name === name) return s
        return null
    }
    function moveToScreen(s) {
        if (!s || s === root.screen) return false
        root.screen = s
        return true
    }
    // Asks Hyprland where the cursor is: the pointer leaves this monitor's
    // surface on the way to another one. Run while the drag crosses the edge
    // and when it ends.
    Process {
        id: cursorPos
        command: ["hyprctl", "cursorpos", "-j"]
        property real grabX: 0               // where the card is held
        property real grabY: 0
        stdout: StdioCollector {
            onStreamFinished: {
                let c; try { c = JSON.parse(this.text) } catch (e) { return }
                root.dropFloat(c.x, c.y, cursorPos.grabX, cursorPos.grabY)
            }
        }
    }
    function checkMonitor() { if (!cursorPos.running) cursorPos.running = true }
    // The cursor is at (gx, gy), in the layout: if that's on another
    // monitor, the card goes there, under the cursor where it was held
    function dropFloat(gx, gy, grabX, grabY) {
        let target = null
        for (const s of Quickshell.screens)
            if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height) target = s
        if (!target || target === root.screen || !floating) return
        // The window is recreated on the other monitor: the drag can't go on
        dragger.enabled = false
        Qt.callLater(() => dragger.enabled = true)
        _pendingPos = Qt.point(gx - target.x - grabX, gy - target.y - grabY)
        moveToScreen(target)
        Qt.callLater(_settle)
    }

    // ── Floating ──
    property bool floating: false
    property real floatX: -1                 // remembered while the shell runs
    property real floatY: -1
    function detach() {
        if (floatX < 0) {                    // first time: left of where the right-side drawers open
            floatX = areaW - dockWidth - floatW - 60
            floatY = Math.round((areaH - floatH) / 2) + 10
        }
        fitFloat()
        moveFloat(floatX, floatY)
        floating = true
    }
    function dock() { floating = false }
    // The monitor's size. Not the window's: while the window moves to
    // another monitor it has a temporary size (500x500 or so), and fitting
    // the card into that shrank it and pushed it into the corner.
    readonly property real areaW: screen && screen.width > 0 ? screen.width : width
    readonly property real areaH: screen && screen.height > 0 ? screen.height : height
    function moveFloat(x, y) {
        if (areaW <= 0 || areaH <= 0) { _pendingPos = Qt.point(x, y); return }
        floatX = Math.round(Math.max(8, Math.min(areaW - floatW - 8, x)))
        floatY = Math.round(Math.max(8, Math.min(areaH - floatH - 8, y)))
    }
    property var _pendingPos: null
    // Once the window has its size (after opening or changing monitor): fit
    // the card in and put it where it should be
    function _settle() {
        if (!floating || areaW <= 0 || areaH <= 0) return
        fitFloat()
        const p = _pendingPos || Qt.point(floatX, floatY)
        _pendingPos = null
        moveFloat(p.x, p.y)
        placeCharacter()
    }
    // Keep the card's size within the monitor (a smaller one, after a move)
    function fitFloat() {
        if (areaW <= 0 || areaH <= 0) return
        floatW = Math.round(Math.max(minWidth, Math.min(areaW - 16, floatW)))
        floatH = Math.round(Math.max(minHeight, Math.min(areaH - 16, floatH)))
    }
    onAreaWChanged: _settle()
    onAreaHChanged: _settle()
    // Resizing the card from one of its grips. edges: 1 left, 2 right, 4 bottom
    function resizeFloat(edges, start, dx, dy) {
        let x = start.x, w = start.width, h = start.height
        if (edges & 2) w = start.width + dx
        if (edges & 1) w = start.width - dx
        if (edges & 4) h = start.height + dy
        w = Math.max(minWidth, Math.min(edges & 1 ? start.x + start.width - 8 : areaW - start.x - 8, w))
        h = Math.max(minHeight, Math.min(areaH - start.y - 8, h))
        if (edges & 1) x = start.x + start.width - w
        floatW = Math.round(w); floatH = Math.round(h); floatX = Math.round(x)
    }
    function saveSizes() {
        Assistant.setUi({ dockWidth: Math.round(dockWidth), floatWidth: Math.round(floatW), floatHeight: Math.round(floatH) })
    }
    onFloatingChanged: {
        if (!floating && isOpen) {
            animating = true                 // the drawer slides back out
            FrameState.claim("assistant")
        }
        placeCharacter()
        focusTimer.restart()
    }

    // The character stands left of the panel, docked or floating
    function placeCharacter() {
        if (floating) Assistant.placeCharacter(areaW - floatX + 6, areaH - floatY - floatH, root.screen)
        else Assistant.placeCharacter(dockWidth + 16, 10, root.screen)
    }
    Timer { id: placeThrottle; interval: 33; onTriggered: root.placeCharacter() }
    onFloatXChanged: if (floating && !placeThrottle.running) placeThrottle.start()
    onFloatYChanged: if (floating && !placeThrottle.running) placeThrottle.start()
    onFloatHChanged: if (floating && !placeThrottle.running) placeThrottle.start()
    onDockWidthChanged: if (!floating && !placeThrottle.running) placeThrottle.start()

    onIsOpenChanged: {
        if (isOpen) {
            // Open on the focused monitor (it stays where it is while floating)
            if (!animating && Hyprland.focusedMonitor) moveToScreen(screenNamed(Hyprland.focusedMonitor.name))
            animating = true
            if (!floating) FrameState.claim("assistant")
            focusTimer.restart()
        } else {
            floating = false
        }
        placeCharacter()
        Assistant.showCharacter(isOpen)
    }
    // Another drawer opens: float next to it rather than close
    Connections {
        target: FrameState
        function onClaimed(k) { if (k !== "assistant" && root.isOpen && !root.floating) root.detach() }
    }
    // It wants to do something that needs an OK: make sure it's seen
    Connections {
        target: Assistant
        function onApprovalRequested() { if (!root.isOpen) root.isOpen = true }
    }

    IpcHandler {
        target: "assistant"
        function toggle(): void { root.isOpen = !root.isOpen }
        function open(): void { root.isOpen = true }
        function close(): void { root.isOpen = false }
        // Open and send a message right away
        function ask(text: string): void { root.isOpen = true; Assistant.send(text) }
        function mode(m: string): void { if (m === "special") m = "personal"; if (m === "assistant" || m === "personal") Assistant.mode = m }
        // Open the form for a new personal assistant
        function create(): void { root.isOpen = true; root.edit("") }
        // Make one without the form (Claude writes its lines): name, what it
        // calls you (may be empty), personality
        function make(name: string, addressAs: string, personality: string): string {
            const id = Assistant.savePersona("", { name: name, addressAs: addressAs, personality: personality })
            Assistant.personalPersona = id; Assistant.mode = "personal"
            return id
        }
        // Start a new chat with the current persona
        function clear(): void { Assistant.newChat() }
        // Debug: fake a tap ("head", "body") or a pat on the character
        function poke(kind: string): void { Assistant.pokeCharacter(kind) }
        // Delete a personal assistant (its character files are kept)
        function remove(id: string): void { Assistant.deletePersona(id) }
        function persona(id: string): void { if (Assistant.personalPersonas.includes(id)) { Assistant.personalPersona = id; Assistant.mode = "personal" } }
        // Attach a file or an image to the next message (opens the panel)
        function attach(path: string): void { root.isOpen = true; Assistant.attach(path) }
        // Float it (it stays open with other popups), or put it back
        function detach(): void { root.isOpen = true; root.detach() }
        function dock(): void { root.dock() }
        // Answer the first pending request (what the Allow / Deny buttons do)
        // (or the one waiting in the Remote Control session)
        function allow(): void {
            if (Assistant.approvals.count) Assistant.answer(Assistant.approvals.get(0).requestId, true, false)
            else Assistant.remoteAnswer(true)
        }
        function deny(): void {
            if (Assistant.approvals.count) Assistant.answer(Assistant.approvals.get(0).requestId, false, false)
            else Assistant.remoteAnswer(false)
        }
    }

    Timer { id: focusTimer; interval: 120; onTriggered: if (root.editing === null) input.forceActiveFocus() }

    // The form: null while chatting, else the fields being edited ("" id: new)
    property var editing: null
    property string editingId: ""
    function edit(id) {
        const p = id ? (Assistant.personas[id] || {}) : {}
        editingId = id
        editing = { name: p.name || "", icon: p.icon || "", tagline: p.tagline || "",
                    addressAs: p.addressAs || "", personality: p.personality || "" }
        confirmDelete = false
        Qt.callLater(() => nameFieldBox.field.forceActiveFocus())
    }
    property bool confirmDelete: false
    readonly property bool showOnboarding: editing === null && Assistant.mode === "personal" && Assistant.personalPersonas.length === 0

    FrameDrawer {
        open: root.isOpen && !root.floating
        onClosed: root.animating = false
        edge: "right"
        panelWidth: root.dockWidth
        duration: 350

        Item { id: drawerSlot; anchors.fill: parent }
    }

    // ── The floating card ──
    Item {
        id: floatCard
        visible: root.floating && root.isOpen
        x: root.floatX; y: root.floatY
        width: root.floatW; height: root.floatH

        readonly property real radius: PanelStyle.radiusWindow !== undefined ? PanelStyle.radiusWindow : 20
        Shadow { radius: floatCard.radius }
        Rectangle {
            anchors.fill: parent
            radius: floatCard.radius
            color: PanelStyle.windowFill !== undefined ? PanelStyle.windowFill : Theme.withAlpha(Theme.background, 0.92)
            border.color: PanelStyle.windowBorder !== undefined ? PanelStyle.windowBorder : Theme.withAlpha(Theme.primary, 0.3)
            border.width: 1
        }
        // Drag it by the header. Under the content: the header's buttons take
        // their clicks first, and only presses on the rest of the header
        // (title, icon, empty space) fall through to here.
        Item {
            width: parent.width
            height: PanelStyle.pad + PanelStyle.headerHeight
            DragHandler {
                id: dragger
                target: null
                property real startX: 0
                property real startY: 0
                onActiveChanged: {
                    if (active) {
                        startX = root.floatX; startY = root.floatY
                        cursorPos.grabX = centroid.scenePressPosition.x - startX
                        cursorPos.grabY = centroid.scenePressPosition.y - startY
                    } else {
                        root.checkMonitor()      // dropped on another monitor?
                    }
                }
                onCentroidChanged: {
                    if (!active) return
                    const p = centroid.scenePosition
                    root.moveFloat(startX + p.x - centroid.scenePressPosition.x,
                                   startY + p.y - centroid.scenePressPosition.y)
                    // The pointer left this monitor: follow it right away
                    if (p.x < 0 || p.y < 0 || p.x >= root.areaW || p.y >= root.areaH) root.checkMonitor()
                }
            }
            HoverHandler { cursorShape: dragger.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
        }
        Item { id: floatSlot; anchors.fill: parent }

        // Resize: the sides and the bottom corners (the header moves it)
        ResizeGrip { win: root; edges: 1; x: 0; y: 24; width: 6; height: parent.height - 24 - 16 }
        ResizeGrip { win: root; edges: 2; x: parent.width - 6; y: 24; width: 6; height: parent.height - 24 - 16 }
        ResizeGrip { win: root; edges: 4; x: 16; y: parent.height - 6; width: parent.width - 32; height: 6 }
        ResizeGrip { win: root; edges: 5; x: 0; y: parent.height - 16; width: 16; height: 16 }
        ResizeGrip { win: root; edges: 6; x: parent.width - 16; y: parent.height - 16; width: 16; height: 16 }
    }

    // The panel's content: in the drawer, or in the floating card
    Item {
        id: body
        parent: root.floating ? floatSlot : drawerSlot
        anchors.fill: parent

        Keys.onEscapePressed: root.isOpen = false

        // Files dropped on the panel are attached
        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (d) => {
                for (const u of d.urls) Assistant.attach(decodeURIComponent(u.toString()))
                d.acceptProposedAction()
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            z: 20
            visible: drop.containsDrag
            radius: PanelStyle.radiusCard
            color: Theme.withAlpha(Theme.primary, 0.12)
            border.color: Theme.primary; border.width: 2
            Text {
                anchors.centerIn: parent
                text: "Drop to attach"
                color: Theme.primary
                font.family: Theme.fontFamily; font.pixelSize: PanelStyle.titleSize; font.bold: true
            }
        }

        // Docked: drag the inner (left) edge to make it wider or narrower
        ResizeGrip { win: root; visible: !root.floating; edges: 1; x: 0; y: 0; width: 6; height: parent.height }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: PanelStyle.pad
            spacing: PanelStyle.gap

            // ── Header ──
            PanelHeader {
                icon: Assistant.persona.icon || "󰚩"
                title: Assistant.persona.name || "Assistant"
                subtitle: Assistant.drafting === Assistant.personaId && Assistant.drafting !== "" ? "Writing their lines…"
                    : Assistant.remoteStatus !== "" ? Assistant.remoteStatus
                    : Assistant.busy ? (Assistant.status || "Thinking…")
                    // Context size of this conversation: past ~100k, each call gets expensive
                    : Assistant.contextTokens > 0 ? Math.round(Assistant.contextTokens / 1000) + "k context"
                        + (Assistant.effort !== "" && Assistant.effort !== "medium" ? " · " + Assistant.effort : "")
                        + (Assistant.contextTokens > 100000 ? " · long: /handoff" : "")
                    : (Assistant.persona.tagline || "")

                // Show or hide the character next to the panel (kept in state.json)
                IconButton {
                    icon: Assistant.characterHidden ? "󰈉" : "󰈈"; size: 30; iconSize: 15
                    visible: Assistant.mode === "personal" && Assistant.canChat && root.editing === null
                        && (Assistant.characterAvailable || Assistant.characterHidden)
                    onClicked: Assistant.characterHidden = !Assistant.characterHidden
                    ToolTip.visible: hovered; ToolTip.delay: 500
                    ToolTip.text: Assistant.characterHidden ? "Show the character" : "Hide the character"
                }
                IconButton {
                    icon: "󰏫"; size: 30; iconSize: 15
                    visible: Assistant.mode === "personal" && Assistant.canChat && root.editing === null
                    onClicked: root.edit(Assistant.personaId)
                    ToolTip.visible: hovered; ToolTip.delay: 500; ToolTip.text: "Edit this assistant"
                }
                IconButton {
                    icon: root.floating ? "󱂫" : "󰏌"; size: 30; iconSize: 15
                    onClicked: root.floating ? root.dock() : root.detach()
                    ToolTip.visible: hovered; ToolTip.delay: 500
                    ToolTip.text: root.floating ? "Put it back" : "Float (stays open with other popups)"
                }
                IconButton {
                    icon: "󰐕"; size: 30; iconSize: 15
                    enabled: Assistant.messages.count > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: Assistant.newChat()
                    ToolTip.visible: hovered; ToolTip.delay: 500; ToolTip.text: "New chat"
                }
                IconButton {
                    icon: "󰅖"; size: 30; iconSize: 15
                    onClicked: root.isOpen = false
                }
            }

            // ── Mode: plain assistant or one of the user's own ──
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Chip {
                    icon: "󰚩"; text: "Assistant"
                    selected: Assistant.mode === "assistant"
                    onClicked: { Assistant.mode = "assistant"; root.editing = null }
                }
                Chip {
                    icon: "󰀄"; text: "Personal"
                    selected: Assistant.mode === "personal"
                    onClicked: Assistant.mode = "personal"
                }
                Rectangle {
                    visible: Assistant.mode === "personal" && Assistant.personalPersonas.length > 0
                    width: 1; height: 18; y: 5
                    color: PanelStyle.divider
                }
                Repeater {
                    model: Assistant.mode === "personal" ? Assistant.personalPersonas : []
                    Chip {
                        required property string modelData
                        text: (Assistant.personas[modelData] || {}).name || modelData
                        selected: Assistant.personalPersona === modelData && root.editing === null
                        onClicked: { Assistant.personalPersona = modelData; root.editing = null }
                    }
                }
                Chip {
                    visible: Assistant.mode === "personal" && Assistant.personalPersonas.length > 0
                    icon: "󰐕"; text: "New"
                    selected: root.editing !== null && root.editingId === ""
                    onClicked: root.edit("")
                }
            }

            // No character files for this assistant: say where they go
            Text {
                Layout.fillWidth: true
                visible: Assistant.mode === "personal" && Assistant.canChat && root.editing === null && !Assistant.characterAvailable
                text: "No character files for " + (Assistant.persona.name || "") + ". Add a Spine export to ~/.local/share/ml4w-assistant/characters/" + Assistant.personaId + "/ to see them here."
                wrapMode: Text.Wrap
                color: Theme.primary; opacity: PanelStyle.faint
                font.pixelSize: PanelStyle.labelSize + 1
            }

            // ── No personal assistant yet ──
            ColumnLayout {
                visible: root.showOnboarding
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰀄"; color: Theme.primary; opacity: 0.5; font.pixelSize: 44
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Make your own assistant"
                    color: Theme.primary; font.pixelSize: PanelStyle.titleSize; font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Give them a name and a personality, and Claude writes the rest. "
                        + "You can change them any time here, or edit their file in ~/.local/share/ml4w-assistant/personas/."
                    color: Theme.primary; opacity: PanelStyle.dim
                    font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize
                }
                PanelButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    accent: true; icon: "󰐕"; text: "Create an assistant"
                    onClicked: root.edit("")
                }
                Item { Layout.fillHeight: true }
            }

            // ── The form: create or edit a personal assistant ──
            Flickable {
                id: formView
                visible: root.editing !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: form.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: form
                    width: formView.width - 8
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: root.editingId === "" ? "New assistant" : "Edit " + ((Assistant.personas[root.editingId] || {}).name || "")
                        color: Theme.primary; font.pixelSize: PanelStyle.titleSize - 1; font.bold: true
                    }

                    FieldLabel { text: "Name" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        FormField {
                            Layout.preferredWidth: 56
                            Layout.fillWidth: false
                            text: root.editing ? root.editing.icon : ""
                            placeholder: (nameFieldBox.text.trim().charAt(0) || "A").toUpperCase()
                            field.horizontalAlignment: TextInput.AlignHCenter
                            field.maximumLength: 4
                            onTextChanged: if (root.editing) root.editing.icon = text
                            ToolTip.visible: field.activeFocus; ToolTip.text: "Icon: a letter, an emoji or a Nerd Font glyph"
                        }
                        FormField {
                            id: nameFieldBox
                            text: root.editing ? root.editing.name : ""
                            placeholder: "Nova, Mika, Jarvis…"
                            onTextChanged: if (root.editing) root.editing.name = text
                        }
                    }

                    FieldLabel { text: "What do they call you?" }
                    FormField {
                        text: root.editing ? root.editing.addressAs : ""
                        placeholder: "Your name, \"Boss\", \"Captain\"… (optional)"
                        onTextChanged: if (root.editing) root.editing.addressAs = text
                    }

                    FieldLabel { text: "Personality" }
                    PanelField {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(110, personality.implicitHeight + 16)
                        focused: personality.activeFocus
                        TextArea {
                            id: personality
                            anchors.fill: parent; anchors.margins: 4
                            text: root.editing ? root.editing.personality : ""
                            placeholderText: "How they behave and talk. E.g. cheerful and a bit clumsy, loves sweets, lots of exclamation marks; or calm, precise and dry, with a hidden soft side."
                            placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
                            color: Theme.primary
                            wrapMode: TextArea.Wrap
                            background: null
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                            onTextChanged: if (root.editing) root.editing.personality = text
                        }
                    }

                    FieldLabel { text: "Tagline" }
                    FormField {
                        text: root.editing ? root.editing.tagline : ""
                        placeholder: "Shown under their name (optional)"
                        onTextChanged: if (root.editing) root.editing.tagline = text
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        wrapMode: Text.Wrap
                        text: (root.editingId === ""
                                ? "After you save, Claude writes their lines: greetings, and what they say when clicked or patted. "
                                : Assistant.isExample(root.editingId)
                                ? "This one comes from the examples: saving makes it your own copy, which you can then change freely. "
                                : "")
                            + "Everything is in ~/.local/share/ml4w-assistant/personas/"
                            + (root.editingId || Assistant.slug(root.editing ? root.editing.name : "")) + ".json, "
                            + "and a character can go in ~/.local/share/ml4w-assistant/characters/"
                            + (root.editingId || Assistant.slug(root.editing ? root.editing.name : "")) + "/ (see the README)."
                        color: Theme.primary; opacity: PanelStyle.faint
                        font.pixelSize: PanelStyle.labelSize + 1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8
                        PanelButton {
                            accent: true; icon: "󰆓"; text: "Save"
                            enabled: root.editing !== null && root.editing.name.trim() !== ""
                            onClicked: {
                                const id = Assistant.savePersona(root.editingId, root.editing)
                                Assistant.personalPersona = id
                                Assistant.mode = "personal"
                                root.editing = null
                                focusTimer.restart()
                            }
                        }
                        PanelButton {
                            text: "Cancel"
                            onClicked: { root.editing = null; focusTimer.restart() }
                        }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            visible: root.editingId !== "" && !Assistant.isExample(root.editingId)
                            icon: "󰈔"; size: 30; iconSize: 14
                            onClicked: Qt.openUrlExternally("file://" + Assistant.personaFile(root.editingId))
                            ToolTip.visible: hovered; ToolTip.delay: 400; ToolTip.text: "Open the file"
                        }
                        IconButton {
                            visible: root.editingId !== ""
                            icon: "󰑓"; size: 30; iconSize: 14
                            enabled: Assistant.drafting === ""
                            opacity: enabled ? 1 : 0.4
                            onClicked: Assistant.draftLines(root.editingId, Assistant.personas[root.editingId] || root.editing)
                            ToolTip.visible: hovered; ToolTip.delay: 400; ToolTip.text: "Rewrite their lines with Claude"
                        }
                        PanelButton {
                            visible: root.editingId !== "" && !Assistant.isExample(root.editingId)
                            danger: true
                            icon: "󰆴"; text: root.confirmDelete ? "Sure?" : "Delete"
                            onClicked: {
                                if (!root.confirmDelete) { root.confirmDelete = true; return }
                                Assistant.deletePersona(root.editingId)
                                root.editing = null
                            }
                        }
                    }
                }
            }

            // ── Conversation ──
            Item {
                visible: root.editing === null && !root.showOnboarding
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Empty: the persona's greeting
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: Assistant.messages.count === 0
                    spacing: 10
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Assistant.persona.icon || "󰚩"
                        color: Theme.primary; opacity: 0.5
                        font.pixelSize: 44
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ((Assistant.persona.lines || {}).greet || ["How can I help?"])[0]
                        wrapMode: Text.Wrap
                        color: Theme.primary; opacity: PanelStyle.dim
                        font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                    }
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    spacing: 10
                    model: Assistant.messages
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    // Follow the reply while it streams, unless scrolled up
                    property bool follow: true
                    onMovementEnded: follow = atYEnd
                    onContentHeightChanged: if (follow) Qt.callLater(positionViewAtEnd)
                    onCountChanged: { follow = true; Qt.callLater(positionViewAtEnd) }

                    delegate: Item {
                        id: msg
                        required property string role
                        required property string text
                        required property bool streaming
                        required property string files
                        readonly property var fileList: { try { return files ? JSON.parse(files) : [] } catch (e) { return [] } }
                        readonly property bool mine: role === "user"
                        readonly property real maxW: list.width - (mine ? 48 : 0)
                        // A tool it used: "tool:<name>", ":err" when it failed or was denied
                        readonly property bool isTool: role.startsWith("tool:")
                        readonly property string toolName: isTool ? role.split(":")[1] : ""
                        readonly property bool toolFailed: role.endsWith(":err")
                        width: list.width
                        height: role === "note" || role === "info" ? noteText.implicitHeight + 4
                              : isTool ? toolRow.implicitHeight + 2 : bubble.height

                        RowLayout {
                            id: toolRow
                            visible: msg.isTool
                            width: parent.width
                            spacing: 8
                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: msg.toolName === "Bash" ? (msg.text.indexOf("/screenshot") >= 0 ? "󰹑" : "󰆍")
                                    : msg.toolName === "Read" ? "󰈔"
                                    : msg.toolName === "Grep" || msg.toolName === "Glob" ? "󰍉"
                                    : msg.toolName === "Edit" || msg.toolName === "Write" ? "󰏫"
                                    : "󰖟"
                                color: msg.toolFailed ? Theme.error : Theme.primary
                                opacity: msg.toolFailed ? 0.9 : PanelStyle.dim
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: msg.text
                                color: msg.toolFailed ? Theme.error : Theme.primary
                                opacity: msg.toolFailed ? 0.9 : PanelStyle.dim
                                font.family: "monospace"; font.pixelSize: PanelStyle.labelSize + 1
                                font.strikeout: msg.toolFailed
                                wrapMode: Text.WrapAnywhere
                                // 3 lines; click to see all of it
                                maximumLineCount: toolRow.expanded ? 10000 : 3
                                elide: Text.ElideRight
                            }
                            property bool expanded: false
                            TapHandler { onTapped: toolRow.expanded = !toolRow.expanded }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }

                        // A note (an error) or an info line (/rc, /help…)
                        Text {
                            id: noteText
                            visible: msg.role === "note" || msg.role === "info"
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: msg.text
                            textFormat: msg.role === "info" ? Text.MarkdownText : Text.PlainText
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            color: msg.role === "info" ? Theme.primary : Theme.error
                            opacity: msg.role === "info" ? PanelStyle.dim : 1
                            linkColor: Theme.primary
                            font.pixelSize: PanelStyle.labelSize + 2
                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                            HoverHandler { cursorShape: noteText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        }

                        // Measures a user message, so its bubble fits it
                        Text {
                            id: measure
                            visible: false
                            text: msg.text
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                        }

                        // A reply in pieces: Markdown text, and code blocks
                        // in boxes with a Copy button (Assistant.segments).
                        // Kept in a model updated in place, so a streaming
                        // reply only changes its last piece.
                        ListModel { id: segModel }
                        function syncSegments() {
                            const segs = msg.mine || msg.isTool || msg.role === "note" ? [] : Assistant.segments(msg.text)
                            for (let i = 0; i < segs.length; i++) {
                                if (i >= segModel.count) { segModel.append(segs[i]); continue }
                                const cur = segModel.get(i)
                                if (cur.kind !== segs[i].kind) { segModel.set(i, segs[i]); continue }
                                if (cur.text !== segs[i].text) segModel.setProperty(i, "text", segs[i].text)
                                if (cur.lang !== segs[i].lang) segModel.setProperty(i, "lang", segs[i].lang)
                            }
                            while (segModel.count > segs.length) segModel.remove(segModel.count - 1)
                        }
                        onTextChanged: syncSegments()
                        Component.onCompleted: syncSegments()

                        Rectangle {
                            id: bubble
                            visible: msg.role === "user" || msg.role === "assistant"
                            anchors.right: msg.mine ? parent.right : undefined
                            width: msg.mine ? Math.min(msg.maxW, Math.max(measure.implicitWidth, attachRow.implicitWidth) + 26) : msg.maxW
                            height: content.implicitHeight + 18
                            radius: PanelStyle.radiusCard
                            color: msg.mine ? Theme.withAlpha(Theme.primary, 0.16) : PanelStyle.cardFill

                            Column {
                                id: content
                                x: 13; y: 9
                                width: parent.width - 26
                                spacing: 8

                                // What was attached (user messages)
                                Flow {
                                    id: attachRow
                                    width: parent.width
                                    visible: msg.fileList.length > 0
                                    spacing: 6
                                    Repeater {
                                        model: msg.fileList
                                        AttachmentChip { required property string modelData; path: modelData }
                                    }
                                }
                                TextEdit {
                                    visible: msg.mine && msg.text !== ""
                                    width: parent.width
                                    readOnly: true
                                    selectByMouse: true
                                    textFormat: TextEdit.PlainText
                                    text: msg.mine ? msg.text : ""
                                    wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                    color: Theme.primary
                                    selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                                    selectedTextColor: Theme.primary
                                    font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                                }
                                Repeater {
                                    model: segModel
                                    delegate: Item {
                                        id: seg
                                        required property int index
                                        required property string kind
                                        required property string text
                                        required property string lang
                                        width: content.width
                                        height: kind === "code" ? codeBox.implicitHeight : prose.implicitHeight
                                        CodeBlock {
                                            id: codeBox
                                            visible: seg.kind === "code"
                                            width: parent.width
                                            code: seg.kind === "code" ? seg.text : ""
                                            lang: seg.lang
                                        }
                                        MessageText {
                                            id: prose
                                            visible: seg.kind === "text"
                                            width: parent.width
                                            text: seg.kind !== "text" ? ""
                                                : seg.text + (msg.streaming && seg.index === segModel.count - 1 ? " ▍" : "")
                                        }
                                    }
                                }
                                // Nothing yet
                                Text {
                                    visible: !msg.mine && segModel.count === 0
                                    text: msg.streaming ? "▍" : ""
                                    color: Theme.primary
                                }
                            }

                            // Copy the message
                            IconButton {
                                anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: 4
                                size: 22; iconSize: 11
                                icon: "󰆏"
                                visible: !msg.mine && !msg.streaming && bubbleHover.hovered
                                onClicked: Quickshell.execDetached(["wl-copy", "--", msg.text])
                            }
                            HoverHandler { id: bubbleHover }
                        }
                    }
                }
            }

            // ── It wants to do something: Allow / Always / Deny ──
            Repeater {
                model: root.editing === null ? Assistant.approvals : null
                delegate: Rectangle {
                    id: ask
                    required property int index
                    required property string requestId
                    required property string tool
                    required property string summary
                    required property string detail
                    required property string preview
                    required property string rule
                    required property string ruleText
                    visible: index === 0
                    Layout.fillWidth: true
                    implicitHeight: askCol.implicitHeight + 24
                    radius: PanelStyle.radiusCard
                    color: PanelStyle.cardFill
                    border.color: Theme.withAlpha(Theme.primary, 0.4)
                    border.width: 1

                    ColumnLayout {
                        id: askCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: "󰕥"; color: Theme.primary; font.pixelSize: 15 }
                            Text {
                                Layout.fillWidth: true
                                text: ({ Bash: "Wants to run a command", Edit: "Wants to change a file", Write: "Wants to write a file",
                                         Read: "Wants to read a file", WebFetch: "Wants to open a page" })[ask.tool] || ("Wants to use " + ask.tool)
                                    + (Assistant.approvals.count > 1 ? "  ·  1 of " + Assistant.approvals.count : "")
                                color: Theme.primary; font.bold: true
                                font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: ask.detail !== "" && ask.detail !== ask.preview
                            text: ask.detail
                            wrapMode: Text.Wrap
                            color: Theme.primary; opacity: PanelStyle.dim
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize
                        }
                        // What it wants to run: scrolls when it's long, so the
                        // whole command can be read before allowing it
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.min(Math.max(160, root.height * 0.3), code.implicitHeight + 16)
                            radius: PanelStyle.radiusControl
                            color: Theme.withAlpha(Theme.primary, 0.08)
                            clip: true
                            Flickable {
                                id: codeView
                                anchors.fill: parent
                                anchors.margins: 8
                                contentHeight: code.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentHeight > height
                                ScrollBar.vertical: ScrollBar { policy: codeView.interactive ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                            TextEdit {
                                id: code
                                width: codeView.width - (codeView.interactive ? 10 : 0)
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: ask.summary + (ask.preview !== "" ? "\n\n" + ask.preview : "")
                                color: Theme.primary
                                selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                                font.family: "monospace"; font.pixelSize: PanelStyle.labelSize + 2
                            }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            PanelButton {
                                accent: true; icon: "󰄬"; text: "Allow"
                                onClicked: Assistant.answer(ask.requestId, true, false)
                            }
                            PanelButton {
                                visible: ask.rule !== ""
                                text: "Always"
                                onClicked: Assistant.answer(ask.requestId, true, true)
                            }
                            PanelButton {
                                danger: true; icon: "󰅖"; text: "Deny"
                                onClicked: Assistant.answer(ask.requestId, false, false)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: ask.rule !== ""
                            text: "Always: also allows " + ask.ruleText + " for the rest of this chat"
                            wrapMode: Text.Wrap
                            color: Theme.primary; opacity: PanelStyle.faint
                            font.pixelSize: PanelStyle.labelSize + 1
                        }
                    }
                }
            }

            // ── Remote Control (/rc) ──
            Rectangle {
                visible: root.editing === null && Assistant.remoteHere
                Layout.fillWidth: true
                implicitHeight: rcCol.implicitHeight + 20
                radius: PanelStyle.radiusCard
                color: Theme.withAlpha(Theme.primary, 0.1)
                border.color: Theme.withAlpha(Theme.primary, 0.35); border.width: 1
                ColumnLayout {
                    id: rcCol
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "󰄜"; color: Theme.primary; font.pixelSize: 16 }
                        Text {
                            Layout.fillWidth: true
                            text: Assistant.remote ? "On Remote Control" : "Starting Remote Control…"
                            color: Theme.primary; font.bold: true
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                        }
                        PanelButton {
                            visible: Assistant.remote
                            text: "Bring it back"
                            onClicked: Assistant.stopRemote()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: Assistant.remote
                        text: "Also at <a href=\"" + Assistant.remoteUrl + "\">" + Assistant.remoteUrl.replace("https://", "")
                            + "</a> and in the Claude app (\"" + Assistant.remoteName + "\"). Messages from either side show up on both."
                        textFormat: Text.StyledText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: Theme.primary; opacity: PanelStyle.dim; linkColor: Theme.primary
                        font.family: Theme.fontFamily; font.pixelSize: PanelStyle.labelSize + 2
                        onLinkActivated: (link) => Qt.openUrlExternally(link)
                        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    }
                    // It waits for an OK: answer here or remotely
                    ColumnLayout {
                        visible: Assistant.remoteAsk !== ""
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6
                        Text {
                            text: "󰕥  Wants your OK"
                            color: Theme.primary; font.bold: true
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.min(150, askText.implicitHeight + 14)
                            radius: PanelStyle.radiusControl
                            color: Theme.withAlpha(Theme.primary, 0.08)
                            clip: true
                            Text {
                                id: askText
                                x: 8; y: 7
                                width: parent.width - 16
                                text: Assistant.remoteAsk
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: Theme.primary
                                font.family: "monospace"; font.pixelSize: PanelStyle.labelSize + 2
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            PanelButton { accent: true; icon: "󰄬"; text: "Allow"; onClicked: Assistant.remoteAnswer(true) }
                            PanelButton { danger: true; icon: "󰅖"; text: "Deny"; onClicked: Assistant.remoteAnswer(false) }
                        }
                    }
                }
            }

            // ── Slash commands: suggestions while typing one ──
            Column {
                id: slash
                // Only while the input is "/" plus the start of a command name
                readonly property bool typing: root.editing === null && /^\/[\w-]*$/.test(input.text)
                readonly property var items: typing ? Assistant.commandSuggestions(input.text.slice(1)) : []
                visible: items.length > 0
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: slash.items
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: slash.width; height: 28
                        radius: PanelStyle.radiusControl
                        color: rowMouse.containsMouse || index === 0 ? Theme.withAlpha(Theme.primary, 0.1) : "transparent"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10; spacing: 10
                            Text {
                                text: "/" + modelData.name
                                color: Theme.primary; font.bold: true
                                font.family: "monospace"; font.pixelSize: PanelStyle.bodySize
                            }
                            Text {
                                text: modelData.hint
                                color: Theme.primary; opacity: PanelStyle.faint
                                font.family: Theme.fontFamily; font.pixelSize: PanelStyle.labelSize + 1
                                elide: Text.ElideRight
                                width: slash.width - x - 20
                            }
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.completeCommand(modelData.name)
                        }
                    }
                }
            }

            // ── Attachments for the next message ──
            Flow {
                visible: root.editing === null && !root.showOnboarding && Assistant.attachments.count > 0
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Assistant.attachments
                    AttachmentChip {
                        required property int index
                        required property var model      // (a `path` role here would hide the chip's own)
                        path: model.path
                        removable: true
                        onRemoved: Assistant.detachFile(index)
                    }
                }
            }

            // ── Input ──
            PanelField {
                visible: root.editing === null && !root.showOnboarding
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(140, Math.max(PanelStyle.controlHeight + 6, input.implicitHeight + 14))
                focused: input.activeFocus

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 8
                    spacing: 8

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 4; Layout.bottomMargin: 4
                        TextArea {
                            id: input
                            placeholderText: Assistant.remoteHere ? "Message " + (Assistant.remoteName || "them") + " (on Remote Control too)…"
                                : Assistant.mode === "personal" ? "Talk to " + (Assistant.persona.name || "") + "…" : "Ask anything…"
                            color: Theme.primary
                            placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                            wrapMode: TextArea.Wrap
                            background: null
                            verticalAlignment: TextEdit.AlignVCenter
                            Keys.onPressed: (e) => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                    root.submit(); e.accepted = true
                                } else if (e.key === Qt.Key_Tab && slash.items.length > 0) {
                                    root.completeCommand(slash.items[0].name); e.accepted = true
                                } else if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.ShiftModifier)) {
                                    // An image or copied files attach; text pastes as usual
                                    root.pasteClipboard(); e.accepted = true
                                } else if (e.key === Qt.Key_Escape) {
                                    root.isOpen = false; e.accepted = true
                                }
                            }
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        size: 30; iconSize: 15
                        icon: "󰏢"
                        onClicked: root.pickFiles()
                        ToolTip.visible: hovered; ToolTip.delay: 500; ToolTip.text: "Attach files or images"
                    }
                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        size: 30; iconSize: 15
                        readonly property bool stops: Assistant.busy || (Assistant.remoteHere && Assistant.remoteWorking && input.text.trim() === "")
                        icon: stops ? "󰓛" : "󰒊"
                        enabled: stops || input.text.trim() !== "" || Assistant.attachments.count > 0
                        opacity: enabled ? 1 : 0.4
                        onClicked: stops ? Assistant.stop() : root.submit()
                    }
                }
            }

            Text {
                visible: root.editing === null && !root.showOnboarding
                Layout.fillWidth: true
                text: "Enter to send · Shift+Enter for a new line · Ctrl+V or drop files to attach · / for commands"
                color: Theme.primary; opacity: PanelStyle.faint
                font.pixelSize: PanelStyle.labelSize
                horizontalAlignment: Text.AlignHCenter
                // A narrow panel: wrap at the separators instead of spilling past the edges
                wrapMode: Text.WordWrap
                Layout.preferredWidth: 0   // the layout's width, not the text's one-line width
            }
        }
    }

    function completeCommand(name) {
        input.text = "/" + name + " "
        input.cursorPosition = input.text.length
        input.forceActiveFocus()
    }

    function submit() {
        if (Assistant.busy || (input.text.trim() === "" && Assistant.attachments.count === 0)) return
        Assistant.send(input.text)
        input.text = ""
    }

    // ── Attaching ──
    // Ctrl+V: tools/clip-attach saves a copied image (or lists copied files);
    // when the clipboard holds text, the input pastes it instead
    Process {
        id: clipAttach
        command: [Assistant.toolsDir + "/clip-attach", Assistant.attachDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const files = this.text.split("\n").filter(l => l.startsWith("file ")).map(l => l.slice(5))
                if (!files.length) { input.paste(); return }
                for (const f of files) Assistant.attach(f)
            }
        }
    }
    function pasteClipboard() { if (!clipAttach.running) clipAttach.running = true }
    // The paperclip: a file chooser (zenity)
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach to the assistant"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const f of this.text.split("\n")) if (f.trim() !== "") Assistant.attach(f.trim())
            }
        }
    }
    function pickFiles() { if (!picker.running) picker.running = true }
}
