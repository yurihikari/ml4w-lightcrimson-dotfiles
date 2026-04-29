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
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.active = false
        }
    }

    // Local Executor for clipboard actions
    Process {
        id: clipExec
        function run(args) {
            command = args
            running = true
        }
    }

    // --- CLIPBOARD ENGINE ---
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

    Rectangle {
        id: container
        width: 400
        height: 600
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.right: parent.right
        anchors.rightMargin: 155
        
        radius: 30
        color: Theme.background
        border.color: Theme.primary
        border.width: 1

        MouseArea { anchors.fill: parent } // Block click-through

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 15

            // --- HEADER ---
            RowLayout {
                Layout.fillWidth: true
                Text { text: "󰅌  Clipboard History"; color: Theme.primary; font.pixelSize: 16; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { 
                    text: "󰃢"
                    color: Theme.primary; font.pixelSize: 18; opacity: 0.6
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            clipExec.run(["bash", "-c", "cliphist wipe"])
                            clipModel.clear()
                            root.active = false
                        }
                    }
                }
            }

            // --- SEARCH BAR ---
            Rectangle {
                Layout.fillWidth: true; height: 40; radius: 12
                color: Theme.surface_container_high
                border.color: searchField.activeFocus ? Theme.primary : "transparent"
                border.width: 1

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                    Text { text: "󰍉"; color: Theme.primary; opacity: 0.5; font.pixelSize: 14 }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search history..."
                        color: Theme.primary
                        font.pixelSize: 13
                        background: Item {} 
                        onTextChanged: {
                            root.searchText = text
                            searchDelay.restart()
                        }
                    }
                }
            }

            // --- LIST ---
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.surface_container_high; radius: 20; clip: true

                ListView {
                    id: listView
                    anchors.fill: parent; anchors.margins: 8
                    model: clipModel
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 100 

                    delegate: Rectangle {
                        width: listView.width; height: 45; radius: 12
                        color: "transparent"

                        // Row structure to separate Copy and Delete areas
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            spacing: 0

                            // 1. CLICK TO COPY AREA (Text)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Rectangle {
                                    anchors.fill: parent; radius: 10; 
                                    color: Theme.primary; opacity: copyMouse.containsMouse ? 0.1 : 0
                                }

                                Text { 
                                    anchors.fill: parent; anchors.leftMargin: 10
                                    text: model.preview; color: Theme.primary; font.pixelSize: 12
                                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
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

                            // 2. DELETE BUTTON AREA
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.fillHeight: true
                                color: "transparent"
                                radius: 10

                                Rectangle {
                                    anchors.fill: parent; radius: 10; 
                                    color: "#ff5555"; opacity: delMouse.containsMouse ? 0.2 : 0
                                }

                                Text { 
                                    anchors.centerIn: parent
                                    text: "󰆴"; color: delMouse.containsMouse ? "#ff5555" : Theme.primary
                                    opacity: delMouse.containsMouse ? 1.0 : 0.4; font.pixelSize: 14 
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
                        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Theme.primary; opacity: 0.2 }
                    }
                }
            }
        }
    }
}