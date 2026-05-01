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
        width: 320; height: 440
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 15
        radius: 24; color: "transparent"

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
            anchors.fill: parent; anchors.margins: 16; spacing: 12

            // TAB SWITCHER
            Rectangle {
                Layout.fillWidth: true; height: 38; radius: 12; color: Theme.background
                Row {
                    anchors.fill: parent; anchors.margins: 4; spacing: 4
                    Repeater {
                        model: ["Connectivity", "Performance"]
                        Rectangle {
                            width: (parent.width - 4) / 2; height: parent.height
                            radius: 8
                            color: popup.currentTab === modelData ? Theme.primary : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: popup.currentTab === modelData ? Theme.background : Theme.primary
                                font.bold: true; font.pixelSize: 12
                            }
                            MouseArea { anchors.fill: parent; onClicked: popup.currentTab = modelData }
                        }
                    }
                }
            }

            // ── CONNECTIVITY TAB ──────────────────────────────────────
            ColumnLayout {
                visible: popup.currentTab === "Connectivity"
                Layout.fillWidth: true; spacing: 12

                // ETHERNET (shown only when connected)
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    visible: sysInfo.connType === "ethernet"

                    RowLayout {
                        Text { text: "󰈀  Ethernet"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: Theme.primary
                        }
                        Text { text: "Connected"; color: Theme.primary; font.pixelSize: 11; opacity: 0.7 }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: 12; color: Theme.background
                        RowLayout {
                            anchors.centerIn: parent; spacing: 8
                            Text { text: "󰈀"; color: Theme.primary; font.pixelSize: 16 }
                            Text { text: "Wired Connection"; color: Theme.primary; font.pixelSize: 12; font.bold: true }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }
                }

                // WI-FI
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8

                    RowLayout {
                        Text { text: "󰤨  Wi-Fi"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }

                        // FIX: use connType for state, use a bordered track when off
                        property bool wifiOn: sysInfo.connType === "wifi"
                        Rectangle {
                            id: wifiToggle
                            width: 40; height: 22; radius: 11
                            color: sysInfo.wifiRadio ? Theme.primary : "transparent"
                            border.color: Theme.primary
                            border.width: 2

                            Rectangle {
                                x: sysInfo.wifiRadio ? parent.width - width - 3 : 3
                                y: 3; width: 16; height: 16; radius: 8
                                color: sysInfo.wifiRadio ? Theme.background : Theme.primary
                                Behavior on x { NumberAnimation { duration: 200 } }
                            }
                            MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                executor.run(["bash", "-c", sysInfo.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"])
                                // Wait briefly for nmcli to apply, then force re-poll
                                repollTimer.restart()
                            }
                        }
                        }
                    }

                    // Status box — shows SSID when connected, hint when off
                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: 12
                        color: Theme.background
                        RowLayout {
                            anchors.centerIn: parent; spacing: 8
                            Text {
                                text: sysInfo.wifiRadio && sysInfo.wifi !== "" ? "󰤨" : "󰤭"
                                color: Theme.primary; font.pixelSize: 16
                                opacity: sysInfo.wifiRadio && sysInfo.wifi !== "" ? 1.0 : 0.4
                            }
                            Text {
                                text: sysInfo.wifiRadio && sysInfo.wifi !== ""
                                    ? sysInfo.wifi
                                    : "Not connected"
                                color: Theme.primary; font.pixelSize: 12; font.bold: true
                                opacity: sysInfo.wifiRadio && sysInfo.wifi !== "" ? 1.0 : 0.4
                                elide: Text.ElideRight; width: 200
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 10
                        border.color: Theme.primary; border.width: 1; color: "transparent"
                        Text { anchors.centerIn: parent; text: "Network Settings"; color: Theme.primary; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { executor.run(["kitty", "--class", "floating", "nmtui"]); popup.active = false }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                // BLUETOOTH
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8

                    RowLayout {
                        Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: btToggle
                            width: 40; height: 22; radius: 11
                            color: sysInfo.bluetooth ? Theme.primary : "transparent"
                            border.color: Theme.primary
                            border.width: 2

                            Rectangle {
                                x: sysInfo.bluetooth ? parent.width - width - 3 : 3
                                y: 3; width: 16; height: 16; radius: 8
                                color: sysInfo.bluetooth ? Theme.background : Theme.primary
                                Behavior on x { NumberAnimation { duration: 200 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: executor.run(["bash", "-c", sysInfo.bluetooth ? "bluetoothctl power off" : "bluetoothctl power on"])
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 10
                        border.color: Theme.primary; border.width: 1; color: "transparent"
                        Text { anchors.centerIn: parent; text: "Bluetooth Manager"; color: Theme.primary; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { executor.run(["blueman-manager"]); popup.active = false }
                        }
                    }
                }
            }

            // ── PERFORMANCE TAB ───────────────────────────────────────
            ColumnLayout {
                visible: popup.currentTab === "Performance"
                Layout.fillWidth: true; spacing: 20

                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 30

                    component PerfBar: ColumnLayout {
                        property string label: ""; property real value: 0.0; property string icon: ""
                        spacing: 8
                        Rectangle {
                            width: 24; height: 180; radius: 12; color: Theme.background
                            Rectangle {
                                anchors.bottom: parent.bottom; width: 24; radius: 12
                                height: parent.height * Math.max(0.05, value)
                                color: value > 0.85 ? "#e06c75" : Theme.primary
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
                    Text { anchors.centerIn: parent; text: "Open System Monitor"; color: Theme.background; font.bold: true; font.pixelSize: 11 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { executor.run(["bash", "-c", "~/.config/ml4w/settings/system-monitor.sh"]); popup.active = false }
                    }
                }
            }
        }
    }
}