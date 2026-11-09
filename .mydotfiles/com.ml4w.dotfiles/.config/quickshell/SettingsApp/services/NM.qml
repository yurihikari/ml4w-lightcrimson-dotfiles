pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager, as the Settings app sees it.
//
// Everything goes through nmcli, so NetworkManager stays the single source of
// truth: a VPN, hotspot or shared connection started here keeps running after
// the Settings window closes, and anything started elsewhere (nm-applet, nmcli,
// a previous Settings session) shows up here as soon as the window opens.
//
// Pages call `watch()` / `unwatch()` while they are visible; the state is only
// polled while someone is watching.
Singleton {
    id: nm

    // ── State ───────────────────────────────────────────────────────────────
    // [{ device, type, state, connection }]
    property var devices: []
    // [{ name, uuid, type, device, state }]  state: "" | "activating" | "activated" | "deactivating"
    property var connections: []
    // uuid → "up" | "down" while an nmcli call for it is running
    property var pending: ({})
    // uuid → last error message for that connection
    property var errors: ({})

    readonly property string hotspotName: "Hotspot"
    readonly property string sharingName: "Wired sharing"

    readonly property var vpns: connections.filter(c => c.type === "vpn" || c.type === "wireguard")
    // Connections worth editing (not bridges, loopback, docker, …)
    readonly property var editable: connections.filter(c =>
        c.type === "802-11-wireless" || c.type === "802-3-ethernet" || c.type === "vpn" || c.type === "wireguard")
    readonly property var ethDevices: devices.filter(d => d.type === "ethernet" && d.state !== "unmanaged")
    readonly property string wifiDevice: {
        const d = devices.find(x => x.type === "wifi")
        return d ? d.device : ""
    }

    function byName(name) { return connections.find(c => c.name === name) || null }
    function byUuid(uuid) { return connections.find(c => c.uuid === uuid) || null }
    function isUp(c) { return c !== null && c.state === "activated" }
    function isBusy(c) {
        return c !== null && (c.state === "activating" || c.state === "deactivating" || pending[c.uuid] !== undefined)
    }

    readonly property var hotspot: byName(hotspotName)
    readonly property bool hotspotOn: isUp(hotspot)
    readonly property var sharing: byName(sharingName)

    // ── Watching ────────────────────────────────────────────────────────────
    property int watchers: 0
    function watch() { watchers += 1; refresh() }
    function unwatch() { watchers = Math.max(0, watchers - 1) }
    Timer { interval: 3000; repeat: true; running: nm.watchers > 0; onTriggered: nm.refresh() }

    // ── Running nmcli ───────────────────────────────────────────────────────
    // run(["nmcli", ...], (ok, out, err) => {...}): one process per call.
    function run(cmd, done) {
        const p = procComp.createObject(nm, { command: cmd, done: done || null })
        p.running = true
    }

    Component {
        id: procComp
        Process {
            id: proc
            property var done: null
            property int code: -1
            property int left: 3          // exit + stdout + stderr
            function step() {
                left -= 1
                if (left > 0) return
                if (done) done(code === 0, out.text, err.text)
                proc.destroy()
            }
            stdout: StdioCollector { id: out; onStreamFinished: proc.step() }
            stderr: StdioCollector { id: err; onStreamFinished: proc.step() }
            onExited: (exitCode) => { proc.code = exitCode; proc.step() }
        }
    }

    // nmcli -t escapes ':' and '\' in values; split on the unescaped colons.
    function splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (ch === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (ch === ":") { out.push(cur); cur = ""; continue }
            cur += ch
        }
        out.push(cur)
        return out
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // Short, human message from nmcli's stderr.
    function cleanError(err) {
        const t = (err || "").trim().split("\n").filter(l => l.trim() !== "").pop() || "Failed"
        return t.replace(/^Error:\s*/, "").replace(/^Connection activation failed:\s*/, "")
    }

    function setPending(uuid, what) {
        const p = Object.assign({}, pending)
        if (what) p[uuid] = what; else delete p[uuid]
        pending = p
    }
    function setError(uuid, msg) {
        const e = Object.assign({}, errors)
        if (msg) e[uuid] = msg; else delete e[uuid]
        errors = e
    }

    // ── Refresh ─────────────────────────────────────────────────────────────
    function refresh() {
        run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"], (ok, out) => {
            if (!ok) return
            nm.devices = out.trim().split("\n").filter(l => l !== "").map(l => {
                const f = nm.splitTerse(l)
                return { device: f[0], type: f[1], state: f[2], connection: f[3] || "" }
            })
        })
        run(["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,ACTIVE,STATE", "connection", "show"], (ok, out) => {
            if (!ok) return
            nm.connections = out.trim().split("\n").filter(l => l !== "").map(l => {
                const f = nm.splitTerse(l)
                return { name: f[0], uuid: f[1], type: f[2], device: f[3] || "",
                         state: f[4] === "yes" ? (f[5] || "activated") : "" }
            })
        })
    }

    // ── Connections ─────────────────────────────────────────────────────────
    // up(uuid, { password, ifname }, done): activates and waits for the result.
    function up(uuid, opts, done) {
        opts = opts || {}
        setPending(uuid, "up")
        setError(uuid, "")
        let cmd = "nmcli connection up uuid " + shq(uuid)
        if (opts.ifname) cmd += " ifname " + shq(opts.ifname)
        if (opts.password !== undefined) {
            // Secrets for this one activation only, via a private temp file.
            cmd = "f=$(mktemp -p \"${XDG_RUNTIME_DIR:-/tmp}\"); chmod 600 \"$f\"; " +
                  "printf 'vpn.secrets.password:%s\\n' " + shq(opts.password) + " > \"$f\"; " +
                  cmd + " passwd-file \"$f\"; r=$?; rm -f \"$f\"; exit $r"
        }
        run(["bash", "-c", cmd], (ok, out, err) => {
            nm.setPending(uuid, "")
            if (!ok) nm.setError(uuid, nm.cleanError(err))
            nm.refresh()
            if (done) done(ok, nm.cleanError(err))
        })
    }

    function down(uuid, done) {
        setPending(uuid, "down")
        run(["nmcli", "connection", "down", "uuid", uuid], (ok, out, err) => {
            nm.setPending(uuid, "")
            nm.refresh()
            if (done) done(ok, nm.cleanError(err))
        })
    }

    function remove(uuid, done) {
        run(["nmcli", "connection", "delete", "uuid", uuid], (ok, out, err) => {
            nm.refresh()
            if (done) done(ok, nm.cleanError(err))
        })
    }

    // modify(uuid, ["ipv4.method", "auto", ...], done)
    function modify(uuid, args, done) {
        run(["nmcli", "connection", "modify", "uuid", uuid].concat(args), (ok, out, err) => {
            nm.refresh()
            if (done) done(ok, nm.cleanError(err))
        })
    }

    // Reads settings: get(uuid, ["ipv4.method", ...], secrets, (ok, map) => …)
    function get(uuid, fields, secrets, done) {
        const cmd = ["nmcli"].concat(secrets ? ["-s"] : []).concat(["-t", "-f", fields.join(","), "connection", "show", "uuid", uuid])
        run(cmd, (ok, out) => {
            const map = {}
            for (const l of out.split("\n")) {
                const i = l.indexOf(":")
                if (i > 0) map[l.substring(0, i)] = l.substring(i + 1)
            }
            done(ok, map)
        })
    }

    // Live IP details of a device: (ok, { ip4, gateway, dns, ip6 })
    function deviceDetails(dev, done) {
        run(["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS", "device", "show", dev], (ok, out) => {
            const r = { ip4: [], gateway: "", dns: [], ip6: [] }
            for (const l of out.split("\n")) {
                const i = l.indexOf(":")
                if (i < 0) continue
                const k = l.substring(0, i), v = l.substring(i + 1)
                if (v === "" || v === "--") continue
                if (k.startsWith("IP4.ADDRESS")) r.ip4.push(v)
                else if (k === "IP4.GATEWAY") r.gateway = v
                else if (k.startsWith("IP4.DNS")) r.dns.push(v)
                else if (k.startsWith("IP6.ADDRESS")) r.ip6.push(v)
            }
            done(ok, r)
        })
    }

    // ── VPN ─────────────────────────────────────────────────────────────────
    // Imports an .ovpn (OpenVPN) or WireGuard .conf; done(ok, uuidOrError)
    function importVpn(path, done) {
        const cmd = "f=" + shq(path) + "; t=openvpn; " +
                    "grep -qi '^\\s*\\[Interface\\]' \"$f\" 2>/dev/null && t=wireguard; " +
                    "nmcli connection import type \"$t\" file \"$f\""
        run(["bash", "-c", cmd], (ok, out, err) => {
            const m = out.match(/\(([0-9a-f-]{36})\)/)
            nm.refresh()
            done(ok && m !== null, ok && m ? m[1] : nm.cleanError(err))
        })
    }

    // Username / password of an OpenVPN connection. A new password is stored
    // by NetworkManager (root-only file); an empty one keeps the current.
    function setVpnCredentials(uuid, user, password, done) {
        const esc = s => String(s).replace(/\\/g, "\\\\").replace(/,/g, "\\,")
        let args = ["+vpn.data", "username=" + esc(user)]
        if (password !== "") args = args.concat(["+vpn.data", "password-flags=0", "vpn.secrets", "password=" + esc(password)])
        modify(uuid, args, done)
    }

    // ── Hotspot ─────────────────────────────────────────────────────────────
    // band: "" (auto) | "bg" (2.4 GHz) | "a" (5 GHz)
    function startHotspot(ssid, password, band, done) {
        const dev = wifiDevice
        if (dev === "") { if (done) done(false, "No Wi-Fi device"); return }
        if (hotspot) {
            const id = hotspot.uuid
            setPending(id, "up")
            modify(id, ["802-11-wireless.ssid", ssid, "802-11-wireless-security.key-mgmt", "wpa-psk",
                        "802-11-wireless-security.psk", password, "802-11-wireless.band", band,
                        "connection.autoconnect", "no"], (ok, msg) => {
                if (!ok) { nm.setPending(id, ""); if (done) done(false, msg); return }
                nm.up(id, { ifname: dev }, done)
            })
        } else {
            const cmd = ["nmcli", "device", "wifi", "hotspot", "ifname", dev, "con-name", hotspotName,
                         "ssid", ssid, "password", password].concat(band !== "" ? ["band", band] : [])
            run(cmd, (ok, out, err) => {
                nm.refresh()
                if (done) done(ok, nm.cleanError(err))
            })
        }
    }

    // Connect / disconnect a device (Ethernet port) with its usual connection.
    function deviceConnect(dev, on, done) {
        run(["nmcli", "device", on ? "connect" : "disconnect", dev], (ok, out, err) => {
            nm.refresh()
            if (done) done(ok, nm.cleanError(err))
        })
    }

    function stopHotspot(done) {
        if (hotspot) down(hotspot.uuid, done)
    }

    // Devices reachable on an interface we share on (hotspot / Ethernet
    // sharing): (list of { ip, mac, name }); names from NetworkManager's
    // dnsmasq leases when readable.
    function clients(dev, done) {
        if (!dev) { done([]); return }
        const cmd = "ip -4 neigh show dev " + shq(dev) + " 2>/dev/null | awk '$0 !~ /FAILED|INCOMPLETE/ {print $1\" \"$3}'; " +
                    "echo '--'; cat /var/lib/NetworkManager/dnsmasq-" + dev + ".leases 2>/dev/null"
        run(["bash", "-c", cmd], (ok, out) => {
            const parts = out.split("--\n")
            const names = {}
            for (const l of (parts[1] || "").split("\n")) {
                const f = l.trim().split(/\s+/)
                if (f.length >= 4) names[f[2]] = f[3] === "*" ? "" : f[3]
            }
            const list = []
            for (const l of (parts[0] || "").split("\n")) {
                const f = l.trim().split(" ")
                if (f.length >= 2 && f[1] !== "") list.push({ ip: f[0], mac: f[1], name: names[f[0]] || "" })
            }
            done(list)
        })
    }

    // ── Sharing over Ethernet ───────────────────────────────────────────────
    // While on, the Ethernet port shares this computer's internet: whatever is
    // plugged in gets an address from us (NetworkManager "shared" mode). It is
    // set to connect automatically, so it also applies to a cable plugged in
    // later, until it is switched off.
    function setSharing(on, dev, done) {
        if (on) {
            const finish = (ok, msg) => {
                if (!ok) { if (done) done(false, msg); return }
                const c = nm.byName(nm.sharingName)
                nm.loadSharingAuto()
                // No cable yet is fine: it activates when one is plugged in.
                if (c) nm.up(c.uuid, { ifname: dev }, () => { nm.setError(c.uuid, ""); if (done) done(true, "") })
                else if (done) done(true, "")
            }
            const props = ["ipv4.method", "shared", "ipv6.method", "ignore",
                           "connection.autoconnect", "yes", "connection.autoconnect-priority", "100"]
            if (sharing) modify(sharing.uuid, ["connection.interface-name", dev].concat(props), finish)
            else run(["nmcli", "connection", "add", "type", "ethernet", "ifname", dev, "con-name", sharingName].concat(props),
                     (ok, out, err) => { nm.refresh(); Qt.callLater(() => finish(ok, nm.cleanError(err))) })
        } else if (sharing) {
            const id = sharing.uuid
            modify(id, ["connection.autoconnect", "no"], () => {
                nm.loadSharingAuto()
                if (nm.isUp(nm.byUuid(id))) down(id, done)
                else if (done) done(true, "")
            })
        }
    }

    // "On" = armed to connect automatically, or currently active.
    readonly property bool sharingOn: sharing !== null && (isUp(sharing) || sharingAuto)
    property bool sharingAuto: false
    readonly property string sharingUuid: sharing ? sharing.uuid : ""
    onSharingUuidChanged: loadSharingAuto()
    function loadSharingAuto() {
        if (sharingUuid === "") { sharingAuto = false; return }
        get(sharingUuid, ["connection.autoconnect"], false, (ok, m) => nm.sharingAuto = m["connection.autoconnect"] === "yes")
    }
}
