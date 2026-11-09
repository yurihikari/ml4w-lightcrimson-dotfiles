import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.CustomTheme
import qs.SettingsApp.services

// In-app editor for one NetworkManager connection (instead of nmtui): connect
// automatically, metered, IPv4 (automatic / manual address, gateway), DNS,
// IPv6, MAC address randomisation for Wi-Fi, and for VPNs whether all traffic
// goes through the tunnel. Shows the live addresses while it is active.
//
// Changes are applied with nmcli; an active connection is reconnected so they
// take effect.
StCard {
    id: ed
    property string uuid: ""
    signal closeRequested()

    readonly property var conn: NM.byUuid(uuid)
    readonly property string ctype: conn ? conn.type : ""
    readonly property bool isWifi: ctype === "802-11-wireless"
    readonly property bool isVpn: ctype === "vpn" || ctype === "wireguard"
    readonly property bool active: NM.isUp(conn)

    title: "Connection settings"

    // Edited values
    property bool autoconnect: true
    property bool metered: false
    property string v4method: "auto"
    property string v6method: "auto"
    property bool ignoreAutoDns: false
    property bool neverDefault: false
    property string mac: ""
    property bool loaded: false
    property string status: ""
    property bool busy: false
    property var live: null

    function typeLabel(t) {
        return t === "802-11-wireless" ? "Wi-Fi" : t === "802-3-ethernet" ? "Ethernet"
             : t === "wireguard" ? "WireGuard" : t === "vpn" ? "VPN" : t
    }

    function load() {
        loaded = false; status = ""; live = null
        if (!conn) return
        let fields = ["connection.autoconnect", "connection.metered", "ipv4.method", "ipv4.addresses",
                      "ipv4.gateway", "ipv4.dns", "ipv4.ignore-auto-dns", "ipv4.never-default", "ipv6.method"]
        if (isWifi) fields.push("802-11-wireless.cloned-mac-address")
        NM.get(uuid, fields, false, (ok, m) => {
            ed.autoconnect = m["connection.autoconnect"] !== "no"
            ed.metered = m["connection.metered"] === "yes"
            ed.v4method = m["ipv4.method"] || "auto"
            addrField.text = (m["ipv4.addresses"] || "").split(",")[0].trim()
            gwField.text = m["ipv4.gateway"] || ""
            dnsField.text = (m["ipv4.dns"] || "").split(",").map(x => x.trim()).filter(x => x !== "").join(", ")
            ed.ignoreAutoDns = m["ipv4.ignore-auto-dns"] === "yes"
            ed.neverDefault = m["ipv4.never-default"] === "yes"
            ed.v6method = m["ipv6.method"] || "auto"
            ed.mac = m["802-11-wireless.cloned-mac-address"] || ""
            ed.loaded = true
        })
        if (conn.device) NM.deviceDetails(conn.device, (ok, r) => ed.live = r)
    }
    onUuidChanged: load()
    Component.onCompleted: load()

    function apply() {
        let args = ["connection.autoconnect", autoconnect ? "yes" : "no",
                    "connection.metered", metered ? "yes" : "no",
                    "ipv4.method", v4method]
        if (v4method === "manual") {
            let a = addrField.text.trim()
            if (a === "") { status = "Enter an address, e.g. 192.168.1.50/24"; return }
            if (a.indexOf("/") < 0) a += "/24"
            args = args.concat(["ipv4.addresses", a, "ipv4.gateway", gwField.text.trim()])
        } else if (v4method === "auto") {
            args = args.concat(["ipv4.addresses", "", "ipv4.gateway", ""])
        }
        const dns = dnsField.text.split(/[\s,]+/).filter(x => x !== "").join(",")
        args = args.concat(["ipv4.dns", dns, "ipv4.ignore-auto-dns", (ignoreAutoDns && dns !== "") ? "yes" : "no",
                            "ipv6.method", v6method])
        if (isVpn) args = args.concat(["ipv4.never-default", neverDefault ? "yes" : "no"])
        if (isWifi) args = args.concat(["802-11-wireless.cloned-mac-address", mac])

        busy = true; status = "Applying…"
        NM.modify(uuid, args, (ok, msg) => {
            if (!ok) { ed.busy = false; ed.status = msg; return }
            if (!ed.active) { ed.busy = false; ed.status = "Saved"; return }
            ed.status = "Saved · reconnecting…"
            NM.up(uuid, {}, (ok2, msg2) => {
                ed.busy = false
                ed.status = ok2 ? "Saved and applied" : "Saved, but reconnecting failed: " + msg2
                ed.load()
            })
        })
    }

    // ── Header ──
    StRow {
        icon: ed.isWifi ? "󰤨" : ed.isVpn ? "󰦝" : "󰈀"
        title: ed.conn ? ed.conn.name : ""
        subtitle: ed.typeLabel(ed.ctype) + (ed.active ? "  ·  Active on " + ed.conn.device : "")
        StButton {
            text: "Full editor"
            icon: "󰒓"
            implicitHeight: 30
            onClicked: Quickshell.execDetached(["nm-connection-editor", "--edit=" + ed.uuid])
        }
        StIconButton { icon: "󰅖"; onClicked: ed.closeRequested() }
    }

    // ── Live details ──
    StRow {
        visible: ed.active && ed.live !== null && !ed.isVpn
        icon: "󰩟"
        title: ed.live && ed.live.ip4.length > 0 ? ed.live.ip4.join(", ") : "No IPv4 address"
        subtitle: ed.live ? ("Gateway " + (ed.live.gateway || "—") + "  ·  DNS " + (ed.live.dns.length ? ed.live.dns.join(", ") : "—")) : ""
    }

    // ── General ──
    StRow {
        icon: "󰑓"
        title: "Connect automatically"
        subtitle: "Join this connection whenever it is available"
        StToggle { controlled: true; checked: ed.autoconnect; onToggled: (v) => ed.autoconnect = v }
    }
    StRow {
        visible: !ed.isVpn
        icon: "󰾅"
        title: "Metered connection"
        subtitle: "Apps should limit background data on it"
        StToggle { controlled: true; checked: ed.metered; onToggled: (v) => ed.metered = v }
    }
    StRow {
        visible: ed.isVpn
        icon: "󰖟"
        title: "Send all traffic through the VPN"
        subtitle: ed.neverDefault ? "Off: only the VPN's own networks use it" : "On: all internet traffic goes through the tunnel"
        StToggle { controlled: true; checked: !ed.neverDefault; onToggled: (v) => ed.neverDefault = !v }
    }
    StRow {
        visible: ed.isWifi
        icon: "󰒃"
        title: "MAC address"
        subtitle: "Random or stable addresses make the device harder to track"
        StSegmented {
            implicitWidth: 330
            model: [{ value: "", label: "Default" }, { value: "permanent", label: "Device" },
                    { value: "stable", label: "Stable" }, { value: "random", label: "Random" }]
            current: ed.mac
            onSelected: (v) => ed.mac = v
        }
    }

    // ── IPv4 ──
    StRow {
        visible: !ed.isVpn
        icon: "󰩠"
        title: "IPv4"
        subtitle: ed.v4method === "manual" ? "Fixed address" : ed.v4method === "shared" ? "Shared to other computers"
                : ed.v4method === "disabled" ? "Disabled" : "Automatic (DHCP)"
        StSegmented {
            implicitWidth: 300
            model: ed.v4method === "shared"
                ? [{ value: "auto", label: "Automatic" }, { value: "manual", label: "Manual" }, { value: "shared", label: "Shared" }]
                : [{ value: "auto", label: "Automatic" }, { value: "manual", label: "Manual" }, { value: "disabled", label: "Off" }]
            current: ed.v4method
            onSelected: (v) => ed.v4method = v
        }
    }
    StRow {
        visible: !ed.isVpn && ed.v4method === "manual"
        icon: "󰩟"
        title: "Address"
        subtitle: "With prefix, e.g. 192.168.1.50/24"
        StField { id: addrField; placeholder: "192.168.1.50/24" }
    }
    StRow {
        visible: !ed.isVpn && ed.v4method === "manual"
        icon: "󰑩"
        title: "Gateway"
        StField { id: gwField; placeholder: "192.168.1.1" }
    }

    // ── DNS ──
    StRow {
        icon: "󰇖"
        title: "DNS servers"
        subtitle: "Comma separated; empty uses the network's"
        StField { id: dnsField; placeholder: "1.1.1.1, 9.9.9.9" }
    }
    StRow {
        visible: dnsField.text.trim() !== ""
        icon: "󰒘"
        title: "Use only these DNS servers"
        subtitle: "Ignore the DNS servers the network provides"
        StToggle { controlled: true; checked: ed.ignoreAutoDns; onToggled: (v) => ed.ignoreAutoDns = v }
    }

    // ── IPv6 ──
    StRow {
        visible: !ed.isVpn
        icon: "󰩠"
        title: "IPv6"
        StSegmented {
            implicitWidth: 220
            model: (ed.v6method === "auto" || ed.v6method === "disabled")
                ? [{ value: "auto", label: "Automatic" }, { value: "disabled", label: "Off" }]
                : [{ value: "auto", label: "Automatic" }, { value: "disabled", label: "Off" }, { value: ed.v6method, label: ed.v6method }]
            current: ed.v6method
            onSelected: (v) => ed.v6method = v
        }
    }

    // ── Actions ──
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 6
        spacing: 8
        StButton { text: ed.busy ? "Applying…" : "Apply"; icon: "󰄬"; accent: true; enabled: ed.loaded && !ed.busy; onClicked: ed.apply() }
        StButton { text: "Revert"; enabled: !ed.busy; onClicked: ed.load() }
        Text {
            Layout.fillWidth: true
            text: ed.status
            color: Theme.primary; opacity: 0.6; font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
