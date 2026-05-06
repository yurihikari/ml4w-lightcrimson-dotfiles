import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

// DashboardPopup — opened by clicking the OS logo on the bar.
// Wire-up in ScreenFrame:
//   DashboardPopup { id: dashPopup; screen: root.screen }
//   onClicked: dashPopup.active = !dashPopup.active   (on the logo)
PanelWindow {
    id: popup

    property bool active: false
    property var screen
    screen: popup.screen
    visible: active

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    // Backdrop — click to close
    MouseArea { anchors.fill: parent; onClicked: popup.active = false }

    // ─── State (filled by Processes below) ────────────────────────────────
    property string osName:     ""
    property string osVersion:  ""
    property string osIconHint: ""    // ICON_NAME from os-release, or ID
    property string osLogoPath: ""    // resolved absolute path
    property string hostname:   ""
    property string username:   ""
    property string osAge:      ""
    property string kernelStr:  ""
    property string uptimeStr:  ""

    // Folder paths from xdg-user-dir
    property string homeDir: ""
    property string docsDir: ""
    property string picsDir: ""
    property string vidsDir: ""
    property string musicDir: ""

    Process { id: executor; function run(args) { command = args; running = true } }

    // One bash invocation gathers everything except the logo path
    Process {
        id: infoLoader
        running: true
        property string _buf: ""
        command: ["bash", "-c",
            ". /etc/os-release 2>/dev/null\n" +
            "echo \"osname=${PRETTY_NAME:-${NAME:-Linux}}\"\n" +
            "echo \"osversion=${VERSION:-${VERSION_ID:-rolling}}\"\n" +
            "echo \"osicon=${ICON_NAME:-${LOGO:-${ID:-linux}}}\"\n" +
            "echo \"osid=${ID:-linux}\"\n" +
            "echo \"hostname=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)\"\n" +
            "echo \"username=${USER:-$(whoami)}\"\n" +
            "echo \"kernel=$(uname -r)\"\n" +
            "# OS age from filesystem birth time of /\n" +
            "birth=$(stat -c %W / 2>/dev/null)\n" +
            "if [ -n \"$birth\" ] && [ \"$birth\" != \"0\" ] && [ \"$birth\" != \"-\" ]; then\n" +
            "  now=$(date +%s)\n" +
            "  diff=$((now - birth))\n" +
            "  days=$((diff / 86400))\n" +
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
            "# XDG user dirs — falls back to $HOME/<Default> if xdg-user-dir absent\n" +
            "echo \"home=$HOME\"\n" +
            "if command -v xdg-user-dir &>/dev/null; then\n" +
            "  echo \"docs=$(xdg-user-dir DOCUMENTS)\"\n" +
            "  echo \"pics=$(xdg-user-dir PICTURES)\"\n" +
            "  echo \"vids=$(xdg-user-dir VIDEOS)\"\n" +
            "  echo \"music=$(xdg-user-dir MUSIC)\"\n" +
            "else\n" +
            "  echo \"docs=$HOME/Documents\"\n" +
            "  echo \"pics=$HOME/Pictures\"\n" +
            "  echo \"vids=$HOME/Videos\"\n" +
            "  echo \"music=$HOME/Music\"\n" +
            "fi\n"
        ]
        stdout: SplitParser {
            onRead: { infoLoader._buf += data + "\n" }
        }
        onRunningChanged: {
            if (running) return
            let lines = infoLoader._buf.trim().split("\n")
            infoLoader._buf = ""
            for (let l of lines) {
                let i = l.indexOf("=")
                if (i < 1) continue
                let k = l.substring(0, i)
                let v = l.substring(i + 1).trim()
                switch (k) {
                    case "osname":     popup.osName     = v; break
                    case "osversion":  popup.osVersion  = v; break
                    case "osicon":     popup.osIconHint = v; break
                    case "hostname":   popup.hostname   = v; break
                    case "username":   popup.username   = v; break
                    case "kernel":     popup.kernelStr  = v; break
                    case "osage":      popup.osAge      = v; break
                    case "uptime":     popup.uptimeStr  = v; break
                    case "home":       popup.homeDir    = v; break
                    case "docs":       popup.docsDir    = v; break
                    case "pics":       popup.picsDir    = v; break
                    case "vids":       popup.vidsDir    = v; break
                    case "music":      popup.musicDir   = v; break
                }
            }
            // Once we know the icon hint, kick off the resolver
            if (popup.osIconHint !== "") logoResolver.start(popup.osIconHint)
        }
    }

    // ─── Logo resolver — same bulk-find approach as DockPopup ──────────────
    // Tries a list of well-known distro-logo paths against the icon hint.
    // We don't run a full filesystem find here because logos are stored in
    // a small set of conventional locations.
    Process {
        id: logoResolver
        property string _buf: ""
        function start(hint) {
            _buf = ""
            command = ["bash", "-c",
                "h='" + hint.replace(/'/g, "'\\''") + "'\n" +
                "# Candidate paths in priority order. Note /usr/share/icons/<name>.svg\n" +
                "# at the *root* of the icons directory — that's where some distros\n" +
                "# (CachyOS, GNOME's gnome-logo-text) drop their branded logo.\n" +
                "candidates=(\n" +
                "  \"/usr/share/icons/${h}.svg\"\n" +
                "  \"/usr/share/icons/${h}.png\"\n" +
                "  \"/usr/share/icons/${h}-logo.svg\"\n" +
                "  \"/usr/share/pixmaps/${h}.png\"\n" +
                "  \"/usr/share/pixmaps/${h}.svg\"\n" +
                "  \"/usr/share/pixmaps/${h}-logo.png\"\n" +
                "  \"/usr/share/pixmaps/${h}-logo.svg\"\n" +
                "  \"/usr/share/pixmaps/distributor-logo-${h}.svg\"\n" +
                "  \"/usr/share/pixmaps/distributor-logo-${h}.png\"\n" +
                "  \"/usr/share/icons/hicolor/scalable/apps/${h}.svg\"\n" +
                "  \"/usr/share/icons/hicolor/scalable/apps/${h}-logo.svg\"\n" +
                "  \"/usr/share/icons/hicolor/scalable/apps/distributor-logo-${h}.svg\"\n" +
                "  \"/usr/share/icons/hicolor/scalable/apps/start-here-${h}.svg\"\n" +
                "  \"/usr/share/icons/hicolor/256x256/apps/${h}.png\"\n" +
                "  \"/usr/share/icons/hicolor/128x128/apps/${h}.png\"\n" +
                "  \"/usr/share/icons/hicolor/scalable/apps/start-here.svg\"\n" +
                ")\n" +
                "for c in \"${candidates[@]}\"; do\n" +
                "  [ -f \"$c\" ] && echo \"$c\" && exit 0\n" +
                "done\n" +
                "# Fallback: search common icon directories at depth 1-2\n" +
                "find /usr/share/icons /usr/share/pixmaps \\\n" +
                "  -maxdepth 2 -iname \"*${h}*\" -type f 2>/dev/null \\\n" +
                "  \\( -name '*.svg' -o -name '*.png' \\) | head -1\n"
            ]
            running = true
        }
        stdout: SplitParser { onRead: { logoResolver._buf += data + "\n" } }
        onRunningChanged: {
            if (running) return
            let p = logoResolver._buf.trim().split("\n")[0] || ""
            popup.osLogoPath = p
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONTAINER
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: container
        width: 520; height: 620
        anchors.top: parent.top; anchors.topMargin: 45
        anchors.left: parent.left; anchors.leftMargin: 15
        radius: 30; color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.background; opacity: 0.8
            border.color: Theme.primary; border.width: 2
            radius: 30
        }
        // Eat clicks so they don't fall through to the backdrop
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 24; spacing: 18

            // ── HERO: OS logo + name + version ────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 18

                // Logo with circular highlight backdrop
                Rectangle {
                    width: 92; height: 92; radius: 22
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    border.width: 1

                    Image {
                        id: logoImg
                        anchors.centerIn: parent
                        width: 64; height: 64
                        source: popup.osLogoPath !== "" ? "file://" + popup.osLogoPath : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    // Fallback glyph when no logo found
                    Text {
                        anchors.centerIn: parent
                        text: "󰌽"   // generic linux glyph (nerdfont)
                        color: Theme.primary
                        font.pixelSize: 56
                        opacity: 0.8
                        visible: !logoImg.visible
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    Text {
                        text: popup.osName || "Loading…"
                        color: Theme.primary
                        font.pixelSize: 22
                        font.weight: Font.Black
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: popup.osVersion
                        color: Theme.primary; opacity: 0.55
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: popup.osVersion !== ""
                    }
                    // Inline pill: kernel version
                    Rectangle {
                        height: 22; radius: 11
                        Layout.preferredWidth: kernelLbl.implicitWidth + 18
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                        border.width: 1
                        visible: popup.kernelStr !== ""
                        Text {
                            id: kernelLbl
                            anchors.centerIn: parent
                            text: "󰌽  " + popup.kernelStr
                            color: Theme.primary; opacity: 0.75
                            font.pixelSize: 10; font.bold: true
                        }
                    }
                }
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // ── INFO GRID: hostname / user / age / uptime ─────────────────
            // Reusable info-tile inline component
            component InfoTile: Rectangle {
                id: infoRoot
                property string tileIcon: ""
                property string tileLabel: ""
                property string tileValue: ""
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 14
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                        Text { anchors.centerIn: parent; text: infoRoot.tileIcon; color: Theme.primary; font.pixelSize: 16 }
                    }
                    ColumnLayout {
                        spacing: -1; Layout.fillWidth: true
                        Text { text: infoRoot.tileLabel; color: Theme.primary; opacity: 0.5; font.pixelSize: 9; font.bold: true }
                        Text {
                            text: infoRoot.tileValue !== "" ? infoRoot.tileValue : "—"
                            color: Theme.primary; font.pixelSize: 13; font.weight: Font.Black
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2; rowSpacing: 8; columnSpacing: 8

                InfoTile { tileIcon: "󰍹"; tileLabel: "HOSTNAME"; tileValue: popup.hostname }
                InfoTile { tileIcon: "󰀄"; tileLabel: "USER";     tileValue: popup.username }
                InfoTile { tileIcon: "󰃭"; tileLabel: "OS AGE";   tileValue: popup.osAge }
                InfoTile { tileIcon: "󱎫"; tileLabel: "UPTIME";   tileValue: popup.uptimeStr }
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // ── QUICK FOLDERS ─────────────────────────────────────────────
            Text {
                text: "QUICK ACCESS"
                color: Theme.primary; opacity: 0.45
                font.pixelSize: 10; font.bold: true
                Layout.leftMargin: 4
            }

            // Reusable folder-button inline component
            component FolderButton: Rectangle {
                id: fbRoot
                property string folderIcon: ""
                property string folderLabel: ""
                property string folderPath:  ""
                property color  accentColor: Theme.primary

                Layout.fillWidth: true
                Layout.preferredHeight: 78
                radius: 16
                color: hovered
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                border.color: hovered
                    ? Theme.primary
                    : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                border.width: hovered ? 1.5 : 1
                Behavior on color       { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                property bool hovered: false

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4

                    // Icon block
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 38; height: 38; radius: 11
                        color: Qt.rgba(fbRoot.accentColor.r, fbRoot.accentColor.g, fbRoot.accentColor.b, fbRoot.hovered ? 0.20 : 0.12)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: fbRoot.folderIcon
                            color: fbRoot.accentColor
                            font.pixelSize: 20
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: fbRoot.folderLabel
                        color: Theme.primary
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: fbRoot.hovered = true
                    onExited:  fbRoot.hovered = false
                    onClicked: {
                        if (fbRoot.folderPath !== "") {
                            // Prefer nemo if available, else xdg-open
                            executor.run(["bash", "-c",
                                "if command -v nemo &>/dev/null; then nemo \"" + fbRoot.folderPath + "\"; " +
                                "else xdg-open \"" + fbRoot.folderPath + "\"; fi"])
                            popup.active = false
                        }
                    }
                }
            }

            // 5 buttons — Home spans 2 columns visually by being placed first
            // in a 5-column grid that fills the row
            GridLayout {
                Layout.fillWidth: true
                columns: 5; rowSpacing: 8; columnSpacing: 8

                FolderButton {
                    folderIcon: "󰋜"
                    folderLabel: "Home"
                    folderPath: popup.homeDir
                }
                FolderButton {
                    folderIcon: "󰈙"
                    folderLabel: "Documents"
                    folderPath: popup.docsDir
                }
                FolderButton {
                    folderIcon: "󰋩"
                    folderLabel: "Pictures"
                    folderPath: popup.picsDir
                }
                FolderButton {
                    folderIcon: "󰕧"
                    folderLabel: "Videos"
                    folderPath: popup.vidsDir
                }
                FolderButton {
                    folderIcon: "󰝚"
                    folderLabel: "Music"
                    folderPath: popup.musicDir
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
