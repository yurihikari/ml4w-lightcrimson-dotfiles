import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "System"
    subheading: "About this system"
    icon: "󰒓"

    property bool active: false
    property var info: ({})

    onActiveChanged: if (active) { reader._buf = ""; reader.running = true }

    Process {
        id: reader
        property string _buf: ""
        command: ["bash", "-c",
            "echo \"host=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)\"\n" +
            "echo \"user=$USER\"\n" +
            "( . /etc/os-release 2>/dev/null; echo \"os=$PRETTY_NAME\" )\n" +
            "echo \"kernel=$(uname -r)\"\n" +
            "echo \"cpu=$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ //')\"\n" +
            "echo \"gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | sed 's/.*: //')\"\n" +
            "echo \"mem=$(awk '/MemTotal/{printf \"%.1f GB\", $2/1024/1024}' /proc/meminfo)\"\n" +
            "echo \"uptime=$(uptime -p 2>/dev/null | sed 's/up //')\"\n" +
            "echo \"wm=Hyprland $(hyprctl version 2>/dev/null | awk '/^Tag:/{print $2}' | head -1)\"\n" +
            "echo \"shell=$(basename $SHELL)\""
        ]
        stdout: SplitParser { onRead: reader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let info = {}
            for (let l of reader._buf.trim().split("\n")) {
                let i = l.indexOf("="); if (i < 1) continue
                info[l.substring(0, i)] = l.substring(i + 1).trim()
            }
            page.info = info
            reader._buf = ""
        }
    }

    StCard {
        title: "About"
        StRow { icon: "󰌢"; title: "Device name"; subtitle: page.info.host || "—" }
        StRow { icon: "󰣇"; title: "Operating system"; subtitle: page.info.os || "—" }
        StRow { icon: "󰣖"; title: "Kernel"; subtitle: page.info.kernel || "—" }
        StRow { icon: "󰧨"; title: "Window manager"; subtitle: page.info.wm || "—" }
        StRow { icon: "󰆍"; title: "Shell"; subtitle: page.info.shell || "—" }
        StRow { icon: "󰅐"; title: "Uptime"; subtitle: page.info.uptime || "—" }
    }

    StCard {
        title: "Hardware"
        StRow { icon: "󰻠"; title: "Processor"; subtitle: page.info.cpu || "—" }
        StRow { icon: "󰢮"; title: "Graphics"; subtitle: page.info.gpu || "—" }
        StRow { icon: "󰍛"; title: "Memory"; subtitle: page.info.mem || "—" }
    }

    StCard {
        title: "Tools"
        StRow {
            icon: "󰋊"
            title: "System info"
            subtitle: "Open the ML4W system info tool"
            clickable: true
            onClicked: Quickshell.execDetached(["bash", "-c", Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-hyprsysteminfo"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
        StRow {
            icon: "󰓅"
            title: "Resource monitor"
            subtitle: "Open btop / htop in a terminal"
            clickable: true
            onClicked: Quickshell.execDetached(["bash", "-c", "kitty --class dotfiles-floating -e sh -c 'btop || htop'"])
            Text { text: "󰁔"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
        }
    }
}
