import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    property string currentTab: "Connectivity"
    visible: active
    
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: popup.active = false }

    Rectangle {
        id: container
        width: 320; height: 420
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 15
        radius: 24; color: Theme.background; border.color: Theme.primary; border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 15; spacing: 15

            // TAB SWITCHER
            Rectangle {
                Layout.fillWidth: true; height: 40; radius: 12; color: Theme.surface_container_high
                Row {
                    anchors.fill: parent; anchors.margins: 4; spacing: 4
                    Repeater {
                        model: ["Connectivity", "Performance"]
                        Rectangle {
                            width: (parent.width - 4) / 2; height: parent.height
                            radius: 8; color: popup.currentTab === modelData ? Theme.primary : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData; color: popup.currentTab === modelData ? Theme.background : Theme.primary
                                font.bold: true; font.pixelSize: 12
                            }
                            MouseArea { anchors.fill: parent; onClicked: popup.currentTab = modelData }
                        }
                    }
                }
            }

            // TAB CONTENT: CONNECTIVITY
            ColumnLayout {
                visible: popup.currentTab === "Connectivity"
                Layout.fillWidth: true; spacing: 15

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    RowLayout {
                        Text { text: "󰤨  Wi-Fi"; color: Theme.primary; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 36; height: 20; radius: 10; color: sysInfo.wifi !== "Offline" ? Theme.primary : Theme.surface_container_high
                            Rectangle { x: sysInfo.wifi !== "Offline" ? 18 : 2; y: 2; width: 16; height: 16; radius: 8; color: Theme.background; Behavior on x { NumberAnimation { duration: 200 } } }
                            MouseArea { anchors.fill: parent; onClicked: executor.run(["bash", "-c", sysInfo.wifi !== "Offline" ? "nmcli radio wifi off" : "nmcli radio wifi on"]) }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 45; radius: 12; color: Theme.surface_container_high
                        Text { anchors.centerIn: parent; text: sysInfo.wifi; color: Theme.primary; font.bold: true; font.pixelSize: 12; elide: Text.ElideRight; width: 250 }
                    }
                    Rectangle { Layout.fillWidth: true; height: 35; radius: 10; border.color: Theme.primary; border.width: 1; color: "transparent"
                        Text { anchors.centerIn: parent; text: "Network Settings"; color: Theme.primary; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; onClicked: { executor.run(["kitty", "--class", "floating", "nmtui"]); popup.active = false; } }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    RowLayout {
                        Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 36; height: 20; radius: 10; color: sysInfo.bluetooth ? Theme.primary : Theme.surface_container_high
                            Rectangle { x: sysInfo.bluetooth ? 18 : 2; y: 2; width: 16; height: 16; radius: 8; color: Theme.background; Behavior on x { NumberAnimation { duration: 200 } } }
                            MouseArea { anchors.fill: parent; onClicked: executor.run(["bash", "-c", sysInfo.bluetooth ? "bluetoothctl power off" : "bluetoothctl power on"]) }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 35; radius: 10; border.color: Theme.primary; border.width: 1; color: "transparent"
                        Text { anchors.centerIn: parent; text: "Bluetooth Manager"; color: Theme.primary; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; onClicked: { executor.run(["blueman-manager"]); popup.active = false; } }
                    }
                }
            }

            // TAB CONTENT: PERFORMANCE
            ColumnLayout {
                visible: popup.currentTab === "Performance"
                Layout.fillWidth: true; spacing: 20

                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 30
                    
                    component PerfBar: ColumnLayout {
                        property string label: ""; property real value: 0.0; property string icon: ""
                        spacing: 8
                        Rectangle {
                            width: 24; height: 180; radius: 12; color: Theme.surface_container_high
                            Rectangle {
                                anchors.bottom: parent.bottom; width: 24; radius: 12
                                height: parent.height * Math.max(0.05, value); color: Theme.primary
                                Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                            }
                        }
                        Text { text: icon; color: Theme.primary; font.pixelSize: 16; Layout.alignment: Qt.AlignHCenter }
                        Text { text: Math.round(value * 100) + "%"; color: Theme.primary; font.pixelSize: 11; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                    }

                    PerfBar { label: "CPU"; icon: "󰻠"; value: sysInfo.cpuUsage }
                    PerfBar { label: "RAM"; icon: "󰍛"; value: sysInfo.ramUsage }
                    PerfBar { label: "DISK"; icon: "󰋊"; value: sysInfo.diskUsage }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 40; radius: 12; color: Theme.primary
                    Text { anchors.centerIn: parent; text: "Open ML4W Monitor"; color: Theme.background; font.bold: true; font.pixelSize: 11 }
                    MouseArea { 
                        anchors.fill: parent
                        onClicked: { 
                            executor.run(["bash", "-c", "~/.config/ml4w/settings/system-monitor.sh"]); 
                            popup.active = false; 
                        } 
                    }
                }
            }
        }
    }
}