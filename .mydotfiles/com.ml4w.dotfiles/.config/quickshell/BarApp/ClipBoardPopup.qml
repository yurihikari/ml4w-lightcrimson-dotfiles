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
    
    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    
    // THE FIX: Changed to OnDemand so the Search Bar can take focus
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    
    color: "transparent"

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.active = false
        }
    }

    // --- CLIPBOARD ENGINE ---
    ListModel { id: clipModel }

    Process {
        id: clipLoader
        // If search is empty, list all. If not, pipe through grep.
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

    // Debounce Timer: Waits 200ms after you stop typing to search
    // This prevents lag with 600+ items
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

    Rectangle {
        id: container
        width: 400
        height: 600 // Increased height for search bar room
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.right: parent.right
        anchors.rightMargin: 155
        
        radius: 30
        color: Theme.background
        border.color: Theme.primary
        border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 15

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                Text { 
                    text: "󰅌  Clipboard"
                    color: Theme.primary
                    font.pixelSize: 16
                    font.bold: true 
                }
                Item { Layout.fillWidth: true }
                Text { 
                    text: "󰃢"
                    color: Theme.primary
                    font.pixelSize: 18
                    opacity: 0.6
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            executor.run(["bash", "-c", "cliphist wipe"])
                            clipModel.clear()
                            root.active = false
                        }
                    }
                }
            }

            // --- SEARCH BAR ---
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 12
                color: Theme.surface_container_high
                border.color: searchField.activeFocus ? Theme.primary : "transparent"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    
                    Text { 
                        text: "󰍉"
                        color: Theme.primary
                        opacity: 0.5
                        font.pixelSize: 14 
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search history..."
                        color: Theme.primary
                        font.pixelSize: 13
                        background: Item {} // Remove default styling
                        
                        onTextChanged: {
                            root.searchText = text
                            searchDelay.restart()
                        }

                        // Close on Enter if an item is selected, or just for convenience
                        onAccepted: root.active = false 
                    }

                    Text {
                        text: "󰅖"
                        color: Theme.primary
                        visible: searchField.text !== ""
                        opacity: 0.5
                        MouseArea {
                            anchors.fill: parent
                            onClicked: searchField.text = ""
                        }
                    }
                }
            }

            // --- LIST ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.surface_container_high
                radius: 20
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: 8
                    model: clipModel
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 100 

                    // Empty State logic
                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0 && !clipLoader.running
                        text: "No matches found"
                        color: Theme.primary
                        opacity: 0.3
                    }

                    delegate: Rectangle {
                        width: listView.width
                        height: 45
                        radius: 12
                        color: itemMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 10
                            spacing: 10
                            
                            Text { 
                                text: model.preview
                                color: Theme.primary
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true 
                            }
                            
                            Text { 
                                text: "󰆴"
                                color: Theme.primary
                                opacity: 0.4
                                font.pixelSize: 14 
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        executor.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist delete"])
                                        clipModel.remove(index)
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                executor.run(["bash", "-c", "echo '" + model.clipId + "\t" + model.preview + "' | cliphist decode | wl-copy"])
                                root.active = false
                            }
                        }
                    }
                    
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: Theme.primary
                            opacity: 0.3
                        }
                    }
                }
            }
        }
    }
}