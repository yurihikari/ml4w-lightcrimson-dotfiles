import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.services
import qs.SettingsApp.components

// Network: VPN, sharing (hotspot / Ethernet), wired ports and an editor for
// every connection. Everything is a NetworkManager connection (see NM), so
// what is started here keeps running after Settings closes and is picked up
// again when it opens.
StPage {
    id: page
    heading: "Network"
    subheading: "VPN, hotspot and Ethernet sharing, wired ports and connection settings"
    icon: "󰦝"

    property bool active: false
    onActiveChanged: {
        if (active) {
            NM.watch()
            legacyReader.running = true
            appDetector._buf = ""; appDetector.running = true
            loadHotspotSettings()
        } else {
            NM.unwatch()
        }
    }
    Component.onDestruction: if (active) NM.unwatch()

    // ── Editor ──────────────────────────────────────────────────────────────
    property string editUuid: ""
    function edit(uuid) {
        editUuid = uuid
        Qt.callLater(() => page.scrollTo(editor))
    }
    // Used by the Wi-Fi page and the Wired rows. "" = the active Wi-Fi
    // connection. Opened from elsewhere, the connection list may not be
    // loaded yet: then it is resolved as soon as it arrives.
    property string pendingEdit: ""
    property bool hasPendingEdit: false
    function editByName(name) {
        const c = name !== "" ? NM.byName(name)
                : NM.connections.find(x => x.type === "802-11-wireless" && x.state === "activated")
        if (c) { hasPendingEdit = false; edit(c.uuid) }
        else { pendingEdit = name; hasPendingEdit = true }
    }
    Connections {
        target: NM
        function onConnectionsChanged() { if (page.hasPendingEdit) page.editByName(page.pendingEdit) }
    }

    function typeIcon(t) {
        return t === "802-11-wireless" ? "󰤨" : t === "802-3-ethernet" ? "󰈀"
             : t === "wireguard" ? "󰖂" : t === "vpn" ? "󰦝" : "󰛳"
    }
    function typeLabel(t) {
        return t === "802-11-wireless" ? "Wi-Fi" : t === "802-3-ethernet" ? "Ethernet"
             : t === "wireguard" ? "WireGuard" : t === "vpn" ? "OpenVPN" : t
    }
    readonly property color okColor: "#a6e3a1"
    readonly property color warnColor: "#e5c07b"
    readonly property color errColor: "#e06c75"
    readonly property color offColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)

    // ════════════════════════════════════════════════════════════════════════
    //  VPN
    // ════════════════════════════════════════════════════════════════════════
    property string askPassFor: ""      // VPN waiting for a password to connect
    property string credsFor: ""        // VPN whose username/password are being edited
    property string confirmDelete: ""
    property string importStatus: ""
    property bool hasZenity: false

    function connectVpn(c) {
        askPassFor = ""
        NM.up(c.uuid, {}, (ok, msg) => {
            if (!ok && /secret|password|auth/i.test(msg)) page.askPassFor = c.uuid
        })
    }

    function openCreds(c) {
        credsFor = c.uuid
        credUser.text = ""; credPass.text = ""
        NM.get(c.uuid, ["vpn.data"], false, (ok, m) => {
            const mm = (m["vpn.data"] || "").match(/(?:^|,\s*)username\s*=\s*([^,]*)/)
            credUser.text = mm ? mm[1].trim() : ""
        })
    }

    function importFile(path) {
        path = path.trim()
        if (path === "") return
        importStatus = "Importing…"
        NM.importVpn(path, (ok, res) => {
            page.importStatus = ok ? "Imported" : res
            if (ok) { importPath.text = ""; const c = NM.byUuid(res); if (c && c.type === "vpn") page.openCreds(c) }
        })
    }

    Process {
        id: configPicker
        command: ["bash", "-c", "zenity --file-selection --title='Import a VPN configuration' --file-filter='VPN configs | *.ovpn *.conf' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { const f = this.text.trim(); if (f !== "") importPath.text = f } }
    }

    // ── Former in-app OpenVPN configs (ran openvpn as a child of this window,
    //    which is why closing Settings dropped the VPN). Offered for import
    //    into NetworkManager once; passwords are not kept in the old file. ──
    readonly property string legacyPath: Quickshell.env("HOME") + "/.cache/quickshell-vpn-configs.json"
    property var legacy: []
    property string migrateStatus: ""
    Process {
        id: legacyReader
        command: ["bash", "-c", "cat " + NM.shq(page.legacyPath) + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.legacy = JSON.parse(this.text.trim() || "[]") } catch (e) { page.legacy = [] }
            }
        }
    }

    function migrate() {
        const list = legacy.slice()
        let failed = []
        const next = () => {
            if (list.length === 0) {
                // Keep a copy of the list without the passwords, drop the old file.
                const kept = legacy.map(c => ({ name: c.name, path: c.path, user: c.user || "" }))
                const b64 = Qt.btoa(unescape(encodeURIComponent(JSON.stringify(kept, null, 2))))
                NM.run(["bash", "-c", "echo " + NM.shq(b64) + " | base64 -d > " + NM.shq(page.legacyPath + ".migrated") +
                        " && rm -f " + NM.shq(page.legacyPath)], () => {
                    page.legacy = []
                    page.migrateStatus = failed.length ? "Could not import: " + failed.join(", ") : "Moved to NetworkManager"
                })
                return
            }
            const c = list.shift()
            const base = (c.path || "").split("/").pop().replace(/\.(ovpn|conf)$/i, "")
            const existing = NM.byName(base) || NM.byName(c.name)
            if (existing) { next(); return }      // already in NetworkManager (with its own credentials)
            NM.importVpn(c.path, (ok, uuid) => {
                if (!ok) { failed.push(c.name); next(); return }
                if (c.user) NM.setVpnCredentials(uuid, c.user, c.password || "", () => next())
                else next()
            })
        }
        migrateStatus = "Moving…"
        next()
    }

    StCard {
        title: "VPN"

        // Old in-app configs
        StRow {
            visible: page.legacy.length > 0
            icon: "󰁯"
            title: "Move saved OpenVPN configs to NetworkManager"
            subtitle: page.migrateStatus !== "" ? page.migrateStatus
                    : "So connections stay up when Settings closes (" + page.legacy.length + " saved)"
            StButton { text: "Move"; accent: true; implicitHeight: 30; onClicked: page.migrate() }
        }

        Text {
            Layout.fillWidth: true
            Layout.margins: 10
            visible: NM.vpns.length === 0
            text: "No VPN connections yet. Import an OpenVPN (.ovpn) or WireGuard (.conf) file below."
            color: Theme.primary; opacity: 0.45; font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: NM.vpns
            delegate: ColumnLayout {
                id: vpnItem
                required property var modelData
                readonly property var c: modelData
                readonly property bool up: NM.isUp(c)
                readonly property bool busy: NM.isBusy(c)
                readonly property string err: NM.errors[c.uuid] || ""
                Layout.fillWidth: true
                spacing: 4

                StRow {
                    icon: page.typeIcon(vpnItem.c.type)
                    title: vpnItem.c.name
                    subtitle: vpnItem.up ? "Connected" + (vpnItem.c.device ? " · " + vpnItem.c.device : "")
                            : vpnItem.busy ? (NM.pending[vpnItem.c.uuid] === "down" ? "Disconnecting…" : "Connecting…")
                            : vpnItem.err !== "" ? vpnItem.err
                            : page.typeLabel(vpnItem.c.type)

                    Rectangle {
                        width: 9; height: 9; radius: 4.5
                        color: vpnItem.up ? page.okColor : vpnItem.busy ? page.warnColor : vpnItem.err !== "" ? page.errColor : page.offColor
                    }
                    StButton {
                        text: vpnItem.up ? "Disconnect" : vpnItem.busy ? "Cancel" : "Connect"
                        accent: !vpnItem.up && !vpnItem.busy
                        dangerous: vpnItem.up || vpnItem.busy
                        implicitHeight: 30
                        onClicked: (vpnItem.up || vpnItem.busy) ? NM.down(vpnItem.c.uuid) : page.connectVpn(vpnItem.c)
                    }
                    StIconButton {
                        visible: vpnItem.c.type === "vpn"
                        icon: "󰌆"
                        onClicked: page.credsFor === vpnItem.c.uuid ? page.credsFor = "" : page.openCreds(vpnItem.c)
                    }
                    StIconButton { icon: "󰒓"; onClicked: page.edit(vpnItem.c.uuid) }
                    StIconButton {
                        visible: page.confirmDelete !== vpnItem.c.uuid
                        icon: "󰆴"
                        onClicked: page.confirmDelete = vpnItem.c.uuid
                    }
                    StButton {
                        visible: page.confirmDelete === vpnItem.c.uuid
                        text: "Delete"
                        dangerous: true
                        implicitHeight: 30
                        onClicked: { NM.remove(vpnItem.c.uuid); page.confirmDelete = "" }
                    }
                }

                // Password needed to connect (not saved)
                RowLayout {
                    visible: page.askPassFor === vpnItem.c.uuid
                    Layout.fillWidth: true
                    Layout.leftMargin: 46; Layout.rightMargin: 10; Layout.bottomMargin: 6
                    spacing: 8
                    StField {
                        id: askField
                        placeholder: "Password for " + vpnItem.c.name
                        password: true
                        onAccepted: askBtn.clicked()
                    }
                    StButton {
                        id: askBtn
                        text: "Connect"; accent: true; implicitHeight: 34
                        onClicked: {
                            const pw = askField.text
                            askField.text = ""
                            page.askPassFor = ""
                            NM.up(vpnItem.c.uuid, { password: pw })
                        }
                    }
                    StButton { text: "Cancel"; implicitHeight: 34; onClicked: page.askPassFor = "" }
                }
            }
        }

        // Credentials editor (OpenVPN)
        ColumnLayout {
            visible: page.credsFor !== ""
            Layout.fillWidth: true
            spacing: 4
            StRow {
                icon: "󰀄"
                title: "Username"
                subtitle: "For " + (NM.byUuid(page.credsFor) ? NM.byUuid(page.credsFor).name : "")
                StField { id: credUser; placeholder: "username" }
            }
            StRow {
                icon: "󰌆"
                title: "Password"
                subtitle: "Stored by NetworkManager; leave empty to keep the current one"
                StField { id: credPass; placeholder: "new password (optional)"; password: true }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 6
                spacing: 8
                StButton {
                    text: "Save"; icon: "󰆓"; accent: true
                    onClicked: {
                        const id = page.credsFor
                        NM.setVpnCredentials(id, credUser.text.trim(), credPass.text, (ok, msg) => {
                            page.importStatus = ok ? "Credentials saved" : msg
                        })
                        credPass.text = ""
                        page.credsFor = ""
                    }
                }
                StButton { text: "Cancel"; onClicked: page.credsFor = "" }
            }
        }

        // Import
        StRow {
            icon: "󰁯"
            title: "Import"
            subtitle: page.importStatus !== "" ? page.importStatus : "OpenVPN .ovpn or WireGuard .conf"
            StField { id: importPath; placeholder: "/path/to/config.ovpn"; onAccepted: page.importFile(text) }
            StIconButton { icon: "󰉋"; visible: page.hasZenity; onClicked: configPicker.running = true }
            StButton { text: "Import"; accent: true; implicitHeight: 30; enabled: importPath.text.trim() !== ""; onClicked: page.importFile(importPath.text) }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  SHARING
    // ════════════════════════════════════════════════════════════════════════
    property string hotspotStatus: ""
    property bool hotspotBusy: false
    property string hotspotBand: ""
    property var hotspotClients: []
    property string sharingStatus: ""
    property bool sharingBusy: false
    property var sharingClients: []
    readonly property var ethDev: NM.ethDevices.length > 0 ? NM.ethDevices[0] : null
    // Hotspot uses the Wi-Fi radio, so Wi-Fi drops while it is on, unless
    // the internet comes from somewhere else (Ethernet).
    readonly property bool wifiIsUplink: NM.devices.some(d => d.type === "wifi" && d.state === "connected")
                                         && !NM.devices.some(d => d.type === "ethernet" && d.state === "connected" && d.connection !== NM.sharingName)

    // Load the saved hotspot settings once the profile is known (keyed on its
    // id, so the 3s refresh doesn't overwrite what is being typed).
    readonly property string hotspotUuid: NM.hotspot ? NM.hotspot.uuid : ""
    onHotspotUuidChanged: if (active) loadHotspotSettings()

    function loadHotspotSettings() {
        const h = NM.hotspot
        if (!h) { if (hsSsid.text === "") hsSsid.text = "Hotspot"; return }
        NM.get(h.uuid, ["802-11-wireless.ssid", "802-11-wireless-security.psk", "802-11-wireless.band"], true, (ok, m) => {
            hsSsid.text = m["802-11-wireless.ssid"] || "Hotspot"
            hsPass.text = m["802-11-wireless-security.psk"] || ""
            page.hotspotBand = m["802-11-wireless.band"] || ""
        })
    }

    function startHotspot() {
        const ssid = hsSsid.text.trim(), pw = hsPass.text
        if (ssid === "") { hotspotStatus = "Give the hotspot a name"; return }
        if (pw.length < 8) { hotspotStatus = "The password needs at least 8 characters"; return }
        hotspotBusy = true; hotspotStatus = "Starting…"
        NM.startHotspot(ssid, pw, hotspotBand, (ok, msg) => {
            page.hotspotBusy = false
            page.hotspotStatus = ok ? "" : msg
        })
    }

    function setSharing(on) {
        if (!ethDev) return
        sharingBusy = true; sharingStatus = on ? "Turning on…" : "Turning off…"
        NM.setSharing(on, ethDev.device, (ok, msg) => {
            page.sharingBusy = false
            page.sharingStatus = ok ? "" : msg
        })
    }

    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: page.active && (NM.hotspotOn || NM.isUp(NM.sharing))
        onTriggered: {
            if (NM.hotspotOn) NM.clients(NM.wifiDevice, l => page.hotspotClients = l)
            if (NM.isUp(NM.sharing) && page.ethDev) NM.clients(page.ethDev.device, l => page.sharingClients = l)
        }
    }

    component ClientList: ColumnLayout {
        property var clients: []
        Layout.fillWidth: true
        Layout.leftMargin: 46
        spacing: 2
        Repeater {
            model: parent.clients
            delegate: Text {
                required property var modelData
                text: "󰟀  " + (modelData.name !== "" ? modelData.name + "  ·  " : "") + modelData.ip + "  ·  " + modelData.mac
                color: Theme.primary; opacity: 0.6; font.pixelSize: 11
            }
        }
    }

    StCard {
        title: "Sharing"

        // ── Hotspot ──
        StRow {
            visible: NM.wifiDevice !== ""
            icon: "󰀂"
            title: "Wi-Fi hotspot"
            subtitle: page.hotspotStatus !== "" ? page.hotspotStatus
                    : NM.hotspotOn ? "On · " + page.hotspotClients.length + (page.hotspotClients.length === 1 ? " device" : " devices") + " connected"
                    : page.wifiIsUplink ? "Shares this computer's internet. Wi-Fi disconnects while it is on"
                    : "Share this computer's internet over Wi-Fi"
            Rectangle { width: 9; height: 9; radius: 4.5; color: NM.hotspotOn ? page.okColor : page.hotspotBusy ? page.warnColor : page.offColor }
            StToggle {
                controlled: true
                checked: NM.hotspotOn
                onToggled: (v) => v ? page.startHotspot() : NM.stopHotspot()
            }
        }
        StRow {
            visible: NM.wifiDevice !== ""
            icon: "󰖩"
            title: "Network name"
            StField { id: hsSsid; placeholder: "Hotspot" }
        }
        StRow {
            visible: NM.wifiDevice !== ""
            icon: "󰌆"
            title: "Password"
            subtitle: "At least 8 characters"
            StField { id: hsPass; placeholder: "password"; password: true; onAccepted: page.startHotspot() }
        }
        StRow {
            visible: NM.wifiDevice !== ""
            icon: "󰹯"
            title: "Band"
            subtitle: "5 GHz is faster, 2.4 GHz reaches further and suits older devices"
            StSegmented {
                implicitWidth: 260
                model: [{ value: "", label: "Auto" }, { value: "bg", label: "2.4 GHz" }, { value: "a", label: "5 GHz" }]
                current: page.hotspotBand
                onSelected: (v) => page.hotspotBand = v
            }
            StButton {
                visible: NM.hotspotOn
                text: "Apply"; implicitHeight: 30
                onClicked: page.startHotspot()
            }
        }
        ClientList { visible: NM.hotspotOn; clients: page.hotspotClients }

        // ── Ethernet sharing ──
        StRow {
            visible: page.ethDev !== null
            icon: "󰌘"
            title: "Share over Ethernet"
            subtitle: page.sharingStatus !== "" ? page.sharingStatus
                    : NM.isUp(NM.sharing) ? "Sharing on " + page.ethDev.device + " · " + page.sharingClients.length + (page.sharingClients.length === 1 ? " device" : " devices")
                    : NM.sharingOn ? "On · plug a device into " + page.ethDev.device + " to share with it"
                    : "Give a device plugged into the Ethernet port this computer's internet"
            Rectangle { width: 9; height: 9; radius: 4.5; color: NM.isUp(NM.sharing) ? page.okColor : NM.sharingOn || page.sharingBusy ? page.warnColor : page.offColor }
            StToggle { controlled: true; checked: NM.sharingOn; onToggled: (v) => page.setSharing(v) }
        }
        Text {
            visible: page.ethDev !== null && NM.sharingOn
            Layout.fillWidth: true
            Layout.leftMargin: 46; Layout.rightMargin: 10
            text: "While on, a cable plugged into this port gets internet from this computer instead of giving it internet."
            color: Theme.primary; opacity: 0.45; font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        ClientList { visible: NM.isUp(NM.sharing); clients: page.sharingClients }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  WIRED
    // ════════════════════════════════════════════════════════════════════════
    StCard {
        title: "Wired"
        visible: NM.ethDevices.length > 0
        Repeater {
            model: NM.ethDevices
            delegate: StRow {
                id: ethRow
                required property var modelData
                readonly property bool connected: modelData.state === "connected"
                readonly property bool noCable: modelData.state === "unavailable"
                icon: "󰈀"
                title: "Ethernet (" + modelData.device + ")"
                subtitle: connected ? modelData.connection
                        : noCable ? "Cable not connected"
                        : modelData.state.indexOf("connecting") === 0 ? "Connecting…" : "Disconnected"
                Rectangle { width: 9; height: 9; radius: 4.5; color: ethRow.connected ? page.okColor : page.offColor }
                StIconButton {
                    visible: ethRow.connected
                    icon: "󰒓"
                    onClicked: page.editByName(ethRow.modelData.connection)
                }
                StToggle {
                    controlled: true
                    checked: ethRow.connected
                    onToggled: (v) => NM.deviceConnect(ethRow.modelData.device, v)
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  CONNECTIONS (advanced)
    // ════════════════════════════════════════════════════════════════════════
    StCard {
        title: "Connections"
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 10; Layout.bottomMargin: 2
            text: "Addresses, DNS, auto-connect and privacy settings for each saved connection."
            color: Theme.primary; opacity: 0.45; font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: NM.editable
            delegate: StRow {
                required property var modelData
                icon: page.typeIcon(modelData.type)
                title: modelData.name
                subtitle: page.typeLabel(modelData.type) + (NM.isUp(modelData) ? "  ·  Active on " + modelData.device : "")
                clickable: true
                onClicked: page.edit(modelData.uuid)
                Rectangle { visible: NM.isUp(modelData); width: 9; height: 9; radius: 4.5; color: page.okColor }
                Text { text: page.editUuid === modelData.uuid ? "󰅀" : "󰅂"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
            }
        }
    }

    ConnectionEditor {
        id: editor
        visible: page.editUuid !== ""
        uuid: page.editUuid
        onCloseRequested: page.editUuid = ""
    }

    // ════════════════════════════════════════════════════════════════════════
    //  VPN APPS
    // ════════════════════════════════════════════════════════════════════════
    property var vpnApps: []

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
            "elif flatpak info com.protonvpn.www >/dev/null 2>&1; then emit 'Proton VPN' 'flatpak run com.protonvpn.www' '󰦝'\nfi\n" +
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
