import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

PanelWindow {
    id: root
    property bool active: false
    property string searchText: ""
    
    // Wayland-safe exit animation state
    property bool isAnimating: false
    visible: active || isAnimating
    
    screen: modelData 

    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // Background click-to-close area
    MouseArea {
        anchors.fill: parent
        onClicked: { root.active = false }
    }

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
    Process {
        id: clipExec
        function run(args) { command = args; running = true }
    }

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

    onActiveChanged: {
        if (active) {
            root.isAnimating = true
            root.searchText = ""
            searchField.forceActiveFocus()
            clipModel.clear()
            clipLoader.running = true
            root.hoveredClipId = ""
            root.hoveredIsImage = false
            root.decodedImagePath = ""
            root.decodedText = ""
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // UNIFIED EXPANDING CONTAINER (Zero-Jitter Architecture)
    // ══════════════════════════════════════════════════════════════════════════
    Item {
        anchors.fill: parent

        Rectangle {
            id: mainCard
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.rightMargin: 155
            height: 640
            
            // Dynamic width expansion. 
            // Because it is anchored to the right, it smoothly grows to the left!
            width: root.hoveredClipId !== "" ? 820 : 440
            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
            
            anchors.topMargin: root.active ? 45 : 20
            Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

            color: "transparent"
            radius: 30

            // Entrance Opacity & Animation tracking
            opacity: root.active ? 1.0 : 0.0
            Behavior on opacity { 
                NumberAnimation { 
                    duration: 250; easing.type: Easing.OutCubic 
                    onRunningChanged: if (!running && !root.active) root.isAnimating = false 
                } 
            }

            // The blurred background layer (0.8 opacity for Hyprland to blur!)
            Rectangle {
                anchors.fill: parent
                radius: 30
                color: Theme.background
                opacity: 0.8 
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
                border.width: 2
            }

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
                    width: 340 // Fixed internal width guarantees NO text cropping or reflowing!
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 25
                    anchors.bottomMargin: 25
                    spacing: 16

                    // Header
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Text { text: root.hoveredIsImage ? "󰋼" : "󰈙"; color: Theme.primary; font.pixelSize: 18; opacity: 0.8 }
                        Text { text: root.hoveredIsImage ? "Image Preview" : "Content Preview"; color: Theme.primary; font.pixelSize: 16; font.bold: true; opacity: 0.8 }
                        Item { Layout.fillWidth: true }
                    }

                    // ── TEXT PREVIEW ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.hoveredIsImage
                        radius: 20
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        border.width: 1

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
                        radius: 20
                        color: Qt.rgba(0, 0, 0, 0.15)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        border.width: 1
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
                width: 440 // Rigid width blocks layout jitter
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 25
                    spacing: 18

                    // Header
                    RowLayout {
                        Layout.fillWidth: true; spacing: 14
                        
                        Rectangle {
                            width: 44; height: 44; radius: 14
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                            Text { anchors.centerIn: parent; text: "󰅌"; color: Theme.primary; opacity: 0.8; font.pixelSize: 22 }
                        }
                        
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Clipboard"; color: Theme.primary; font.pixelSize: 20; font.bold: true; opacity: 0.9 }
                            Text { text: clipModel.count + " entries"; color: Theme.primary; font.pixelSize: 12; opacity: 0.5 }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Rectangle {
                            width: 90; height: 36; radius: 18
                            color: clearMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                            border.color: Theme.primary; border.width: 1
                            scale: clearMouse.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            RowLayout { 
                                anchors.centerIn: parent; spacing: 6
                                Text { text: "󰃢"; color: Theme.primary; font.pixelSize: 14; opacity: 0.8 }
                                Text { text: "Clear"; color: Theme.primary; font.pixelSize: 12; font.bold: true; opacity: 0.8 }
                            }
                            MouseArea {
                                id: clearMouse; anchors.fill: parent; hoverEnabled: true
                                onClicked: { clipExec.run(["bash", "-c", "cliphist wipe"]); clipModel.clear(); root.active = false }
                            }
                        }
                    }

                    // Search Bar
                    Rectangle {
                        Layout.fillWidth: true; height: 48; radius: 24
                        color: searchField.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04)
                        border.color: searchField.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3) : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 16; spacing: 10
                            Text { text: "󰍉"; color: Theme.primary; opacity: searchField.activeFocus ? 0.8 : 0.4; font.pixelSize: 16 }
                            
                            TextField {
                                id: searchField; Layout.fillWidth: true
                                placeholderText: "Search history..."
                                placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                color: Theme.primary; font.pixelSize: 14; background: Item {}
                                onTextChanged: { root.searchText = text; searchDelay.restart() }
                            }
                            
                            Text {
                                text: "󰅖"; color: Theme.primary; font.pixelSize: 16; opacity: 0.4
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
                            spacing: 10; boundsBehavior: Flickable.StopAtBounds; cacheBuffer: 200

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
                                width: listView.width; height: 56; radius: 16
                                
                                color: copyMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.02)
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
                                                clipExec.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist decode | wl-copy"])
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
                                                clipExec.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist delete"])
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
                        color: Theme.primary; opacity: 0.3; font.pixelSize: 11
                        Layout.topMargin: 4
                    }
                }
            }
        }
    }
}