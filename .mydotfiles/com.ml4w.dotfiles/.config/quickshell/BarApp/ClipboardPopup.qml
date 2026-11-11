import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

BarPopup {
    id: root
    ipcTarget: "bar-clipboard"
    property string searchText: ""

    // --- PREVIEW STATE ---
    property string hoveredClipId: ""
    property string hoveredPreview: ""
    property bool hoveredIsImage: false
    property string decodedImagePath: ""
    
    property string decodedText: ""
    property string _textBuf: ""

    Process {
        id: imageDecoder
        property string targetId: ""
        property string targetPreview: ""

        property string targetFile: {
            let safe = targetId.replace(/[^a-zA-Z0-9]/g, "_")
            return "/tmp/qs_clip_" + safe + ".png"
        }

        command: ["bash", "-c",
            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode > \"$3\" 2>/dev/null && echo ok",
            "_",
            imageDecoder.targetId,
            imageDecoder.targetPreview,
            imageDecoder.targetFile
        ]

        stdout: SplitParser {
            onRead: {
                if (data.trim() === "ok") {
                    root.decodedImagePath = "file://" + imageDecoder.targetFile + "?t=" + Date.now()
                }
            }
        }
    }

    Process {
        id: textDecoder
        property string targetId: ""
        property string targetPreview: ""

        command: ["bash", "-c",
            "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode 2>/dev/null",
            "_",
            textDecoder.targetId,
            textDecoder.targetPreview
        ]

        stdout: SplitParser {
            onRead: { root._textBuf += data + "\n" }
        }
        onRunningChanged: {
            if (!running) {
                root.decodedText = root._textBuf.replace(/\n$/, "")
            }
        }
    }

    Timer {
        id: decodeDebounce; interval: 120
        onTriggered: {
            if (root.hoveredClipId !== "") {
                if (root.hoveredIsImage) {
                    imageDecoder.targetId = root.hoveredClipId
                    imageDecoder.targetPreview = root.hoveredPreview
                    imageDecoder.running = true
                } else {
                    root._textBuf = ""
                    root.decodedText = "" 
                    textDecoder.targetId = root.hoveredClipId
                    textDecoder.targetPreview = root.hoveredPreview
                    textDecoder.running = true
                }
            }
        }
    }

    Timer {
        id: hidePreviewTimer; interval: 350
        onTriggered: {
            root.hoveredClipId = ""
            root.hoveredPreview = ""
            root.hoveredIsImage = false
        }
    }

    // --- LOGIC ---
    ListModel { id: clipModel }

    Process {
        id: clipLoader
        command: root.searchText === "" 
                 ? ["cliphist", "list"] 
                 : ["bash", "-c", "cliphist list | grep -i '" + root.searchText + "'"]
        stdout: SplitParser {
            onRead: {
                let line = data.trim()
                if (line.length === 0) return
                let splitIdx = line.indexOf("\t")
                if (splitIdx !== -1)
                    clipModel.append({ "clipId": line.substring(0, splitIdx), "preview": line.substring(splitIdx + 1) })
            }
        }
    }

    Timer {
        id: searchDelay; interval: 200
        onTriggered: { clipModel.clear(); clipLoader.running = true }
    }

    onOpened: {
        root.searchText = ""
        searchField.forceActiveFocus()
        clipModel.clear()
        clipLoader.running = true
        root.hoveredClipId = ""
        root.hoveredIsImage = false
        root.decodedImagePath = ""
        root.decodedText = ""
    }

    // ══════════════════════════════════════════════════════════════════════════
    // UNIFIED EXPANDING CONTAINER (Zero-Jitter Architecture)
    // ══════════════════════════════════════════════════════════════════════════
    // Hangs from the bar as part of the frame (fill, blur and border as before).
    // Right-aligned, so the hover expansion still grows it to the left.
    PopoutContent {
        open: root.active
        onClosed: root.isAnimating = false
        hAlign: "right"
        hMargin: PanelStyle.rightMargin
        panelWidth: mainCard.width
        panelHeight: mainCard.height

        Rectangle {
            id: mainCard
            height: PanelStyle.rightHeight

            // Dynamic width expansion (the drawer is right-aligned, so it grows to the left).
            width: root.hoveredClipId !== "" ? 820 : PanelStyle.narrowWidth
            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

            color: "transparent"
            radius: 30

            MouseArea { anchors.fill: parent } // Prevent click-through closing

            // ── LEFT PANE: PREVIEW AREA ──
            Item {
                id: previewPane
                anchors.left: parent.left
                anchors.right: clipboardPane.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                
                opacity: root.hoveredClipId !== "" ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                
                clip: true // MASK REVEAL: This prevents the text from ever resizing/jittering!

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onEntered: hidePreviewTimer.stop()
                    onExited: hidePreviewTimer.restart()
                }

                // Inner content is rigidly pinned to the right side of the mask
                ColumnLayout {
                    width: 360 // Fixed internal width (820 - list width - pad) guarantees NO text cropping or reflowing!
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: PanelStyle.pad
                    anchors.bottomMargin: PanelStyle.pad
                    spacing: PanelStyle.gap

                    // Header (same height as the list's, so the two panes line up)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: PanelStyle.headerHeight
                        spacing: 10
                        Text { text: root.hoveredIsImage ? "󰋼" : "󰈙"; color: Theme.primary; font.pixelSize: 17; opacity: 0.8 }
                        Text { text: root.hoveredIsImage ? "Image preview" : "Content preview"; color: Theme.primary; font.pixelSize: 14; font.bold: true; opacity: 0.8 }
                        Item { Layout.fillWidth: true }
                    }

                    // ── TEXT PREVIEW ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.hoveredIsImage
                        radius: PanelStyle.radiusCard
                        color: PanelStyle.cardFill

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 18
                            clip: true
                            contentWidth: width
                            contentHeight: rawText.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                                id: rawText
                                width: parent.width
                                text: root.decodedText !== "" ? root.decodedText : root.hoveredPreview
                                color: Theme.primary
                                font.pixelSize: 13
                                wrapMode: Text.WrapAnywhere
                                opacity: 0.9
                                lineHeight: 1.3
                            }
                            
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.primary; opacity: 0.2 }
                            }
                        }

                        // Loading indicator for very large texts
                        Text {
                            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 12
                            text: "Decoding..."
                            color: Theme.primary; opacity: 0.4; font.pixelSize: 10
                            visible: textDecoder.running && root.decodedText === ""
                        }
                    }

                    // ── IMAGE PREVIEW ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.hoveredIsImage
                        radius: PanelStyle.radiusCard
                        color: PanelStyle.cardFill
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 12
                            source: root.decodedImagePath
                            cache: false
                            fillMode: Image.PreserveAspectFit
                            smooth: true; asynchronous: true

                            Rectangle {
                                anchors.centerIn: parent
                                width: 48; height: 48; radius: 24
                                color: Theme.background
                                visible: parent.status === Image.Loading
                                Text { anchors.centerIn: parent; text: "󰦟"; color: Theme.primary; opacity: 0.5; font.pixelSize: 24 }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: parent.status === Image.Error || parent.status === Image.Null
                                spacing: 8
                                Text { text: "󰋼"; color: Theme.primary; opacity: 0.2; font.pixelSize: 38; Layout.alignment: Qt.AlignHCenter }
                                Text { text: "Preview unavailable"; color: Theme.primary; opacity: 0.4; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }

                    // Image Footer Metadata
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.hoveredIsImage
                        text: root.hoveredPreview.replace("[[", "").replace("]]", "").trim()
                        color: Theme.primary
                        opacity: 0.4
                        font.pixelSize: 11
                    }
                }
            }

            // ── RIGHT PANE: MAIN CLIPBOARD LIST ──
            Item {
                id: clipboardPane
                width: PanelStyle.narrowWidth // Rigid width blocks layout jitter
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: PanelStyle.pad
                    spacing: PanelStyle.gap

                    PanelHeader {
                        icon: "󰅌"
                        title: "Clipboard"
                        subtitle: clipModel.count + " entries"

                        PanelButton {
                            icon: "󰃢"
                            text: "Clear"
                            // Every history (cliphist, elephant) and the current selection
                            onClicked: { Sys.run(["bash", "-c", "$HOME/.config/ml4w/scripts/ml4w-cliphist w"]); clipModel.clear(); root.active = false }
                        }
                        SectionNav { host: root.host; current: root.ipcTarget }
                    }

                    // Search Bar
                    PanelField {
                        Layout.fillWidth: true
                        focused: searchField.activeFocus

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                            Text { text: "󰍉"; color: Theme.primary; opacity: searchField.activeFocus ? 0.8 : 0.45; font.pixelSize: 16 }

                            TextField {
                                id: searchField; Layout.fillWidth: true
                                placeholderText: "Search history…"
                                placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
                                color: Theme.primary; font.pixelSize: 14; background: Item {}
                                verticalAlignment: TextInput.AlignVCenter
                                onTextChanged: { root.searchText = text; searchDelay.restart() }
                                Keys.onEscapePressed: {
                                    if (root.searchText !== "") {
                                        searchField.text = ""
                                    } else {
                                        root.active = false
                                    }
                                }
                            }

                            Text {
                                text: "󰅖"; color: Theme.primary; font.pixelSize: 15; opacity: 0.45
                                visible: searchField.text.length > 0
                                MouseArea { anchors.fill: parent; onClicked: { searchField.text = ""; searchField.forceActiveFocus() } }
                            }
                        }
                    }

                    // List Area
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: "transparent"; clip: true

                        ListView {
                            id: listView; anchors.fill: parent; model: clipModel
                            spacing: 8; boundsBehavior: Flickable.StopAtBounds; cacheBuffer: 200

                            Item {
                                anchors.centerIn: parent; visible: clipModel.count === 0
                                width: listView.width; height: 120
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 12
                                    Text { text: "󰅌"; color: Theme.primary; opacity: 0.15; font.pixelSize: 48; Layout.alignment: Qt.AlignHCenter }
                                    Text {
                                        text: root.searchText !== "" ? "No results found" : "Nothing copied yet"
                                        color: Theme.primary; opacity: 0.4; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            delegate: Rectangle {
                                id: itemCard
                                width: listView.width; height: 52; radius: PanelStyle.radiusCard

                                color: (copyMouse.containsMouse || delMouse.containsMouse) ? PanelStyle.cardHover : PanelStyle.cardFill
                                scale: copyMouse.pressed ? 0.98 : 1.0
                                
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                Rectangle {
                                    width: 4; height: 24
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    radius: 2; color: Theme.primary
                                    opacity: model.preview.startsWith("[[") ? 0.4 : 0.0
                                }

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 12; spacing: 14

                                    Text {
                                        text: model.preview.startsWith("[[") ? "󰋼" : "󰆒"
                                        color: Theme.primary; opacity: 0.4; font.pixelSize: 15
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Item {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        Text {
                                            anchors.fill: parent; text: model.preview
                                            color: Theme.primary; font.pixelSize: 14
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            opacity: 0.8
                                        }
                                        MouseArea {
                                            id: copyMouse; anchors.fill: parent; hoverEnabled: true
                                            onEntered: {
                                                hidePreviewTimer.stop()
                                                root.hoveredClipId = model.clipId
                                                root.hoveredPreview = model.preview
                                                root.hoveredIsImage = model.preview.startsWith("[[")
                                                root.decodedImagePath = ""
                                                decodeDebounce.restart() 
                                            }
                                            onExited: hidePreviewTimer.restart()
                                            onClicked: {
                                                Sys.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist decode | wl-copy"])
                                                root.active = false
                                            }
                                        }
                                    }

                                    Text {
                                        text: "󰆴"
                                        color: delMouse.containsMouse ? "#ff6b6b" : Theme.primary
                                        opacity: delMouse.containsMouse ? 1.0 : 0.2
                                        font.pixelSize: 16
                                        scale: delMouse.pressed ? 0.8 : (delMouse.containsMouse ? 1.2 : 1.0)
                                        
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                        MouseArea {
                                            id: delMouse; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                Sys.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist delete"])
                                                clipModel.remove(index)
                                                if (root.hoveredClipId === model.clipId) root.hoveredClipId = ""
                                            }
                                        }
                                    }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.primary; opacity: 0.2 }
                            }
                        }
                    }

                    // Footer Text
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Click to copy  ·  Click on bin to delete"
                        color: Theme.primary; opacity: PanelStyle.faint; font.pixelSize: 11
                    }
                }
            }
        }
    }
}