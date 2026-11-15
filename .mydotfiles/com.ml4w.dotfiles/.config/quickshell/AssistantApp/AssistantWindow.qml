import Quickshell
import Quickshell.Wayland
import Quickshell.Io
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

    readonly property real panelWidth: PanelStyle.narrowWidth
    property bool isOpen: false
    property bool animating: false
    visible: isOpen || animating
    // Input only over the panel. Floating, the region is computed from the
    // card's position: a Region following the card item kept the spot where
    // the card was, so after a drag its header was out of it.
    mask: floating ? floatRegion : dockRegion
    property Region dockRegion: Region { item: body }
    property Region floatRegion: Region { x: root.floatX; y: root.floatY; width: root.panelWidth; height: root.floatH }

    // ── Floating ──
    property bool floating: false
    property real floatX: -1                 // remembered while the shell runs
    property real floatY: -1
    readonly property real floatH: Math.min(height - 140, 780)
    function detach() {
        if (floatX < 0) {                    // first time: left of where the right-side drawers open
            floatX = width - panelWidth * 2 - 60
            floatY = Math.round((height - floatH) / 2) + 10
        }
        moveFloat(floatX, floatY)
        floating = true
    }
    function dock() { floating = false }
    function moveFloat(x, y) {
        floatX = Math.round(Math.max(8, Math.min(width - panelWidth - 8, x)))
        floatY = Math.round(Math.max(8, Math.min(height - floatH - 8, y)))
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
        if (floating) Assistant.placeCharacter(width - floatX + 6, height - floatY - floatH)
        else Assistant.placeCharacter(panelWidth + 16, 10)
    }
    Timer { id: placeThrottle; interval: 33; onTriggered: root.placeCharacter() }
    onFloatXChanged: if (floating && !placeThrottle.running) placeThrottle.start()
    onFloatYChanged: if (floating && !placeThrottle.running) placeThrottle.start()

    onIsOpenChanged: {
        if (isOpen) {
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
        // Float it (it stays open with other popups), or put it back
        function detach(): void { root.isOpen = true; root.detach() }
        function dock(): void { root.dock() }
        // Answer the first pending request (what the Allow / Deny buttons do)
        function allow(): void { if (Assistant.approvals.count) Assistant.answer(Assistant.approvals.get(0).requestId, true, false) }
        function deny(): void { if (Assistant.approvals.count) Assistant.answer(Assistant.approvals.get(0).requestId, false, false) }
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
        panelWidth: root.panelWidth
        duration: 350

        Item { id: drawerSlot; anchors.fill: parent }
    }

    // ── The floating card ──
    Item {
        id: floatCard
        visible: root.floating && root.isOpen
        x: root.floatX; y: root.floatY
        width: root.panelWidth; height: root.floatH

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
                onActiveChanged: if (active) { startX = root.floatX; startY = root.floatY }
                onCentroidChanged: if (active) root.moveFloat(
                    startX + centroid.scenePosition.x - centroid.scenePressPosition.x,
                    startY + centroid.scenePosition.y - centroid.scenePressPosition.y)
            }
            HoverHandler { cursorShape: dragger.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
        }
        Item { id: floatSlot; anchors.fill: parent }

    }

    // The panel's content: in the drawer, or in the floating card
    Item {
        id: body
        parent: root.floating ? floatSlot : drawerSlot
        anchors.fill: parent

        Keys.onEscapePressed: root.isOpen = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: PanelStyle.pad
            spacing: PanelStyle.gap

            // ── Header ──
            PanelHeader {
                icon: Assistant.persona.icon || "󰚩"
                title: Assistant.persona.name || "Assistant"
                subtitle: Assistant.drafting === Assistant.personaId && Assistant.drafting !== "" ? "Writing their lines…"
                    : Assistant.busy ? (Assistant.status || "Thinking…") : (Assistant.persona.tagline || "")

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
                        readonly property bool mine: role === "user"
                        readonly property real maxW: list.width - (mine ? 48 : 0)
                        // A tool it used: "tool:<name>", ":err" when it failed or was denied
                        readonly property bool isTool: role.startsWith("tool:")
                        readonly property string toolName: isTool ? role.split(":")[1] : ""
                        readonly property bool toolFailed: role.endsWith(":err")
                        width: list.width
                        height: role === "note" ? noteText.implicitHeight + 4
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
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            id: noteText
                            visible: msg.role === "note"
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: msg.text
                            wrapMode: Text.Wrap
                            color: Theme.error
                            font.pixelSize: PanelStyle.labelSize + 1
                        }

                        // Measures a user message, so its bubble fits it
                        Text {
                            id: measure
                            visible: false
                            text: msg.text
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                        }

                        Rectangle {
                            id: bubble
                            visible: msg.role === "user" || msg.role === "assistant"
                            anchors.right: msg.mine ? parent.right : undefined
                            width: msg.mine ? Math.min(msg.maxW, measure.implicitWidth + 26) : msg.maxW
                            height: textEdit.implicitHeight + 18
                            radius: PanelStyle.radiusCard
                            color: msg.mine ? Theme.withAlpha(Theme.primary, 0.16) : PanelStyle.cardFill

                            TextEdit {
                                id: textEdit
                                x: 13; y: 9
                                width: parent.width - 26
                                readOnly: true
                                selectByMouse: true
                                textFormat: msg.mine ? TextEdit.PlainText : TextEdit.MarkdownText
                                text: msg.text + (msg.streaming ? " ▍" : "")
                                wrapMode: TextEdit.Wrap
                                color: Theme.primary
                                selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                                selectedTextColor: Theme.primary
                                font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                                onLinkActivated: (link) => Qt.openUrlExternally(link)
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
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.min(160, code.implicitHeight + 16)
                            radius: PanelStyle.radiusControl
                            color: Theme.withAlpha(Theme.primary, 0.08)
                            clip: true
                            TextEdit {
                                id: code
                                x: 8; y: 8
                                width: parent.width - 16
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: ask.summary + (ask.preview !== "" ? "\n\n" + ask.preview : "")
                                color: Theme.primary
                                selectionColor: Theme.withAlpha(Theme.primary, 0.3)
                                font.family: "monospace"; font.pixelSize: PanelStyle.labelSize + 2
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
                            placeholderText: Assistant.mode === "personal"
                                ? "Talk to " + (Assistant.persona.name || "") + "…" : "Ask anything…"
                            color: Theme.primary
                            placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
                            font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
                            wrapMode: TextArea.Wrap
                            background: null
                            verticalAlignment: TextEdit.AlignVCenter
                            Keys.onPressed: (e) => {
                                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                                    root.submit(); e.accepted = true
                                } else if (e.key === Qt.Key_Escape) {
                                    root.isOpen = false; e.accepted = true
                                }
                            }
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        size: 30; iconSize: 15
                        icon: Assistant.busy ? "󰓛" : "󰒊"
                        enabled: Assistant.busy || input.text.trim() !== ""
                        opacity: enabled ? 1 : 0.4
                        onClicked: Assistant.busy ? Assistant.stop() : root.submit()
                    }
                }
            }

            Text {
                visible: root.editing === null && !root.showOnboarding
                Layout.fillWidth: true
                text: "Claude · Enter to send · Shift+Enter for a new line"
                color: Theme.primary; opacity: PanelStyle.faint
                font.pixelSize: PanelStyle.labelSize
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function submit() {
        if (Assistant.busy || input.text.trim() === "") return
        Assistant.send(input.text)
        input.text = ""
    }
}
