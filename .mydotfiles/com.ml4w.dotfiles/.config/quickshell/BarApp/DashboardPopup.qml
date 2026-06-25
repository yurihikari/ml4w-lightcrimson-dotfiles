import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

BarPopup {
    id: popup
    ipcTarget: "bar-dashboard"
    onOpened: {
        infoLoader.running = true        // fast core info (os, host, uptime, disks)
        updatesLoader.running = true     // slow update count — runs independently
    }

    // Keyboard focus handler for ESC
    FocusScope {
        anchors.fill: parent
        focus: popup.active
        Keys.onEscapePressed: popup.active = false
    }

    // ─── State (filled by Processes below) ────────────────────────────────
    property string osName:     ""
    property string osVersion:  ""
    property string osIconHint: ""
    property string osLogoPath: ""
    property string hostname:   ""
    property string username:   ""
    property string osAge:      ""
    property string kernelStr:  ""
    property string uptimeStr:  ""

    property string homeDir: ""
    property string docsDir: ""
    property string picsDir: ""
    property string vidsDir: ""
    property string musicDir: ""

    // New Data State
    // Mounted disks: root + anything under /mnt, /media, /run/media (USB keys, etc.)
    // Each entry: { label, pct, used, total, mount }
    property var    disks:      []
    property string updates:    "0"

    // Live clock used for the greeting line.
    property var now: new Date()
    Timer { interval: 60000; repeat: true; running: popup.active; onTriggered: popup.now = new Date() }
    function greeting() {
        var h = now.getHours()
        if (h < 5)  return "Good night"
        if (h < 12) return "Good morning"
        if (h < 18) return "Good afternoon"
        return "Good evening"
    }

    // Fast core info — no network calls, so this returns near-instantly and the
    // popup populates immediately. The (slow) update count is a separate process.
    Process {
        id: infoLoader
        property string _buf: ""
        command: ["bash", "-c",
            ". /etc/os-release 2>/dev/null\n" +
            "echo \"osname=${PRETTY_NAME:-${NAME:-Linux}}\"\n" +
            "echo \"osversion=${VERSION:-${VERSION_ID:-rolling}}\"\n" +
            "echo \"osicon=${ICON_NAME:-${LOGO:-${ID:-linux}}}\"\n" +
            "echo \"hostname=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)\"\n" +
            "echo \"username=${USER:-$(whoami)}\"\n" +
            "echo \"kernel=$(uname -r)\"\n" +
            
            "# OS age\n" +
            "birth=$(stat -c %W / 2>/dev/null)\n" +
            "if [ -n \"$birth\" ] && [ \"$birth\" != \"0\" ] && [ \"$birth\" != \"-\" ]; then\n" +
            "  now=$(date +%s); diff=$((now - birth)); days=$((diff / 86400))\n" +
            "  if   [ $days -ge 365 ]; then years=$((days/365)); months=$(((days%365)/30)); echo \"osage=${years}y ${months}mo\"\n" +
            "  elif [ $days -ge 30 ];  then months=$((days/30));  rdays=$((days%30));      echo \"osage=${months}mo ${rdays}d\"\n" +
            "  else echo \"osage=${days}d\"; fi\n" +
            "fi\n" +
            
            "# Uptime\n" +
            "ut=$(awk '{print int($1)}' /proc/uptime)\n" +
            "d=$((ut/86400)); h=$(( (ut%86400)/3600 )); m=$(( (ut%3600)/60 ))\n" +
            "if [ $d -gt 0 ]; then echo \"uptime=${d}d ${h}h ${m}m\"\n" +
            "elif [ $h -gt 0 ]; then echo \"uptime=${h}h ${m}m\"\n" +
            "else echo \"uptime=${m}m\"; fi\n" +
            
            "# XDG Dirs\n" +
            "echo \"home=$HOME\"\n" +
            "if command -v xdg-user-dir &>/dev/null; then\n" +
            "  echo \"docs=$(xdg-user-dir DOCUMENTS)\"; echo \"pics=$(xdg-user-dir PICTURES)\"\n" +
            "  echo \"vids=$(xdg-user-dir VIDEOS)\"; echo \"music=$(xdg-user-dir MUSIC)\"\n" +
            "else\n" +
            "  echo \"docs=$HOME/Documents\"; echo \"pics=$HOME/Pictures\"\n" +
            "  echo \"vids=$HOME/Videos\"; echo \"music=$HOME/Music\"\n" +
            "fi\n" +

            "# Disk Usage — root + real disks mounted under /mnt, /media, /run/media (USB keys, etc.)\n" +
            "df -h --output=target,pcent,used,size,source 2>/dev/null | tail -n +2 | while read -r tgt pct used size src; do\n" +
            "  case \"$src\" in /dev/*) ;; *) continue;; esac\n" +
            "  case \"$tgt\" in\n" +
            "    /)                        lbl='Root (/)';;\n" +
            "    /mnt/*|/media/*|/run/media/*) lbl=\"$(basename \"$tgt\")\";;\n" +
            "    *) continue;;\n" +
            "  esac\n" +
            "  echo \"disk=${lbl}|${pct%\\%}|${used}|${size}|${tgt}\"\n" +
            "done\n"
        ]
        stdout: SplitParser { onRead: { infoLoader._buf += data + "\n" } }
        onRunningChanged: {
            if (running) return
            let lines = infoLoader._buf.trim().split("\n"); infoLoader._buf = ""
            let disksArr = []
            for (let l of lines) {
                let i = l.indexOf("="); if (i < 1) continue
                let k = l.substring(0, i); let v = l.substring(i + 1).trim()
                switch (k) {
                    case "osname": popup.osName = v; break;     case "osversion": popup.osVersion = v; break
                    case "osicon": popup.osIconHint = v; break; case "hostname": popup.hostname = v; break
                    case "username": popup.username = v; break; case "kernel": popup.kernelStr = v; break
                    case "osage": popup.osAge = v; break;       case "uptime": popup.uptimeStr = v; break
                    case "home": popup.homeDir = v; break;      case "docs": popup.docsDir = v; break
                    case "pics": popup.picsDir = v; break;      case "vids": popup.vidsDir = v; break
                    case "music": popup.musicDir = v; break
                    case "disk": {
                        let p = v.split("|")
                        disksArr.push({ label: p[0] || "?", pct: parseInt(p[1]) || 0,
                                        used: p[2] || "0", total: p[3] || "0", mount: p[4] || "" })
                        break
                    }
                }
            }
            popup.disks = disksArr
            if (popup.osIconHint !== "") logoResolver.start(popup.osIconHint)
        }
    }

    // Update count — can touch the network (checkupdates syncs a temp DB), so it
    // runs on its own and is wrapped in `timeout` to guarantee it can never hang
    // the popup. The badge fills in whenever this finishes.
    Process {
        id: updatesLoader
        property string _buf: ""
        command: ["bash", "-c",
            "if command -v checkupdates >/dev/null 2>&1; then timeout 20 checkupdates 2>/dev/null | wc -l\n" +
            "elif command -v apt >/dev/null 2>&1; then apt list --upgradable 2>/dev/null | grep -vc '^Listing'\n" +
            "elif command -v dnf >/dev/null 2>&1; then timeout 20 dnf check-update -q 2>/dev/null | grep -c .\n" +
            "else echo 0; fi"
        ]
        stdout: SplitParser { onRead: data => updatesLoader._buf += data }
        onRunningChanged: {
            if (running) return
            popup.updates = "" + (parseInt(updatesLoader._buf.trim()) || 0)
            updatesLoader._buf = ""
        }
    }

    Process {
        id: logoResolver; property string _buf: ""
        function start(hint) {
            _buf = ""; running = true
            command = ["bash", "-c", "h='" + hint.replace(/'/g, "'\\''") + "'; candidates=(\"/usr/share/icons/${h}.svg\" \"/usr/share/icons/${h}.png\" \"/usr/share/icons/${h}-logo.svg\" \"/usr/share/pixmaps/${h}.png\" \"/usr/share/pixmaps/${h}.svg\" \"/usr/share/icons/hicolor/scalable/apps/${h}.svg\"); for c in \"${candidates[@]}\"; do [ -f \"$c\" ] && echo \"$c\" && exit 0; done; find /usr/share/icons /usr/share/pixmaps -maxdepth 2 -iname \"*${h}*\" -type f 2>/dev/null \\( -name '*.svg' -o -name '*.png' \\) | head -1"]
        }
        stdout: SplitParser { onRead: { logoResolver._buf += data + "\n" } }
        onRunningChanged: { if (!running) popup.osLogoPath = logoResolver._buf.trim().split("\n")[0] || "" }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  WRAPPER FOR SMOOTH ANIMATIONS
    // ═══════════════════════════════════════════════════════════════════════
    Item {
        id: mainContent
        width: 520
        height: mainColumn.implicitHeight + 48 // Dynamic height
        anchors.left: parent.left
        anchors.leftMargin: 15

        // 3. Smooth Entrance / Exit Animations
        anchors.top: parent.top
        anchors.topMargin: popup.active ? 45 : 25
        transformOrigin: Item.TopLeft // Scales from the correct corner
        opacity: popup.active ? 1.0 : 0.0
        scale: popup.active ? 1.0 : 0.90
        
        Behavior on opacity { 
            NumberAnimation { 
                duration: 250; easing.type: Easing.OutCubic 
                onRunningChanged: if (!running && !popup.active) popup.isAnimating = false 
            } 
        }
        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }


        Shadow {}

        Rectangle {
            anchors.fill: parent
            color: Theme.background; opacity: 0.8
            border.color: Theme.withAlpha(Theme.primary, 0.8); border.width: 2
            radius: 30
        }

        MouseArea { anchors.fill: parent; onClicked: {} } // Eat clicks

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent; anchors.margins: 24; spacing: 18

            // ── HERO: OS logo + name + version ────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 18

                Rectangle {
                    width: 92; height: 92; radius: 22
                    color: Theme.withAlpha(Theme.primary, 0.08)
                    border.color: Theme.withAlpha(Theme.primary, 0.15)
                    border.width: 1

                    Image {
                        id: logoImg
                        anchors.centerIn: parent
                        width: 64; height: 64
                        source: popup.osLogoPath !== "" ? "file://" + popup.osLogoPath : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true; asynchronous: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent; text: "󰌽"; color: Theme.primary
                        font.pixelSize: 56; opacity: 0.8; visible: !logoImg.visible
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    Text {
                        text: popup.greeting() + (popup.username !== "" ? ", " + popup.username : "")
                        color: Theme.primary; opacity: 0.5; font.pixelSize: 11; font.bold: true
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    Text {
                        text: popup.osName || "Loading…"
                        color: Theme.primary; font.pixelSize: 22; font.weight: Font.Black
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    Text {
                        text: popup.osVersion
                        color: Theme.primary; opacity: 0.55; font.pixelSize: 13
                        elide: Text.ElideRight; Layout.fillWidth: true; visible: popup.osVersion !== ""
                    }
                    Rectangle {
                        height: 22; radius: 11; Layout.preferredWidth: kernelLbl.implicitWidth + 18
                        color: Theme.withAlpha(Theme.primary, 0.10)
                        border.color: Theme.withAlpha(Theme.primary, 0.18); border.width: 1
                        visible: popup.kernelStr !== ""
                        Text {
                            id: kernelLbl; anchors.centerIn: parent; text: "󰌽  " + popup.kernelStr
                            color: Theme.primary; opacity: 0.75; font.pixelSize: 10; font.bold: true
                        }
                    }
                }

                // Settings — fills the previously-empty top-right corner.
                IconButton {
                    icon: "󰒓"
                    size: 40
                    iconSize: 18
                    Layout.alignment: Qt.AlignTop
                    onClicked: { Sys.run(["qs", "ipc", "call", "settings", "open"]); popup.active = false }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // ── INFO GRID ──────────────────────────────────────────────────
            component InfoTile: GlassCard {
                id: infoRoot
                property string tileIcon: ""
                property string tileLabel: ""
                property string tileValue: ""
                Layout.fillWidth: true; Layout.preferredHeight: 60; radius: 14

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 10; color: Theme.withAlpha(Theme.primary, 0.10)
                        Text { anchors.centerIn: parent; text: infoRoot.tileIcon; color: Theme.primary; font.pixelSize: 16 }
                    }
                    ColumnLayout {
                        spacing: -1; Layout.fillWidth: true
                        Text { text: infoRoot.tileLabel; color: Theme.primary; opacity: 0.5; font.pixelSize: 9; font.bold: true }
                        Text { text: infoRoot.tileValue !== "" ? infoRoot.tileValue : "—"; color: Theme.primary; font.pixelSize: 13; font.weight: Font.Black; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true; columns: 2; rowSpacing: 8; columnSpacing: 8
                InfoTile { tileIcon: "󰍹"; tileLabel: "HOSTNAME"; tileValue: popup.hostname }
                InfoTile { tileIcon: "󰀄"; tileLabel: "USER";     tileValue: popup.username }
                InfoTile { tileIcon: "󰃭"; tileLabel: "OS AGE";   tileValue: popup.osAge }
                InfoTile { tileIcon: "󱎫"; tileLabel: "UPTIME";   tileValue: popup.uptimeStr }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // ── NEW: STORAGE & UPDATES ────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 20
                
                // Disks Layout
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 10

                    Text { text: "STORAGE"; color: Theme.primary; opacity: 0.45; font.pixelSize: 10; font.bold: true }

                    // One row per mounted disk (root + /mnt, /media, /run/media)
                    Repeater {
                        model: popup.disks
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text {
                                text: modelData.label; color: Theme.primary; font.pixelSize: 12; font.bold: true
                                Layout.preferredWidth: 60; elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Theme.withAlpha(Theme.primary, 0.1)
                                Rectangle { width: parent.width * (modelData.pct/100); height: parent.height; radius: 4; color: modelData.pct > 90 ? "#ff5555" : Theme.primary }
                            }
                            Text { text: modelData.used + " / " + modelData.total; color: Theme.primary; opacity: 0.6; font.pixelSize: 11; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    // Fallback when no disks were detected
                    Text {
                        visible: popup.disks.length === 0
                        text: "No disks mounted"; color: Theme.primary; opacity: 0.5; font.pixelSize: 12
                    }
                }

                // Updates Badge
                GlassCard {
                    Layout.preferredWidth: 100; Layout.preferredHeight: 72
                    Layout.alignment: Qt.AlignVCenter; radius: 14
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text { text: "󰏔"; color: popup.updates !== "0" ? Theme.primary : Theme.primary; opacity: popup.updates !== "0" ? 1.0 : 0.4; font.pixelSize: 26; Layout.alignment: Qt.AlignHCenter }
                        Text { text: popup.updates + " Updates"; color: Theme.primary; opacity: 0.8; font.pixelSize: 11; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // ── QUICK FOLDERS ─────────────────────────────────────────────
            Text { text: "QUICK ACCESS"; color: Theme.primary; opacity: 0.45; font.pixelSize: 10; font.bold: true; Layout.leftMargin: 4 }

            component FolderButton: Rectangle {
                id: fbRoot
                property string folderIcon: ""
                property string folderLabel: ""
                property string folderPath:  ""

                Layout.fillWidth: true; Layout.preferredHeight: 78; radius: 16
                color: hovered ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.primary, 0.05)
                border.color: hovered ? Theme.primary : Theme.withAlpha(Theme.primary, 0.15)
                border.width: hovered ? 1.5 : 1
                scale: hovered ? 1.04 : 1.0
                Behavior on color       { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Behavior on scale       { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                property bool hovered: false

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter; width: 38; height: 38; radius: 11
                        color: Theme.withAlpha(Theme.primary, fbRoot.hovered ? 0.20 : 0.12)
                        Text { anchors.centerIn: parent; text: fbRoot.folderIcon; color: Theme.primary; font.pixelSize: 20 }
                    }
                    Text { Layout.alignment: Qt.AlignHCenter; text: fbRoot.folderLabel; color: Theme.primary; font.pixelSize: 11; font.weight: Font.Bold }
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onEntered: fbRoot.hovered = true; onExited: fbRoot.hovered = false
                    onClicked: {
                        if (fbRoot.folderPath !== "") {
                            Sys.run(["bash", "-c", "if command -v nemo &>/dev/null; then nemo \"" + fbRoot.folderPath + "\"; else xdg-open \"" + fbRoot.folderPath + "\"; fi"])
                            popup.active = false
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true; columns: 5; rowSpacing: 8; columnSpacing: 8
                FolderButton { folderIcon: "󰋜"; folderLabel: "Home"; folderPath: popup.homeDir }
                FolderButton { folderIcon: "󰈙"; folderLabel: "Documents"; folderPath: popup.docsDir }
                FolderButton { folderIcon: "󰋩"; folderLabel: "Pictures"; folderPath: popup.picsDir }
                FolderButton { folderIcon: "󰕧"; folderLabel: "Videos"; folderPath: popup.vidsDir }
                FolderButton { folderIcon: "󰝚"; folderLabel: "Music"; folderPath: popup.musicDir }
            }

            // ── NEW: SESSION CONTROLS ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 5; spacing: 8
                
                component SessionButton: Rectangle {
                    property string btnIcon: ""
                    property string cmd: ""
                    property color hoverColor: Theme.primary
                    Layout.fillWidth: true; Layout.preferredHeight: 50; radius: 14
                    
                    color: pMouse.containsMouse ? hoverColor : Theme.withAlpha(Theme.primary, 0.05)
                    border.color: pMouse.containsMouse ? hoverColor : Theme.withAlpha(Theme.primary, 0.12)
                    border.width: 1
                    scale: pMouse.pressed ? 0.94 : (pMouse.containsMouse ? 1.05 : 1.0)

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    
                    Text { 
                        anchors.centerIn: parent; text: parent.btnIcon 
                        color: pMouse.containsMouse ? Theme.background : Theme.primary
                        font.pixelSize: 22 
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                        id: pMouse; anchors.fill: parent; hoverEnabled: true
                        // FIX: Wrapped command in bash invocation
                        onClicked: { Sys.run(["bash", "-c", cmd]); popup.active = false }
                    }
                }

                SessionButton { btnIcon: "󰌾"; cmd: "hyprlock" }
                SessionButton { btnIcon: "󰍃"; cmd: "hyprctl dispatch 'hl.dsp.exit()'" }
                SessionButton { btnIcon: "󰤄"; cmd: "systemctl suspend" }
                SessionButton { btnIcon: "󰜉"; cmd: "systemctl reboot" }
                SessionButton { btnIcon: "󰐥"; cmd: "systemctl poweroff"; hoverColor: "#ff5555" } // Red hover for shutdown
            }
        }
    }
}