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

// AI assistant (META+A): a chat drawer on the right, backed by the Claude CLI
// (services/Assistant.qml). "Assistant" is a plain assistant; "Special" talks
// as one of the special personas (personas/*.json) and, when that persona's
// character files were added, shows the character next to the panel: tap it
// to make it talk, pat its head to see it react (character/).
//
// It is a FrameDrawer like the sidebar, so each theme draws it its own way
// (out of the frame in LightCrimson, a floating plate in the BA themes). It
// only takes input over the panel itself, so the character and the windows
// stay clickable while it's open; Esc or the close button hides it.
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
    mask: Region { item: body }

    onIsOpenChanged: {
        if (isOpen) {
            animating = true
            FrameState.claim("assistant")
            focusTimer.restart()
        }
        Assistant.showCharacter(isOpen, panelWidth + 16)
    }
    Connections {
        target: FrameState
        function onClaimed(k) { if (k !== "assistant") root.isOpen = false }
    }

    IpcHandler {
        target: "assistant"
        function toggle(): void { root.isOpen = !root.isOpen }
        function open(): void { root.isOpen = true }
        function close(): void { root.isOpen = false }
        // Open and send a message right away
        function ask(text: string): void { root.isOpen = true; Assistant.send(text) }
        function mode(m: string): void { if (m === "assistant" || m === "special") Assistant.mode = m }
        // Start a new chat with the current persona
        function clear(): void { Assistant.newChat() }
        // Debug: fake a tap ("head", "body") or a pat on the character
        function poke(kind: string): void { Assistant.pokeCharacter(kind) }
        function persona(id: string): void { if (Assistant.specialPersonas.includes(id)) { Assistant.specialPersona = id; Assistant.mode = "special" } }
    }

    Timer { id: focusTimer; interval: 120; onTriggered: input.forceActiveFocus() }

    FrameDrawer {
        open: root.isOpen
        onClosed: root.animating = false
        edge: "right"
        panelWidth: root.panelWidth
        duration: 350

        Item {
            id: body
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
                    subtitle: Assistant.busy ? (Assistant.status || "Thinking…") : (Assistant.persona.tagline || "")

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

                // ── Mode: plain assistant or a special persona ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Chip {
                        icon: "󰚩"; text: "Assistant"
                        selected: Assistant.mode === "assistant"
                        onClicked: Assistant.mode = "assistant"
                    }
                    Chip {
                        icon: "󰫢"; text: "Special"
                        selected: Assistant.mode === "special"
                        visible: Assistant.specialPersonas.length > 0
                        onClicked: Assistant.mode = "special"
                    }
                    Rectangle {
                        visible: Assistant.mode === "special"
                        Layout.preferredWidth: 1; Layout.preferredHeight: 18
                        Layout.leftMargin: 4; Layout.rightMargin: 4
                        color: PanelStyle.divider
                    }
                    Repeater {
                        model: Assistant.mode === "special" ? Assistant.specialPersonas : []
                        Chip {
                            required property string modelData
                            text: (Assistant.personas[modelData] || {}).name || modelData
                            selected: Assistant.specialPersona === modelData
                            onClicked: Assistant.specialPersona = modelData
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // No character files for this persona: say where they go
                Text {
                    Layout.fillWidth: true
                    visible: Assistant.mode === "special" && !Assistant.characterAvailable
                    text: "No character files for " + (Assistant.persona.name || "") + ". Add a Spine export to ~/.local/share/ml4w-assistant/characters/" + Assistant.personaId + "/ to see them here."
                    wrapMode: Text.Wrap
                    color: Theme.primary; opacity: PanelStyle.faint
                    font.pixelSize: PanelStyle.labelSize + 1
                }

                // ── Conversation ──
                Item {
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
                            width: list.width
                            height: role === "note" ? noteText.implicitHeight + 4 : bubble.height

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
                                visible: msg.role !== "note"
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

                // ── Input ──
                PanelField {
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
                                placeholderText: Assistant.mode === "special"
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
                    Layout.fillWidth: true
                    text: "Claude · Enter to send · Shift+Enter for a new line"
                    color: Theme.primary; opacity: PanelStyle.faint
                    font.pixelSize: PanelStyle.labelSize
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    function submit() {
        if (Assistant.busy || input.text.trim() === "") return
        Assistant.send(input.text)
        input.text = ""
    }
}
