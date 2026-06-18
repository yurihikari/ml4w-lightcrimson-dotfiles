import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Network"
    subheading: "Wired connection, OpenVPN configurations and VPN apps"
    icon: "󰦝"

    property bool active: false

    property string ethName: ""
    property bool ethUp: false

    // ── OpenVPN — multiple saved configs, connected via the openvpn CLI ──
    // configs: [{ id, name, path, user, password }]
    property var configs: []
    property string editingId: ""        // "" = closed, "new" = adding, else an id

    // Connection state: "off" | "connecting" | "up" | "error"
    property string ovpnState: "off"
    property string ovpnStatus: "Not connected"
    property string connectedId: ""
    property bool userStopped: false
    property string pendingPath: ""
    property bool pendingAuth: false
    readonly property bool connected: ovpnState === "up"
    readonly property bool connecting: ovpnState === "connecting"

    readonly property string authPath: Quickshell.env("HOME") + "/.cache/quickshell-ovpn-auth"
    readonly property string pidPath: "/tmp/quickshell-ovpn.pid"
    readonly property string configsPath: Quickshell.env("HOME") + "/.cache/quickshell-vpn-configs.json"

    property var vpnApps: []
    property bool hasZenity: false

    onActiveChanged: if (active) {
        ethReader.running = true
        configsReader.running = true
        appDetector._buf = ""; appDetector.running = true
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function setStatus(s) { page.ovpnStatus = s }
    function nameOf(id) { let c = page.configs.find(x => x.id === id); return c ? c.name : "" }

    // ── Persistence ──────────────────────────────────────────────────────
    function saveConfigs() {
        let b64 = Qt.btoa(unescape(encodeURIComponent(JSON.stringify(page.configs))))
        configsWriter.command = ["bash", "-c", "mkdir -p $(dirname " + shq(page.configsPath) + ") && echo " + shq(b64) + " | base64 -d > " + shq(page.configsPath)]
        configsWriter.running = true
    }

    // ── Editor ───────────────────────────────────────────────────────────
    function openEditor(cfg) {
        if (cfg) {
            page.editingId = cfg.id
            editName.text = cfg.name; editPath.text = cfg.path
            editUser.text = cfg.user || ""; editPass.text = cfg.password || ""
        } else {
            page.editingId = "new"
            editName.text = ""; editPath.text = ""; editUser.text = ""; editPass.text = ""
        }
    }

    function saveEntry() {
        let path = editPath.text.trim()
        if (path === "") return
        let name = editName.text.trim()
        if (name === "") name = path.split("/").pop().replace(/\.(ovpn|conf)$/i, "")
        let entry = { id: page.editingId === "new" ? ("" + Date.now()) : page.editingId,
                      name: name, path: path, user: editUser.text.trim(), password: editPass.text }
        let arr = page.configs.slice()
        let idx = arr.findIndex(c => c.id === entry.id)
        if (idx >= 0) arr[idx] = entry; else arr.push(entry)
        page.configs = arr
        saveConfigs()
        page.editingId = ""
    }

    function deleteEntry(id) {
        if (page.connectedId === id && (page.connected || page.connecting)) disconnectVpn()
        page.configs = page.configs.filter(c => c.id !== id)
        saveConfigs()
        if (page.editingId === id) page.editingId = ""
    }

    // ── Connect / disconnect (openvpn CLI via pkexec) ────────────────────
    function startProc() {
        let cfg = page.pendingPath
        if (cfg === "") { page.ovpnState = "error"; setStatus("No config file"); return }
        let dir = cfg.lastIndexOf("/") > 0 ? cfg.substring(0, cfg.lastIndexOf("/")) : "."
        let inner = "cd " + shq(dir) + " && exec openvpn --config " + shq(cfg) +
                    " --writepid " + shq(page.pidPath) + " --verb 3" +
                    (page.pendingAuth ? " --auth-user-pass " + shq(page.authPath) + " --auth-nocache" : "")
        ovpnProc.command = ["pkexec", "bash", "-c", inner]
        ovpnProc.running = true
    }

    function connectConfig(cfg) {
        if (page.connected || page.connecting) return
        page.userStopped = false
        page.connectedId = cfg.id
        page.ovpnState = "connecting"
        setStatus("Connecting to " + cfg.name + "…")
        page.pendingPath = cfg.path
        if (cfg.user && cfg.user.trim() !== "") {
            page.pendingAuth = true
            authWriter.command = ["bash", "-c",
                "umask 077; printf '%s\\n%s\\n' " + shq(cfg.user) + " " + shq(cfg.password || "") + " > " + shq(page.authPath)]
            authWriter.running = true   // onRunningChanged → startProc()
        } else {
            page.pendingAuth = false
            startProc()
        }
    }

    function disconnectVpn() {
        page.userStopped = true
        setStatus("Disconnecting…")
        ovpnStop.command = ["pkexec", "bash", "-c",
            "kill $(cat " + shq(page.pidPath) + " 2>/dev/null) 2>/dev/null; rm -f " + shq(page.pidPath) + " " + shq(page.authPath)]
        ovpnStop.running = true
    }

    function parseLine(line) {
        let l = line.trim()
        if (l === "") return
        if (l.indexOf("Initialization Sequence Completed") !== -1) { page.ovpnState = "up"; setStatus("Connected to " + page.nameOf(page.connectedId)); return }
        if (l.indexOf("AUTH_FAILED") !== -1) { setStatus("Authentication failed — check username/password"); return }
        if (l.indexOf("Options error") !== -1 || l.indexOf("Cannot") !== -1 || l.indexOf("ERROR") !== -1 || l.indexOf("No such file") !== -1) { setStatus(l.replace(/^.*?:\s*/, "")); return }
        if (l.indexOf("TLS Error") !== -1 || l.indexOf("TLS handshake failed") !== -1) { setStatus("TLS handshake failed"); return }
    }

    // ── Processes ────────────────────────────────────────────────────────
    Process {
        id: ethReader
        property string _buf: ""
        command: ["bash", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null | grep '^ethernet'"]
        stdout: SplitParser { onRead: ethReader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let up = false, name = ""
            for (let l of ethReader._buf.trim().split("\n")) {
                let p = l.split(":")
                if (p.length >= 3 && p[1].indexOf("connected") !== -1 && p[1].indexOf("disconnected") === -1) { up = true; name = p[2] }
            }
            page.ethUp = up; page.ethName = name
            ethReader._buf = ""
        }
    }

    Process {
        id: configsReader
        command: ["bash", "-c", "cat " + page.shq(page.configsPath) + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim()
                if (t === "") { page.configs = []; return }
                try { page.configs = JSON.parse(t) } catch (e) { page.configs = [] }
            }
        }
    }

    Process { id: configsWriter }

    Process { id: authWriter; onRunningChanged: if (!running) page.startProc() }

    Process {
        id: ovpnProc
        stdout: SplitParser { onRead: page.parseLine(data) }
        stderr: SplitParser { onRead: page.parseLine(data) }
        onRunningChanged: {
            if (running) { if (page.ovpnState !== "up") page.ovpnState = "connecting"; return }
            if (page.userStopped) { page.ovpnState = "off"; page.setStatus("Not connected") }
            else if (page.ovpnState === "up") { page.ovpnState = "off"; page.setStatus("Connection closed") }
            else { page.ovpnState = "error"; if (page.ovpnStatus.indexOf("Connecting") === 0) page.setStatus("Failed to connect") }
            page.connectedId = ""
            page.userStopped = false
        }
    }

    Process { id: ovpnStop; onRunningChanged: if (!running && ovpnProc.running) ovpnProc.running = false }

    Process {
        id: configPicker
        command: ["bash", "-c", "zenity --file-selection --title='Select OpenVPN config' --file-filter='OpenVPN | *.ovpn *.conf *.tblk' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { let f = this.text.trim(); if (f !== "") editPath.text = f } }
    }

    Process {
        id: appDetector
        property string _buf: ""
        command: ["bash", "-c",
            "command -v zenity >/dev/null 2>&1 && echo 'ZENITY' || true\n" +
            "emit() { printf 'APP\\x1f%s\\x1f%s\\x1f%s\\n' \"$1\" \"$2\" \"$3\"; }\n" +
            "if command -v surfshark >/dev/null 2>&1 || [ -d /opt/Surfshark ] || [ -f /usr/share/applications/surfshark.desktop ]; then\n" +
            "  if command -v surfshark >/dev/null 2>&1; then emit 'Surfshark' 'surfshark' '󰦝'; else emit 'Surfshark' 'gtk-launch surfshark' '󰦝'; fi\nfi\n" +
            "if command -v protonvpn-app >/dev/null 2>&1; then emit 'Proton VPN' 'protonvpn-app' '󰦝'\n" +
            "elif command -v protonvpn >/dev/null 2>&1; then emit 'Proton VPN' 'protonvpn' '󰦝'\n" +
            "elif [ -f /usr/share/applications/com.vysp3r.ProtonPlus.desktop ]; then emit 'ProtonPlus' 'gtk-launch com.vysp3r.ProtonPlus' '󰦝'\nfi\n" +
            "if command -v mullvad-vpn >/dev/null 2>&1; then emit 'Mullvad' 'mullvad-vpn' '󰦝'\n" +
            "elif command -v mullvad >/dev/null 2>&1; then emit 'Mullvad' 'mullvad' '󰦝'\nfi\n" +
            "command -v nordvpn >/dev/null 2>&1 && emit 'NordVPN' 'nordvpn' '󰦝' || true\n" +
            "command -v expressvpn >/dev/null 2>&1 && emit 'ExpressVPN' 'expressvpn' '󰦝' || true\n" +
            "command -v windscribe >/dev/null 2>&1 && emit 'Windscribe' 'windscribe' '󰦝' || true\n" +
            "if command -v eovpn >/dev/null 2>&1; then emit 'OpenVPN (eOVPN)' 'eovpn' '󰦝'\n" +
            "elif [ -f /usr/share/applications/com.github.jkotra.eovpn.desktop ]; then emit 'OpenVPN (eOVPN)' 'gtk-launch com.github.jkotra.eovpn' '󰦝'\nfi"
        ]
        stdout: SplitParser { onRead: appDetector._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let apps = [], zen = false
            for (let l of appDetector._buf.trim().split("\n")) {
                if (l.trim() === "ZENITY") { zen = true; continue }
                let p = l.split("\x1f")
                if (p.length >= 4 && p[0] === "APP") apps.push({ name: p[1], cmd: p[2], icon: p[3] })
            }
            page.vpnApps = apps
            page.hasZenity = zen
            appDetector._buf = ""
        }
    }

    Timer { interval: 4000; repeat: true; running: page.active; onTriggered: ethReader.running = true }

    // Reusable themed text input. Exposes `text` directly.
    component Field: Rectangle {
        id: fieldRoot
        property alias text: inp.text
        property string placeholder: ""
        property bool password: false
        implicitHeight: 34
        Layout.fillWidth: true
        Layout.preferredWidth: 220
        radius: 9
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
        border.color: inp.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
        border.width: 1
        TextField {
            id: inp
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            placeholderText: fieldRoot.placeholder
            placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
            color: Theme.primary
            font.pixelSize: 13
            echoMode: fieldRoot.password ? TextInput.Password : TextInput.Normal
            verticalAlignment: TextInput.AlignVCenter
            background: null
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  UI
    // ════════════════════════════════════════════════════════════════════
    StCard {
        title: "Wired"
        StRow {
            icon: "󰈀"
            title: "Ethernet"
            subtitle: page.ethUp ? (page.ethName !== "" ? page.ethName : "Wired connection active") : "Cable not connected"
            Rectangle { width: 9; height: 9; radius: 4.5; color: page.ethUp ? "#a6e3a1" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3) }
            Text { text: page.ethUp ? "Connected" : "Off"; color: Theme.primary; opacity: 0.6; font.pixelSize: 11 }
        }
    }

    // ── Current VPN status ──
    StCard {
        title: "VPN status"
        StRow {
            icon: "󰦝"
            title: page.connected ? "Connected" : page.connecting ? "Connecting…" : "Not connected"
            subtitle: page.ovpnStatus
            Rectangle {
                width: 9; height: 9; radius: 4.5
                color: page.connected ? "#a6e3a1" : page.connecting ? "#e5c07b" : page.ovpnState === "error" ? "#e06c75" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
            }
            StButton {
                visible: page.connected || page.connecting
                text: page.connected ? "Disconnect" : "Cancel"
                dangerous: true
                implicitHeight: 32
                onClicked: page.disconnectVpn()
            }
        }
    }

    // ── Saved connections ──
    StCard {
        title: "OpenVPN connections"

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            color: "transparent"
            visible: page.configs.length === 0
            Text { anchors.centerIn: parent; text: "No configurations yet — add one below"; color: Theme.primary; opacity: 0.4; font.pixelSize: 12 }
        }

        Repeater {
            model: page.configs
            delegate: StRow {
                id: vpnRow
                required property var modelData
                readonly property bool isActive: page.connectedId === modelData.id
                readonly property bool busy: vpnRow.isActive && (page.connected || page.connecting)
                icon: "󰦝"
                title: modelData.name
                subtitle: (vpnRow.isActive && page.connected) ? "Connected" : (vpnRow.isActive && page.connecting) ? "Connecting…" : modelData.path

                Rectangle { visible: vpnRow.isActive && page.connected; width: 9; height: 9; radius: 4.5; color: "#a6e3a1" }

                StButton {
                    text: vpnRow.busy ? "Disconnect" : "Connect"
                    accent: !vpnRow.busy
                    dangerous: vpnRow.busy
                    enabled: vpnRow.busy || (!page.connected && !page.connecting)
                    implicitHeight: 30
                    onClicked: vpnRow.busy ? page.disconnectVpn() : page.connectConfig(vpnRow.modelData)
                }
                StIconButton {
                    icon: "󰏫"
                    onClicked: page.openEditor(vpnRow.modelData)
                }
                StIconButton {
                    icon: "󰆴"
                    onClicked: page.deleteEntry(vpnRow.modelData.id)
                }
            }
        }

        StButton {
            Layout.fillWidth: true
            implicitHeight: 40
            text: "Add configuration"
            icon: "󰐕"
            accent: true
            visible: page.editingId === ""
            onClicked: page.openEditor(null)
        }
    }

    // ── Add / edit editor ──
    StCard {
        title: page.editingId === "new" ? "New connection" : "Edit connection"
        visible: page.editingId !== ""

        StRow {
            icon: "󰦝"
            title: "Name"
            Field { id: editName; placeholder: "My VPN" }
        }
        StRow {
            icon: "󰈤"
            title: "Config file"
            subtitle: ".ovpn or .conf"
            Field { id: editPath; placeholder: "/path/to/config.ovpn" }
            StIconButton { icon: "󰉋"; visible: page.hasZenity; onClicked: configPicker.running = true }
        }
        StRow {
            icon: "󰀄"
            title: "Username"
            subtitle: "Leave empty for certificate-only configs"
            Field { id: editUser; placeholder: "username (optional)" }
        }
        StRow {
            icon: "󰌆"
            title: "Password"
            subtitle: "Stored locally (file is created only while connecting)"
            Field { id: editPass; placeholder: "password (optional)"; password: true }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            spacing: 8
            StButton { text: "Save"; icon: "󰆓"; accent: true; onClicked: page.saveEntry() }
            StButton { text: "Cancel"; onClicked: page.editingId = "" }
            StButton {
                text: "Open file"
                visible: editPath.text.trim() !== ""
                onClicked: Quickshell.execDetached(["bash", "-c", "xdg-open " + page.shq(editPath.text.trim())])
            }
            Item { Layout.fillWidth: true }
            StButton {
                text: "Delete"
                dangerous: true
                visible: page.editingId !== "new"
                onClicked: page.deleteEntry(page.editingId)
            }
        }
    }

    // ── Installed VPN apps ──
    StCard {
        title: "VPN apps"
        visible: page.vpnApps.length > 0
        Repeater {
            model: page.vpnApps
            delegate: StRow {
                required property var modelData
                icon: modelData.icon
                title: modelData.name
                subtitle: "Installed · launch the app"
                StButton {
                    text: "Launch"
                    accent: true
                    icon: "󰜎"
                    implicitHeight: 30
                    onClicked: Quickshell.execDetached(["bash", "-c", modelData.cmd])
                }
            }
        }
    }
}
