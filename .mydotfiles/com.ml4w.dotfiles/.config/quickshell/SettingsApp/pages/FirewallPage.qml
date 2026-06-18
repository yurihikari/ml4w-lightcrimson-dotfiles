import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Firewall"
    subheading: "Manage the uncomplicated firewall (UFW)"
    icon: "󰕥"

    property bool active: false

    property bool checked: false        // initial detection finished
    property bool installed: false
    property bool enabled: false        // real ufw status — the toggle follows THIS
    property bool busy: false           // a privileged action is running
    property bool loadingRules: false
    property bool rulesLoaded: false
    property var rules: []              // { num, text }

    onActiveChanged: if (active) detector.running = true

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // ── Detection (no root needed → no password prompt) ──────────────────
    Process {
        id: detector
        property string _buf: ""
        command: ["bash", "-c",
            "command -v ufw >/dev/null 2>&1 || { echo 'installed=no'; exit 0; }\n" +
            "echo 'installed=yes'\n" +
            "en=$(grep -iE '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 | tr -dc 'a-zA-Z')\n" +
            "if [ -z \"$en\" ]; then systemctl is-active --quiet ufw && en=yes || en=no; fi\n" +
            "echo \"enabled=$en\""
        ]
        stdout: SplitParser { onRead: detector._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            for (let l of detector._buf.trim().split("\n")) {
                let i = l.indexOf("="); if (i < 1) continue
                let k = l.substring(0, i), v = l.substring(i + 1).trim().toLowerCase()
                if (k === "installed") page.installed = (v === "yes")
                else if (k === "enabled") page.enabled = (v === "yes")
            }
            detector._buf = ""
            page.checked = true
            page.busy = false
            if (page.installed && page.enabled && !page.rulesLoaded) page.loadRules()
        }
    }

    // ── Rule listing (root → one polkit prompt) ──────────────────────────
    Process {
        id: rulesLoader
        property string _buf: ""
        command: ["bash", "-c", "pkexec ufw status numbered 2>/dev/null"]
        stdout: SplitParser { onRead: rulesLoader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            let out = []
            for (let l of rulesLoader._buf.split("\n")) {
                let m = l.match(/^\[\s*(\d+)\]\s+(.*)$/)
                if (m) out.push({ num: parseInt(m[1]), text: m[2].replace(/\s+/g, " ").trim() })
            }
            page.rules = out
            page.rulesLoaded = true
            page.loadingRules = false
            rulesLoader._buf = ""
        }
    }

    // ── Privileged mutations ─────────────────────────────────────────────
    // After enable/disable we re-detect, so `enabled` (and the toggle) only
    // change once the real ufw status changes — i.e. after a successful polkit
    // auth. Cancelling the prompt leaves status (and the toggle) untouched.
    Process { id: stateAction; onRunningChanged: if (!running) { page.rulesLoaded = false; detector.running = true } }
    Process { id: ruleAction;  onRunningChanged: if (!running) { page.busy = false; page.loadRules() } }

    function loadRules() { page.loadingRules = true; rulesLoader._buf = ""; rulesLoader.running = true }
    function setEnabled(target) {
        page.busy = true
        stateAction.command = ["pkexec", "ufw", "--force", target ? "enable" : "disable"]
        stateAction.running = true
    }
    function deleteRule(num) { page.busy = true; ruleAction.command = ["pkexec", "ufw", "--force", "delete", "" + num]; ruleAction.running = true }
    function addRule(action, spec) { page.busy = true; ruleAction.command = ["pkexec", "ufw", action, spec]; ruleAction.running = true }

    // ════════════════════════════════════════════════════════════════════
    //  STATE 1 — not installed
    // ════════════════════════════════════════════════════════════════════
    StCard {
        visible: page.checked && !page.installed
        StRow {
            icon: "󰕥"
            title: "UFW is not installed"
            subtitle: "Install the 'ufw' package to manage your firewall here"
            StButton {
                text: "Install"; icon: "󰏗"; accent: true; implicitHeight: 32
                onClicked: Quickshell.execDetached(["kitty", "--class", "dotfiles-floating", "-e", "sh", "-c", "sudo pacman -S ufw; echo; read -p 'Press enter to close…'"])
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  STATE 2 — installed: status + controlled toggle (works disabled/enabled)
    // ════════════════════════════════════════════════════════════════════
    StCard {
        visible: page.checked && page.installed
        StRow {
            icon: "󰕥"
            title: page.enabled ? "Firewall is active" : "Firewall is disabled"
            subtitle: page.busy ? "Applying… confirm the password prompt"
                   : page.enabled ? (page.rules.length + " rule" + (page.rules.length === 1 ? "" : "s") + " configured")
                                   : "Your system is not protected by UFW"
            Rectangle { width: 9; height: 9; radius: 4.5; color: page.enabled ? "#a6e3a1" : "#e06c75" }
            StToggle {
                controlled: true               // knob follows page.enabled, not the click
                checked: page.enabled
                onToggled: (v) => page.setEnabled(v)
            }
        }
    }

    // ── Add rule (only when enabled) ──
    StCard {
        title: "Add rule"
        visible: page.checked && page.installed && page.enabled

        StRow {
            icon: "󰐕"
            title: "New rule"
            subtitle: "Allow or deny incoming traffic on a port"
            StSegmented {
                id: actionSeg
                implicitWidth: 150
                property string value: "allow"
                model: [ { value: "allow", label: "Allow", icon: "󰄬" }, { value: "deny", label: "Deny", icon: "󰅖" } ]
                current: value
                onSelected: (v) => value = v
            }
        }

        StRow {
            icon: "󰳘"
            title: "Port / service"
            subtitle: "e.g. 22, 80/tcp, ssh, 1000:2000"
            Rectangle {
                Layout.preferredWidth: 120
                implicitHeight: 34
                radius: 9
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                border.color: portInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                border.width: 1
                TextField {
                    id: portInput
                    anchors.fill: parent
                    anchors.margins: 2
                    placeholderText: "port"
                    placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    color: Theme.primary
                    font.pixelSize: 13
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    onAccepted: addBtn.submit()
                }
            }
            StSegmented {
                id: protoSeg
                implicitWidth: 170
                property string value: "any"
                model: [ { value: "any", label: "Any" }, { value: "tcp", label: "TCP" }, { value: "udp", label: "UDP" } ]
                current: value
                onSelected: (v) => value = v
            }
        }

        StButton {
            id: addBtn
            Layout.fillWidth: true
            implicitHeight: 42
            text: "Add rule"
            icon: "󰐕"
            accent: true
            enabled: !page.busy && portInput.text.trim() !== ""
            function submit() {
                let p = portInput.text.trim()
                if (p === "" || page.busy) return
                page.addRule(actionSeg.value, protoSeg.value === "any" ? p : (p + "/" + protoSeg.value))
                portInput.text = ""
            }
            onClicked: submit()
        }
    }

    // ── Rules list (only when enabled) ──
    StCard {
        title: "Rules"
        visible: page.checked && page.installed && page.enabled

        StRow {
            icon: "󰑓"
            title: "Active rules"
            subtitle: page.loadingRules ? "Loading…" : "Tap the trash icon to remove a rule"
            StIconButton { icon: "󰑓"; busy: page.loadingRules; onClicked: page.loadRules() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 6
            Layout.preferredHeight: 44
            color: "transparent"
            visible: !page.loadingRules && page.rules.length === 0
            Text { anchors.centerIn: parent; text: "No rules — using the default policy"; color: Theme.primary; opacity: 0.4; font.pixelSize: 12 }
        }

        Repeater {
            model: page.rules
            delegate: StRow {
                required property var modelData
                icon: (modelData.text.indexOf("DENY") !== -1 || modelData.text.indexOf("REJECT") !== -1) ? "󰅖" : "󰄬"
                title: modelData.text
                subtitle: "Rule #" + modelData.num
                StIconButton {
                    icon: "󰆴"
                    enabled: !page.busy
                    onClicked: page.deleteRule(modelData.num)
                }
            }
        }
    }

    // ── Disabled hint ──
    StCard {
        visible: page.checked && page.installed && !page.enabled
        StRow {
            icon: "󰟾"
            title: "Enable the firewall to manage rules"
            subtitle: "Turn on UFW with the switch above to add or remove rules"
        }
    }

    // ── First-load placeholder ──
    Text {
        visible: !page.checked
        text: "Checking firewall status…"
        color: Theme.primary; opacity: 0.4; font.pixelSize: 13
    }
}
