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
    visible: active
    
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

    // --- LOGIC (UNTOUCHED) ---
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
                if (splitIdx !== -1) {
                    let id = line.substring(0, splitIdx)
                    let content = line.substring(splitIdx + 1)
                    clipModel.append({ "clipId": id, "preview": content })
                }
            }
        }
    }

    Timer {
        id: searchDelay
        interval: 200
        onTriggered: {
            clipModel.clear()
            clipLoader.running = true
        }
    }

    onActiveChanged: {
        if (active) {
            root.searchText = ""
            searchField.forceActiveFocus()
            clipModel.clear()
            clipLoader.running = true
        }
    }

    // --- UI CONTAINER ---
    Rectangle {
        id: container
        width: 420
        height: 620
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.right: parent.right
        anchors.rightMargin: 155
        
        radius: 30
        color: "transparent"

        // Layered background — matches media popup style
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                // Icon badge
                Rectangle {
                    width: 36; height: 36; radius: 10
                    color: Theme.primary; opacity: 0.15
                    Text {
                        anchors.centerIn: parent
                        text: "󰅌"
                        color: Theme.primary
                        font.pixelSize: 18
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: "Clipboard"
                        color: Theme.primary
                        font.pixelSize: 18
                        font.bold: true
                    }
                    Text {
                        text: clipModel.count + " entries"
                        color: Theme.primary
                        font.pixelSize: 10
                        opacity: 0.45
                    }
                }

                Item { Layout.fillWidth: true }

                // Clear all — pill button
                Rectangle {
                    width: 80; height: 30; radius: 15
                    color: Theme.background
                    border.color: Theme.primary
                    border.width: 1
                    opacity: clearMouse.containsMouse ? 1.0 : 0.7

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: "󰃢"; color: Theme.primary; font.pixelSize: 12 }
                        Text { text: "Clear"; color: Theme.primary; font.pixelSize: 11; font.bold: true }
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            clipExec.run(["bash", "-c", "cliphist wipe"])
                            clipModel.clear()
                            root.active = false
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.primary
                opacity: 0.1
            }

            // --- SEARCH BAR ---
            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: 14
                color: Theme.background
                border.color: searchField.activeFocus ? Theme.primary : "transparent"
                border.width: 1.5

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 8

                    Text {
                        text: "󰍉"
                        color: Theme.primary
                        opacity: searchField.activeFocus ? 0.9 : 0.4
                        font.pixelSize: 16
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search history..."
                        placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                        color: Theme.primary
                        font.pixelSize: 13
                        background: Item {}
                        onTextChanged: {
                            root.searchText = text
                            searchDelay.restart()
                        }
                    }

                    // Clear search X
                    Text {
                        text: "󰅖"
                        color: Theme.primary
                        font.pixelSize: 14
                        opacity: 0.4
                        visible: searchField.text.length > 0
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { searchField.text = ""; searchField.forceActiveFocus() }
                        }
                    }
                }
            }

            // --- LIST ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    model: clipModel
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 200

                    // Empty state
                    Item {
                        anchors.centerIn: parent
                        visible: clipModel.count === 0
                        width: listView.width
                        height: 120

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "󰅌"
                                color: Theme.primary; opacity: 0.2
                                font.pixelSize: 40
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: root.searchText !== "" ? "No results found" : "Nothing copied yet"
                                color: Theme.primary; opacity: 0.3
                                font.pixelSize: 13
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: itemCard
                        width: listView.width
                        height: 55
                        radius: 15
                        color: Theme.background
                        opacity: copyMouse.containsMouse ? 0.8 : 1
                        border.color: Theme.primary
                        border.width: copyMouse.containsMouse ? 1 : 0

                        // Subtle left accent for binary/image entries
                        Rectangle {
                            width: 3; height: parent.height - 16
                            anchors.left: parent.left; anchors.leftMargin: 0
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 2
                            color: Theme.primary
                            opacity: model.preview.startsWith("[[") ? 0.5 : 0.0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15; anchors.rightMargin: 10
                            spacing: 12

                            // Type icon
                            Text {
                                text: model.preview.startsWith("[[") ? "󰋼" : "󰆒"
                                color: Theme.primary
                                opacity: 0.35
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Text {
                                    anchors.fill: parent
                                    text: model.preview
                                    color: Theme.primary
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                                MouseArea {
                                    id: copyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        clipExec.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist decode | wl-copy"])
                                        root.active = false
                                    }
                                }
                            }

                            // Individual Delete Button
                            Rectangle {
                                width: 36; height: 36; radius: 10
                                color: delMouse.containsMouse ? "#ff5555" : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: delMouse.containsMouse ? "#ffffff" : Theme.primary
                                    opacity: delMouse.containsMouse ? 1.0 : 0.6
                                    font.pixelSize: 16
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        clipExec.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist delete"])
                                        clipModel.remove(index)
                                    }
                                }
                            }
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 3; radius: 2
                            color: Theme.primary; opacity: 0.25
                        }
                    }
                }
            }

            // --- FOOTER ---
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.primary
                opacity: 0.1
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Click to copy  ·  Click on bin to delete"
                color: Theme.primary
                opacity: 0.25
                font.pixelSize: 10
                Layout.bottomMargin: 2
            }
        }
    }
}
