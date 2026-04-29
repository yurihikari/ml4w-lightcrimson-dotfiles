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
    visible: active
    
    anchors { 
        top: true; bottom: true
        left: true; right: true 
    }
    
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
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
        command: ["cliphist", "list"]
        stdout: SplitParser {
            // We removed the 'split' property to avoid the error. 
            // Most versions default to newline splitting.
            onRead: {
                let line = data.trim()
                if (line.length === 0) return
                
                // cliphist output is "ID[tab]Content"
                let splitIdx = line.indexOf("\t")
                if (splitIdx !== -1) {
                    let id = line.substring(0, splitIdx)
                    let content = line.substring(splitIdx + 1)
                    clipModel.append({ "clipId": id, "preview": content })
                }
            }
        }
    }

    onActiveChanged: {
        if (active) {
            clipModel.clear()
            clipLoader.running = true
        }
    }

    Rectangle {
        id: container
        width: 400
        height: 550
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

            RowLayout {
                Layout.fillWidth: true
                Text { 
                    text: "󰅌  Clipboard History"
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