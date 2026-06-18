import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Keyboard"
    subheading: "Input layout and language"
    icon: "󰌌"

    property bool active: false
    property string layout: "us"
    property string variant: ""

    onActiveChanged: if (active) reader.running = true

    readonly property var common: [
        { code: "us", name: "English (US)" },
        { code: "gb", name: "English (UK)" },
        { code: "fr", name: "French" },
        { code: "de", name: "German" },
        { code: "es", name: "Spanish" },
        { code: "it", name: "Italian" },
        { code: "ch", name: "Swiss" },
        { code: "ca", name: "Canadian" }
    ]

    Process {
        id: reader
        command: ["bash", "-c",
            "l=$(grep -E 'kb_layout\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); " +
            "v=$(grep -E 'kb_variant\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); " +
            "echo \"${l:-us}|${v}\""]
        stdout: SplitParser {
            onRead: {
                let p = data.trim().split("|")
                page.layout = (p[0] || "us").toLowerCase()
                page.variant = (p[1] || "").toLowerCase()
            }
        }
    }

    Process { id: applyProc; onRunningChanged: if (!running) reader.running = true }

    function apply(code, variant) {
        let lc = (code || "").toLowerCase()
        let lv = (variant || "").toLowerCase()
        let cmd = "sed -i -E 's/kb_layout\\s*=\\s*\".*\"/kb_layout  = \"" + lc + "\"/' ~/.config/hypr/input.lua && " +
                  "sed -i -E 's/kb_variant\\s*=\\s*\".*\"/kb_variant = \"" + lv + "\"/' ~/.config/hypr/input.lua && hyprctl reload"
        applyProc.command = ["bash", "-c", cmd]
        applyProc.running = true
    }

    StCard {
        StRow {
            icon: "󰌌"
            title: "Current layout"
            subtitle: page.layout.toUpperCase() + (page.variant !== "" ? " (" + page.variant + ")" : "")
            Rectangle {
                Layout.preferredWidth: 54; Layout.preferredHeight: 30; radius: 9
                color: Theme.primary
                Text { anchors.centerIn: parent; text: page.layout.toUpperCase(); color: Theme.background; font.pixelSize: 13; font.bold: true }
            }
        }
    }

    StCard {
        title: "Common layouts"
        GridLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: page.common
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 11
                    property bool isCur: page.layout === modelData.code && page.variant === ""
                    color: isCur ? Theme.primary
                         : (chipMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05))
                    border.color: isCur ? "transparent" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 130 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        Text { text: modelData.code.toUpperCase(); color: parent.parent.isCur ? Theme.background : Theme.primary; font.pixelSize: 13; font.bold: true; Layout.preferredWidth: 30 }
                        Text { text: modelData.name; color: parent.parent.isCur ? Theme.background : Theme.primary; opacity: parent.parent.isCur ? 1.0 : 0.7; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.apply(modelData.code, "") }
                }
            }
        }
    }

    StCard {
        title: "Custom"
        StRow {
            icon: "󰌌"
            title: "Layout / variant"
            subtitle: "e.g. layout “fr”, variant “oss” or “intl”"
            Rectangle {
                Layout.preferredWidth: 90; implicitHeight: 34; radius: 9
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                border.color: layoutInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                border.width: 1
                TextField {
                    id: layoutInput
                    anchors.fill: parent
                    anchors.margins: 2
                    text: page.layout
                    placeholderText: "layout"
                    color: Theme.primary
                    font.pixelSize: 13
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                }
            }
            Rectangle {
                Layout.preferredWidth: 110; implicitHeight: 34; radius: 9
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                border.color: variantInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                border.width: 1
                TextField {
                    id: variantInput
                    anchors.fill: parent
                    anchors.margins: 2
                    text: page.variant
                    placeholderText: "variant"
                    color: Theme.primary
                    font.pixelSize: 13
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    onAccepted: page.apply(layoutInput.text.trim(), variantInput.text.trim())
                }
            }
            StButton {
                text: "Apply"; accent: true; implicitHeight: 34
                onClicked: page.apply(layoutInput.text.trim(), variantInput.text.trim())
            }
        }
    }

    StCard {
        StRow {
            icon: "󰍉"
            title: "Full layout switcher"
            subtitle: "Browse all layouts and variants"
            clickable: true
            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "bar-keyboard", "open"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
        StRow {
            icon: "󰷈"
            title: "Edit input.lua"
            subtitle: "Repeat rate, options and more"
            clickable: true
            onClicked: Quickshell.execDetached(["bash", "-c", "kitty -e sh -c '${EDITOR:-nano} ~/.config/hypr/input.lua'"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
