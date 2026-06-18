import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Printers"
    subheading: "Printers and print queues (CUPS)"
    icon: "󰐪"

    property bool active: false
    property var printers: []
    property string defaultPrinter: ""
    property bool hasTool: false

    onActiveChanged: if (active) refresh()

    function refresh() { reader._buf = ""; reader.running = true; toolCheck.running = true }

    Process {
        id: toolCheck
        command: ["bash", "-c", "command -v system-config-printer >/dev/null 2>&1 && echo yes || echo no"]
        stdout: SplitParser { onRead: page.hasTool = (data.trim() === "yes") }
    }

    Process {
        id: reader
        property string _buf: ""
        command: ["bash", "-c",
            "def=$(lpstat -d 2>/dev/null | sed -n 's/.*: //p')\n" +
            "printf 'DEFAULT\\x1f%s\\n' \"$def\"\n" +
            "lpstat -p 2>/dev/null | while read -r kw name rest; do\n" +
            "  [ \"$kw\" = \"printer\" ] || continue\n" +
            "  state=$(echo \"$rest\" | grep -oE 'idle|printing|disabled' | head -1)\n" +
            "  printf 'P\\x1f%s\\x1f%s\\n' \"$name\" \"${state:-unknown}\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: reader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let list = [], def = ""
            for (let l of reader._buf.trim().split("\n")) {
                let p = l.split("\x1f")
                if (p[0] === "DEFAULT") def = (p[1] || "").trim()
                else if (p[0] === "P" && p.length >= 3) list.push({ name: p[1].trim(), state: p[2].trim() })
            }
            page.defaultPrinter = def
            page.printers = list
            reader._buf = ""
        }
    }

    StCard {
        title: "Printers"

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "transparent"
            visible: page.printers.length === 0
            Text { anchors.centerIn: parent; text: "No printers configured"; color: Theme.primary; opacity: 0.4; font.pixelSize: 12 }
        }

        Repeater {
            model: page.printers
            delegate: StRow {
                required property var modelData
                icon: "󰐪"
                title: modelData.name + (modelData.name === page.defaultPrinter ? "  ·  Default" : "")
                subtitle: modelData.state.charAt(0).toUpperCase() + modelData.state.slice(1)
                Rectangle {
                    width: 9; height: 9; radius: 4.5
                    color: modelData.state === "disabled" ? "#e06c75" : "#a6e3a1"
                }
            }
        }
    }

    StCard {
        title: "Manage"
        StRow {
            icon: "󰖟"
            title: "Open CUPS web interface"
            subtitle: "http://localhost:631"
            clickable: true
            onClicked: Quickshell.execDetached(["xdg-open", "http://localhost:631"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
        StRow {
            visible: page.hasTool
            icon: "󰐪"
            title: "Printer settings"
            subtitle: "Add and configure printers"
            clickable: true
            onClicked: Quickshell.execDetached(["system-config-printer"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
        StRow {
            icon: "󰑓"
            title: "Refresh"
            clickable: true
            onClicked: page.refresh()
            Text { text: "󰑓"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
