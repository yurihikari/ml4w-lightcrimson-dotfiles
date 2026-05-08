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
    
    // 1. Wayland-safe exit animation state
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

    MouseArea {
        anchors.fill: parent
        onClicked: { root.active = false }
    }

    // --- PREVIEW STATE ---
    property string hoveredClipId: ""
    property string hoveredPreview: ""
    property bool hoveredIsImage: false
    property string decodedImagePath: ""

    Process {
        id: imageDecoder
        property string targetId: ""
        property string targetPreview: ""

        // FIX: each clip ID gets its own temp file so Qt's image cache never
        // serves a stale image when revisiting a previously-seen entry.
        // The ?t= timestamp on the source URL is a second line of defence —
        // it makes Qt treat each decode result as a distinct URL.
        property string targetFile: {
            let safe = targetId.replace(/[^a-zA-Z0-9]/g, "_")
            return "/tmp/qs_clip_" + safe + ".png"
        }

        // Pass everything as positional args ($1 $2 $3) — avoids any quoting
        // issues with clip IDs or preview text that contain special characters.
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
                    // ?t= cache-busts Qt's URL-keyed image cache
                    root.decodedImagePath = "file://" + imageDecoder.targetFile
                                           + "?t=" + Date.now()
                }
            }
        }
    }

    Timer {
        id: decodeDebounce; interval: 120
        onTriggered: {
            if (root.hoveredIsImage && root.hoveredClipId !== "") {
                imageDecoder.targetId = root.hoveredClipId
                imageDecoder.targetPreview = root.hoveredPreview
                imageDecoder.running = true
            }
        }
    }

    Timer {
        id: hidePreviewTimer; interval: 300
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

    // 2. Track animation state when opening
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
        }
    }

    // --- WRAPPER FOR SMOOTH ANIMATIONS ---
    Item {
        id: mainContent
        width: 420; height: 620
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 155

        // 3. Smooth Entrance / Exit Animations
        anchors.topMargin: root.active ? 45 : 25
        transformOrigin: Item.Top
        opacity: root.active ? 1.0 : 0.0
        scale: root.active ? 1.0 : 0.90
        
        Behavior on opacity { 
            NumberAnimation { 
                duration: 250; easing.type: Easing.OutCubic 
                onRunningChanged: if (!running && !root.active) root.isAnimating = false 
            } 
        }
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }


        // --- PREVIEW PANEL ---
        Rectangle {
            id: previewPanel
            width: 280
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.left
            anchors.rightMargin: 12
            radius: 24
            color: "transparent"
            visible: opacity > 0
            opacity: root.hoveredClipId !== "" ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                onEntered: hidePreviewTimer.stop()
                onExited: hidePreviewTimer.restart()
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8); border.width: 2
                radius: 24; opacity: 0.9
            }

            Text {
                id: previewHeader
                anchors.top: parent.top; anchors.topMargin: 16
                anchors.left: parent.left; anchors.leftMargin: 16
                text: root.hoveredIsImage ? "󰋼  Image Preview" : "󰈙  Content Preview"
                color: Theme.primary; opacity: 0.45
                font.pixelSize: 11; font.bold: true
            }

            Rectangle {
                id: previewDivider
                anchors.top: previewHeader.bottom; anchors.topMargin: 10
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 16; anchors.rightMargin: 16
                height: 1; color: Theme.primary; opacity: 0.08
            }

            Rectangle {
                id: previewContent
                anchors.top: previewDivider.bottom; anchors.topMargin: 10
                anchors.bottom: previewFooter.top; anchors.bottomMargin: 10
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 16; anchors.rightMargin: 16
                color: Theme.background; radius: 14; clip: true

                Image {
                    anchors.fill: parent; anchors.margins: 8
                    visible: root.hoveredIsImage
                    source: root.decodedImagePath
                    cache: false   // belt-and-suspenders: never serve stale data
                    fillMode: Image.PreserveAspectFit
                    smooth: true; asynchronous: true

                    Rectangle {
                        anchors.centerIn: parent; width: 40; height: 40; radius: 20
                        color: Theme.background
                        visible: parent.status === Image.Loading
                        Text { anchors.centerIn: parent; text: "󰦟"; color: Theme.primary; opacity: 0.4; font.pixelSize: 20 }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: parent.status === Image.Error || parent.status === Image.Null
                        spacing: 6
                        Text { text: "󰋼"; color: Theme.primary; opacity: 0.2; font.pixelSize: 32; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Preview unavailable"; color: Theme.primary; opacity: 0.3; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                    }
                }

                Flickable {
                    anchors.fill: parent; anchors.margins: 10
                    visible: !root.hoveredIsImage
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: fullText.implicitHeight

                    Text {
                        id: fullText
                        width: 220
                        text: root.hoveredPreview
                        color: Theme.primary
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        opacity: 0.85
                        lineHeight: 1.3
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: 3; radius: 2; color: Theme.primary; opacity: 0.25 }
                    }
                }
            }

            Text {
                id: previewFooter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.hoveredIsImage
                text: root.hoveredPreview.replace("[[", "").replace("]]", "").trim()
                color: Theme.primary; opacity: 0.3; font.pixelSize: 10
            }
        }

        // --- MAIN CONTAINER ---
        Rectangle {
            id: container
            anchors.fill: parent
            radius: 30; color: "transparent"

            Rectangle {
                anchors.fill: parent; color: Theme.background
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8); border.width: 2
                radius: 30; opacity: 0.8
            }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 14

                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 4; spacing: 10
                    Rectangle {
                        width: 36; height: 36; radius: 10; color: Theme.primary; opacity: 0.15
                        Text { anchors.centerIn: parent; text: "󰅌"; color: Theme.primary; font.pixelSize: 18 }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "Clipboard"; color: Theme.primary; font.pixelSize: 18; font.bold: true }
                        Text { text: clipModel.count + " entries"; color: Theme.primary; font.pixelSize: 10; opacity: 0.45 }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 80; height: 30; radius: 15; color: Theme.background
                        border.color: Theme.primary; border.width: 1
                        opacity: clearMouse.containsMouse ? 1.0 : 0.7
                        RowLayout { anchors.centerIn: parent; spacing: 5
                            Text { text: "󰃢"; color: Theme.primary; font.pixelSize: 12 }
                            Text { text: "Clear"; color: Theme.primary; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea {
                            id: clearMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { clipExec.run(["bash", "-c", "cliphist wipe"]); clipModel.clear(); root.active = false }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                Rectangle {
                    Layout.fillWidth: true; height: 42; radius: 14; color: Theme.background
                    border.color: searchField.activeFocus ? Theme.primary : "transparent"; border.width: 1.5
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                        Text { text: "󰍉"; color: Theme.primary; opacity: searchField.activeFocus ? 0.9 : 0.4; font.pixelSize: 16 }
                        TextField {
                            id: searchField; Layout.fillWidth: true
                            placeholderText: "Search history..."
                            placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                            color: Theme.primary; font.pixelSize: 13; background: Item {}
                            onTextChanged: { root.searchText = text; searchDelay.restart() }
                        }
                        Text {
                            text: "󰅖"; color: Theme.primary; font.pixelSize: 14; opacity: 0.4
                            visible: searchField.text.length > 0
                            MouseArea { anchors.fill: parent; onClicked: { searchField.text = ""; searchField.forceActiveFocus() } }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; color: "transparent"; clip: true

                    ListView {
                        id: listView; anchors.fill: parent; model: clipModel
                        spacing: 8; boundsBehavior: Flickable.StopAtBounds; cacheBuffer: 200

                        Item {
                            anchors.centerIn: parent; visible: clipModel.count === 0
                            width: listView.width; height: 120
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 8
                                Text { text: "󰅌"; color: Theme.primary; opacity: 0.2; font.pixelSize: 40; Layout.alignment: Qt.AlignHCenter }
                                Text {
                                    text: root.searchText !== "" ? "No results found" : "Nothing copied yet"
                                    color: Theme.primary; opacity: 0.3; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        delegate: Rectangle {
                            id: itemCard
                            width: listView.width; height: 55; radius: 15
                            color: Theme.background
                            opacity: copyMouse.containsMouse ? 0.8 : 1
                            border.color: Theme.primary
                            border.width: copyMouse.containsMouse ? 1 : 0

                            Rectangle {
                                width: 3; height: parent.height - 16
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                radius: 2; color: Theme.primary
                                opacity: model.preview.startsWith("[[") ? 0.5 : 0.0
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 10; spacing: 12

                                Text {
                                    text: model.preview.startsWith("[[") ? "󰋼" : "󰆒"
                                    color: Theme.primary; opacity: 0.35; font.pixelSize: 14
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Item {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    Text {
                                        anchors.fill: parent; text: model.preview
                                        color: Theme.primary; font.pixelSize: 13
                                        elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                    }
                                    MouseArea {
                                        id: copyMouse; anchors.fill: parent; hoverEnabled: true
                                        onEntered: {
                                            hidePreviewTimer.stop()
                                            root.hoveredClipId = model.clipId
                                            root.hoveredPreview = model.preview
                                            root.hoveredIsImage = model.preview.startsWith("[[")
                                            root.decodedImagePath = ""
                                            if (root.hoveredIsImage) decodeDebounce.restart()
                                        }
                                        onExited: hidePreviewTimer.restart()
                                        onClicked: {
                                            clipExec.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist decode | wl-copy"])
                                            root.active = false
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 36; height: 36; radius: 10
                                    color: delMouse.containsMouse ? "#ff5555" : "transparent"
                                    Text {
                                        anchors.centerIn: parent; text: "󰆴"
                                        color: delMouse.containsMouse ? "#ffffff" : Theme.primary
                                        opacity: delMouse.containsMouse ? 1.0 : 0.6; font.pixelSize: 16
                                    }
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
                            contentItem: Rectangle { implicitWidth: 3; radius: 2; color: Theme.primary; opacity: 0.25 }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Click to copy  ·  Click on bin to delete"
                    color: Theme.primary; opacity: 0.25; font.pixelSize: 10; Layout.bottomMargin: 2
                }
            }
        }
    }
}