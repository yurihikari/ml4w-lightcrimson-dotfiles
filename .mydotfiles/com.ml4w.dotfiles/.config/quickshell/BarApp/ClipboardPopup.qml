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
    
    // Multi-monitor support passed from MainBar
    screen: modelData 

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

    // --- LOGIC (UNTOUCHED) ---
    Process {
        id: clipExec
        function run(args) {
            command = args
            running = true
        }
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
        width: 450
        height: 600
        anchors.top: parent.top
        anchors.topMargin: 45
        anchors.right: parent.right
        anchors.rightMargin: 155
        
        radius: 30
        color: "transparent"
        border.color: "transparent"
        border.width: 2

        // Background rectangle with reduced opacity for blur effect
        // Matching your MediaPopup reference
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8 
        }

        MouseArea { 
            anchors.fill: parent 
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 20

            // HEADER
            RowLayout {
                Layout.fillWidth: true
                Text { 
                    text: "󰅌  Clipboard History"
                    color: Theme.primary
                    font.pixelSize: 18
                    font.bold: true 
                }
                Item { Layout.fillWidth: true }
                
                // Clear All Button
                Rectangle {
                    width: 38; height: 38; radius: 19
                    color: Theme.background
                    Text { anchors.centerIn: parent; text: "󰃢"; color: Theme.primary; font.pixelSize: 16 }
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

            // SEARCH BAR
            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 15
                color: Theme.background
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 15
                    Text { text: "󰍉"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        color: Theme.primary
                        font.pixelSize: 14
                        background: Item {} 
                        onTextChanged: {
                            root.searchText = text
                            searchDelay.restart()
                        }
                    }
                }
            }

            // LIST
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
                    cacheBuffer: 100 

                    delegate: Rectangle {
                        width: listView.width
                        height: 50
                        radius: 12
                        color: Theme.background
                        opacity: copyMouse.containsMouse ? 1.0 : 0.8

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 8
                            spacing: 0

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
                                width: 34; height: 34; radius: 10
                                color: "red"
                                opacity: delMouse.containsMouse ? 1.0 : 0.5
                                
                                Text { 
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: "white"
                                    font.pixelSize: 14 
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
                            implicitWidth: 4; radius: 2; 
                            color: Theme.primary; opacity: 0.2
                        }
                    }
                }
            }
        }
    }
}