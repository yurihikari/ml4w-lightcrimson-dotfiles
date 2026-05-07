import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

PanelWindow {
    id: popup
    property bool active: false
    property string currentTab: "Network"
    
    // 1. Wayland-safe exit animation state
    property bool isAnimating: false
    visible: active || isAnimating

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: popup.active = false }

    // ─── WiFi ──────────────────────────────────────────────────────────────
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string wifiConnecting: ""
    property string wifiPassword: ""
    property string wifiPasswordTarget: ""
    property bool showPasswordFor: false

    // ─── Bluetooth ─────────────────────────────────────────────────────────
    property var btDevices: []
    property bool btScanning: false

    // ─── Gamemode / Power profile ──────────────────────────────────────────
    property bool gamemodeActive: false
    property string powerProfile: "balanced"
    property bool tuxedoInstalled: false

    // ─── Extended metrics ──────────────────────────────────────────────────
    property real localCpuUsage: 0
    property real cpuTemp: 0
    property real cpuFreq: 0
    property real gpuTemp: 0
    property real gpuUsage: 0
    property string gpuVendor: ""
    property real memUsedGB: 0
    property real memTotalGB: 0
    property real netRxKBs: 0
    property real netTxKBs: 0
    property string uptimeStr: ""
    property int batteryPct: -1
    property bool batteryCharging: false

    // ─── Sparkline history (last 30 samples) ───────────────────────────────
    property var cpuTempHistory: []
    property var gpuTempHistory: []
    property var cpuUsageHistory: []
    property var netRxHistory: []
    property var netTxHistory: []
    property real netMaxSeen: 100

    function pushHist(arr, val, max) {
        let copy = arr.slice()
        copy.push(val)
        if (copy.length > max) copy.shift()
        return copy
    }

    property string _wifiBuf: ""
    property string _btBuf: ""

    // ═══════════════════════════════════════════════════════════════════════
    //  PROCESSES
    // ═══════════════════════════════════════════════════════════════════════

    Process {
        id: wifiScanner
        command: ["bash", "-c",
            "SAVED=$(nmcli -t -f NAME con show 2>/dev/null)\n" +
            "nmcli -t -f SSID,SIGNAL,SECURITY,ACTIVE dev wifi list 2>/dev/null | while IFS= read -r line; do\n" +
            "  ssid=$(echo \"$line\" | rev | cut -d: -f4- | rev)\n" +
            "  rest=$(echo \"$line\" | rev | cut -d: -f1-3 | rev)\n" +
            "  signal=$(echo \"$rest\" | cut -d: -f1)\n" +
            "  security=$(echo \"$rest\" | cut -d: -f2)\n" +
            "  active=$(echo \"$rest\" | cut -d: -f3 | tr -d '\\r')\n" +
            "  [ -z \"$ssid\" ] || [ \"$ssid\" = \"--\" ] && continue\n" +
            "  if echo \"$SAVED\" | grep -qxF \"$ssid\"; then saved=yes; else saved=no; fi\n" +
            "  printf '%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\n' \"$ssid\" \"$signal\" \"$security\" \"$active\" \"$saved\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: { popup._wifiBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                popup.wifiScanning = false
                let lines = popup._wifiBuf.trim().split("\n")
                popup._wifiBuf = ""
                let seen = {}, nets = []
                for (let l of lines) {
                    let p = l.split("\x1f")
                    if (p.length < 5) continue
                    let ssid = p[0].trim()
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    nets.push({ ssid, signal: parseInt(p[1])||0, security: p[2].trim(),
                                active: p[3].trim()==="yes", saved: p[4].trim()==="yes" })
                }
                nets.sort((a,b) => b.signal - a.signal)
                popup.wifiNetworks = nets
            }
        }
    }

    Process { id: wifiConnector;   onRunningChanged: { if (!running) { popup.wifiConnecting=""; wifiScanner.running=true } } }
    Process { id: wifiDisconnector; onRunningChanged: { if (!running) wifiScanner.running=true } }
    Process { id: wifiForget;       onRunningChanged: { if (!running) wifiScanner.running=true } }

    Process {
        id: btScanner
        command: ["bash", "-c",
            "bluetoothctl devices 2>/dev/null | while read _ mac name; do\n" +
            "  connected=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Connected: yes')\n" +
            "  paired=$(bluetoothctl info $mac 2>/dev/null | grep -c 'Paired: yes')\n" +
            "  echo \"$mac|$name|$connected|$paired\"\n" +
            "done"
        ]
        stdout: SplitParser { onRead: { popup._btBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                popup.btScanning = false
                let lines = popup._btBuf.trim().split("\n"); popup._btBuf = ""
                let devs = []
                for (let l of lines) {
                    let p = l.split("|")
                    if (p.length < 4) continue
                    devs.push({ mac: p[0].trim(), name: p[1].trim(),
                                connected: p[2].trim()==="1", paired: p[3].trim()==="1" })
                }
                popup.btDevices = devs
            }
        }
    }

    Process { id: btAction; onRunningChanged: { if (!running) btScanner.running=true } }

    Process {
        id: localExec
        function run(args) { command = args; running = true }
    }

    Process {
        id: gamemodeExec
        function apply(enable) {
            let blur     = enable ? "0" : "1"
            let anim     = enable ? "0" : "1"
            let rounding = enable ? "0" : "12"
            command = ["bash", "-c",
                "hyprctl keyword decoration:blur:enabled "      + blur     + "\n" +
                "hyprctl keyword animations:enabled "           + anim     + "\n" +
                "hyprctl keyword decoration:rounding "          + rounding + "\n" +
                "hyprctl keyword decoration:drop_shadow "       + blur     + "\n"
            ]
            running = true
        }
    }

    Process {
        id: powerProfileReader
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo balanced"]
        stdout: SplitParser {
            onRead: {
                let p = data.trim()
                if (p === "performance" || p === "power-saver" || p === "balanced") popup.powerProfile = p
            }
        }
    }

    Process {
        id: powerProfileSetter
        function set(profile) {
            command = ["bash", "-c", "powerprofilesctl set " + profile + " 2>/dev/null || true"]
            running = true
        }
    }

    Process {
        id: tuxedoDetector
        running: true
        command: ["bash", "-c", "command -v tuxedo-control-center &>/dev/null && echo yes || echo no"]
        stdout: SplitParser {
            onRead: { popup.tuxedoInstalled = data.trim() === "yes" }
        }
    }

    property string _metricsBuf: ""
    Process {
        id: metricsCollector
        command: ["bash", "-c",
            "set +e\n" +
            "for f in /sys/class/hwmon/hwmon*/temp1_input; do\n" +
            "  name=$(cat \"$(dirname \"$f\")/name\" 2>/dev/null)\n" +
            "  case \"$name\" in\n" +
            "    coretemp|k10temp|zenpower|cpu_thermal|acpitz)\n" +
            "      t=$(cat \"$f\" 2>/dev/null); [ -n \"$t\" ] && echo \"cputemp=$((t/1000))\" && break ;;\n" +
            "  esac\n" +
            "done\n" +
            "freq=$(awk '/cpu MHz/ {sum+=$4; n++} END {if (n>0) printf \"%.2f\", sum/n/1000}' /proc/cpuinfo)\n" +
            "[ -n \"$freq\" ] && echo \"cpufreq=$freq\"\n" +
            "cpuusage=$(awk 'BEGIN{" +
                "while((getline < \"/proc/stat\")>0){split($0,a);if(a[1]==\"cpu\"){t1=a[2]+a[3]+a[4]+a[5]+a[6]+a[7]+a[8];i1=a[5];break}};close(\"/proc/stat\");"
                +"system(\"sleep 0.2\");"
                +"while((getline < \"/proc/stat\")>0){split($0,a);if(a[1]==\"cpu\"){t2=a[2]+a[3]+a[4]+a[5]+a[6]+a[7]+a[8];i2=a[5];break}};"
                +"dt=t2-t1;print dt>0?(dt-(i2-i1))/dt*100:0}')\n" +
            "echo \"cpuusage=$cpuusage\"\n" +
            "if command -v nvidia-smi &>/dev/null; then\n" +
            "  out=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)\n" +
            "  if [ -n \"$out\" ]; then\n" +
            "    echo \"gpuvendor=nvidia\"\n" +
            "    echo \"gputemp=$(echo $out | cut -d, -f1 | tr -d ' ')\"\n" +
            "    echo \"gpuusage=$(echo $out | cut -d, -f2 | tr -d ' ')\"\n" +
            "  fi\n" +
            "fi\n" +
            "for d in /sys/class/drm/card*/device; do\n" +
            "  [ -f \"$d/gpu_busy_percent\" ] && {\n" +
            "    busy=$(cat \"$d/gpu_busy_percent\" 2>/dev/null)\n" +
            "    [ -n \"$busy\" ] && echo \"gpuvendor=amd\" && echo \"gpuusage=$busy\"\n" +
            "    for h in \"$d/hwmon/\"hwmon*; do\n" +
            "      t=$(cat \"$h/temp1_input\" 2>/dev/null)\n" +
            "      [ -n \"$t\" ] && echo \"gputemp=$((t/1000))\" && break\n" +
            "    done\n" +
            "    break\n" +
            "  }\n" +
            "done\n" +
            "for f in /sys/class/hwmon/hwmon*/temp1_input; do\n" +
            "  name=$(cat \"$(dirname \"$f\")/name\" 2>/dev/null)\n" +
            "  if [ \"$name\" = \"i915\" ] || [ \"$name\" = \"xe\" ]; then\n" +
            "    t=$(cat \"$f\" 2>/dev/null); [ -n \"$t\" ] && echo \"gpuvendor=intel\" && echo \"gputemp=$((t/1000))\" && break\n" +
            "  fi\n" +
            "done\n" +
            "awk '/MemTotal:/ {tot=$2} /MemAvailable:/ {avail=$2} END {\n" +
            "  used = tot - avail\n" +
            "  printf \"memused=%.2f\\n\", used/1024/1024\n" +
            "  printf \"memtotal=%.2f\\n\", tot/1024/1024\n" +
            "}' /proc/meminfo\n" +
            "snap1=$(awk '/:/ && !/lo:/ {gsub(\":\",\"\"); rx+=$2; tx+=$10} END {printf \"%d %d\", rx, tx}' /proc/net/dev)\n" +
            "sleep 0.3\n" +
            "snap2=$(awk '/:/ && !/lo:/ {gsub(\":\",\"\"); rx+=$2; tx+=$10} END {printf \"%d %d\", rx, tx}' /proc/net/dev)\n" +
            "rx1=${snap1% *}; tx1=${snap1#* }\n" +
            "rx2=${snap2% *}; tx2=${snap2#* }\n" +
            "echo \"netrx=$(( (rx2 - rx1) / 1024 ))\"\n" +
            "echo \"nettx=$(( (tx2 - tx1) / 1024 ))\"\n" +
            "ut=$(awk '{print int($1)}' /proc/uptime)\n" +
            "d=$((ut/86400)); h=$(( (ut%86400)/3600 )); m=$(( (ut%3600)/60 ))\n" +
            "if [ $d -gt 0 ]; then echo \"uptime=${d}d ${h}h ${m}m\"\n" +
            "elif [ $h -gt 0 ]; then echo \"uptime=${h}h ${m}m\"\n" +
            "else echo \"uptime=${m}m\"; fi\n" +
            "for b in /sys/class/power_supply/BAT*; do\n" +
            "  [ -d \"$b\" ] || continue\n" +
            "  cap=$(cat \"$b/capacity\" 2>/dev/null)\n" +
            "  st=$(cat \"$b/status\" 2>/dev/null)\n" +
            "  [ -n \"$cap\" ] && echo \"battery=$cap\" && [ \"$st\" = \"Charging\" ] && echo \"batcharging=1\" || echo \"batcharging=0\"\n" +
            "  break\n" +
            "done\n"
        ]
        stdout: SplitParser {
            onRead: { popup._metricsBuf += data + "\n" }
        }
        onRunningChanged: {
            if (!running) {
                let lines = popup._metricsBuf.trim().split("\n")
                popup._metricsBuf = ""
                for (let l of lines) {
                    let i = l.indexOf("=")
                    if (i < 1) continue
                    let k = l.substring(0, i)
                    let v = l.substring(i + 1).trim()
                    switch (k) {
                        case "cpuusage":    popup.localCpuUsage = (parseFloat(v) || 0) / 100; break
                        case "cputemp":     popup.cpuTemp     = parseFloat(v) || 0; break
                        case "cpufreq":     popup.cpuFreq     = parseFloat(v) || 0; break
                        case "gpuvendor":   popup.gpuVendor   = v; break
                        case "gputemp":     popup.gpuTemp     = parseFloat(v) || 0; break
                        case "gpuusage":    popup.gpuUsage    = (parseFloat(v) || 0) / 100; break
                        case "memused":     popup.memUsedGB   = parseFloat(v) || 0; break
                        case "memtotal":    popup.memTotalGB  = parseFloat(v) || 0; break
                        case "netrx":       popup.netRxKBs    = parseFloat(v) || 0; break
                        case "nettx":       popup.netTxKBs    = parseFloat(v) || 0; break
                        case "uptime":      popup.uptimeStr   = v; break
                        case "battery":     popup.batteryPct  = parseInt(v) || -1; break
                        case "batcharging": popup.batteryCharging = (v === "1"); break
                    }
                }
                if (popup.cpuTemp > 0)  popup.cpuTempHistory   = popup.pushHist(popup.cpuTempHistory, popup.cpuTemp, 30)
                if (popup.gpuTemp > 0)  popup.gpuTempHistory   = popup.pushHist(popup.gpuTempHistory, popup.gpuTemp, 30)
                let cpuForHistory = popup.localCpuUsage > 0 ? popup.localCpuUsage : sysInfo.cpuUsage
                popup.cpuUsageHistory = popup.pushHist(popup.cpuUsageHistory, cpuForHistory, 30)
                if (popup.localCpuUsage > 0) sysInfo.cpuUsage = popup.localCpuUsage
                popup.netRxHistory    = popup.pushHist(popup.netRxHistory, popup.netRxKBs, 30)
                popup.netTxHistory    = popup.pushHist(popup.netTxHistory, popup.netTxKBs, 30)
                let peak = 100
                for (let v of popup.netRxHistory) if (v > peak) peak = v
                for (let v of popup.netTxHistory) if (v > peak) peak = v
                popup.netMaxSeen = peak * 1.25
            }
        }
    }

    Timer {
        id: metricsTimer
        interval: 2500; repeat: true
        running: popup.active && popup.currentTab === "Performance"
        onTriggered: { if (!metricsCollector.running) metricsCollector.running = true }
        triggeredOnStart: true
    }

    Timer { id: repollTimer; interval: 800; repeat: false; onTriggered: { wifiScanner.running=true; btScanner.running=true } }

    onActiveChanged: {
        if (active) {
            isAnimating = true // Start entrance animation
            if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
            if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
            if (currentTab === "Performance") { powerProfileReader.running=true }
        }
    }
    onCurrentTabChanged: {
        if (!active) return
        if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
        if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
        if (currentTab === "Performance") { powerProfileReader.running=true }
    }

    function signalIcon(sig) {
        if (sig >= 75) return "󰤨"
        if (sig >= 50) return "󰤥"
        if (sig >= 25) return "󰤢"
        return "󰤟"
    }

    function fmtSpeed(kb) {
        if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB/s"
        return Math.round(kb) + " KB/s"
    }

    function tempColor(t) {
        if (t >= 85) return "#e06c75"
        if (t >= 70) return "#e5c07b"
        return Theme.primary
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  CONTAINER — wider on Performance tab
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: container
        width:  popup.currentTab === "Performance" ? 700 : 420
        height: popup.currentTab === "Performance" ? 720 : 580
        Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

        anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 15
        radius: 30; color: "transparent"

        // Wayland-Safe Entrance/Exit Animations
        transformOrigin: Item.TopRight
        opacity: popup.active ? 1.0 : 0.0
        scale: popup.active ? 1.0 : 0.90

        Behavior on opacity { 
            NumberAnimation { 
                duration: 250; easing.type: Easing.OutCubic 
                onRunningChanged: if (!running && !popup.active) popup.isAnimating = false 
            } 
        }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

        Rectangle {
            anchors.fill: parent; color: Theme.background; border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8);
            border.width: 2; radius: 30; opacity: 0.8; 
        }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 14

            // ── Tab bar ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 36; radius: 12; color: Theme.background
                Row {
                    anchors.fill: parent; anchors.margins: 4; spacing: 4
                    Repeater {
                        model: ["Network", "Bluetooth", "Performance"]
                        Rectangle {
                            width: (parent.width - 8) / 3; height: parent.height; radius: 9
                            color: popup.currentTab === modelData ? Theme.primary : "transparent"
                            
                            // Tactile Tab Hover/Press
                            scale: tabMouse.pressed ? 0.95 : (tabMouse.containsMouse && popup.currentTab !== modelData ? 1.03 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData === "Network"   ? "󰤨  Network"
                                    : modelData === "Bluetooth" ? "󰂯  Bluetooth"
                                    : "󰻠  System"
                                color: popup.currentTab === modelData ? Theme.background : Theme.primary
                                font.bold: true; font.pixelSize: 14
                                opacity: popup.currentTab === modelData ? 1.0 : (tabMouse.containsMouse ? 0.9 : 0.6)
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { 
                                id: tabMouse
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: popup.currentTab = modelData 
                            }
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  NETWORK TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Network"
                Layout.fillWidth: true; spacing: 10

                Rectangle {
                    Layout.fillWidth: true; height: 48; radius: 14; color: Theme.background
                    visible: sysInfo.connType === "ethernet"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                        Text { text: "󰈀"; color: Theme.primary; font.pixelSize: 20 }
                        Column {
                            spacing: 1
                            Text { text: "Ethernet"; color: Theme.primary; font.pixelSize: 12; font.weight: Font.Bold }
                            Text { text: "Wired connection active"; color: Theme.primary; opacity: 0.5; font.pixelSize: 10 }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle { width: 8; height: 8; radius: 4; color: "#a6e3a1" }
                        Text { text: "Connected"; color: Theme.primary; opacity: 0.6; font.pixelSize: 10 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰤨  Wi-Fi"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    
                    // Wi-Fi Refresh Button
                    Rectangle {
                        width: 28; height: 28; radius: 8
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        scale: wifiRefMouse.pressed ? 0.9 : (wifiRefMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                        Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 14; opacity: popup.wifiScanning ? 0.3 : 0.8 }
                        MouseArea {
                            id: wifiRefMouse
                            anchors.fill: parent; hoverEnabled: true; enabled: !popup.wifiScanning
                            onClicked: { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
                        }
                    }
                    
                    // Wi-Fi Toggle Switch
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.wifiRadio ? Theme.primary : "transparent"
                        border.color: Theme.primary; border.width: 2
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: sysInfo.wifiRadio ? parent.width - width - 3 : 3; y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.wifiRadio ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { localExec.run(["bash", "-c", sysInfo.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"]); repollTimer.restart() }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 300; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04); clip: true

                    Text {
                        anchors.centerIn: parent
                        text: popup.wifiScanning ? "Scanning…" : (popup.wifiNetworks.length === 0 ? "No networks found" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.wifiScanning || popup.wifiNetworks.length === 0
                    }

                    ListView {
                        anchors.fill: parent; anchors.margins: 6
                        model: popup.wifiNetworks; spacing: 4; clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: (popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid) ? 100 : 52
                            radius: 10
                            color: modelData.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }

                            RowLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10; height: 32; spacing: 10

                                Text { text: signalIcon(modelData.signal); color: Theme.primary; opacity: modelData.active ? 1.0 : 0.6; font.pixelSize: 16 }
                                Column {
                                    spacing: 1; Layout.fillWidth: true
                                    Text { text: modelData.ssid; color: Theme.primary; font.pixelSize: 12; font.weight: modelData.active ? Font.Bold : Font.Normal; elide: Text.ElideRight; width: parent.width }
                                    Text {
                                        text: modelData.active ? "Connected" : modelData.saved ? "󰄬  Saved" : (modelData.security && modelData.security !== "--") ? "󰌆  " + modelData.security : "Open"
                                        color: Theme.primary; opacity: modelData.active ? 0.8 : 0.4; font.pixelSize: 9
                                    }
                                }
                                Row {
                                    spacing: 6
                                    
                                    // Connect/Disconnect Button
                                    Rectangle {
                                        width: 68; height: 26; radius: 8
                                        color: modelData.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Theme.primary
                                        visible: popup.wifiConnecting !== modelData.ssid
                                        
                                        scale: wifiActMouse.pressed ? 0.92 : (wifiActMouse.containsMouse ? 1.05 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                        Text { anchors.centerIn: parent; text: modelData.active ? "Disconnect" : "Connect"; color: modelData.active ? Theme.primary : Theme.background; font.pixelSize: 9; font.weight: Font.Bold }
                                        MouseArea {
                                            id: wifiActMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                if (modelData.active) {
                                                    wifiDisconnector.command = ["nmcli","dev","disconnect","wlan0"]; wifiDisconnector.running = true
                                                } else if (modelData.saved) {
                                                    popup.wifiConnecting = modelData.ssid; wifiConnector.command = ["nmcli","con","up",modelData.ssid]; wifiConnector.running = true
                                                } else if (!modelData.security || modelData.security === "--") {
                                                    popup.wifiConnecting = modelData.ssid; wifiConnector.command = ["nmcli","dev","wifi","connect",modelData.ssid]; wifiConnector.running = true
                                                } else {
                                                    popup.wifiPasswordTarget = modelData.ssid; popup.wifiPassword = ""; popup.showPasswordFor = true
                                                }
                                            }
                                        }
                                    }
                                    Text { visible: popup.wifiConnecting === modelData.ssid; text: "…"; color: Theme.primary; opacity: 0.5; font.pixelSize: 12 }
                                    
                                    // Forget Button
                                    Rectangle {
                                        width: 26; height: 26; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                        scale: wifiForgetMouse.pressed ? 0.9 : (wifiForgetMouse.containsMouse ? 1.1 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                        Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                        MouseArea { 
                                            id: wifiForgetMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            onClicked: { wifiForget.command=["bash","-c","nmcli connection delete \""+modelData.ssid+"\" 2>/dev/null||true"]; wifiForget.running=true } 
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.topMargin: 54; anchors.margins: 10; spacing: 6
                                visible: popup.showPasswordFor && popup.wifiPasswordTarget === modelData.ssid
                                Rectangle {
                                    Layout.fillWidth: true; height: 28; radius: 8
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                        Text { text: "󰌆"; color: Theme.primary; opacity: 0.5; font.pixelSize: 11 }
                                        Item {
                                            Layout.fillWidth: true; height: 28
                                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Password…"; color: Theme.primary; opacity: 0.35; font.pixelSize: 11; visible: pwInput.text.length === 0 }
                                            TextInput {
                                                id: pwInput; anchors.fill: parent; color: Theme.primary; font.pixelSize: 11
                                                echoMode: TextInput.Password; verticalAlignment: TextInput.AlignVCenter
                                                onTextChanged: popup.wifiPassword = text
                                                onAccepted: { popup.wifiConnecting=modelData.ssid; popup.showPasswordFor=false; wifiConnector.command=["nmcli","dev","wifi","connect",modelData.ssid,"password",popup.wifiPassword]; wifiConnector.running=true }
                                            }
                                        }
                                        // Join Button
                                        Rectangle {
                                            width: 50; height: 22; radius: 6; color: Theme.primary
                                            scale: joinMouse.pressed ? 0.95 : (joinMouse.containsMouse ? 1.05 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                            Text { anchors.centerIn: parent; text: "Join"; color: Theme.background; font.pixelSize: 10; font.weight: Font.Bold }
                                            MouseArea { 
                                                id: joinMouse
                                                anchors.fill: parent; hoverEnabled: true
                                                onClicked: { popup.wifiConnecting=modelData.ssid; popup.showPasswordFor=false; wifiConnector.command=["nmcli","dev","wifi","connect",modelData.ssid,"password",popup.wifiPassword]; wifiConnector.running=true } 
                                            }
                                        }
                                        Text { 
                                            text: "󰅖"; color: Theme.primary; opacity: closePwMouse.containsMouse ? 0.8 : 0.4; font.pixelSize: 12
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            MouseArea { id: closePwMouse; anchors.fill: parent; hoverEnabled: true; onClicked: popup.showPasswordFor=false } 
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Advanced Network Settings Button
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1; color: "transparent"
                    
                    scale: advNetMouse.pressed ? 0.98 : (advNetMouse.containsMouse ? 1.02 : 1.0)
                    opacity: advNetMouse.containsMouse ? 1.0 : 0.7
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text { anchors.centerIn: parent; text: "󰖟  Advanced Network Settings"; color: Theme.primary; font.pixelSize: 11 }
                    MouseArea { 
                        id: advNetMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { localExec.run(["kitty","--class","floating","nmtui"]); popup.active=false } 
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  BLUETOOTH TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Bluetooth"
                Layout.fillWidth: true; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    
                    // BT Refresh Button
                    Rectangle {
                        width: 28; height: 28; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                        scale: btRefMouse.pressed ? 0.9 : (btRefMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                        Text { anchors.centerIn: parent; text: "󰑓"; color: Theme.primary; font.pixelSize: 14; opacity: popup.btScanning ? 0.3 : 0.8 }
                        MouseArea { 
                            id: btRefMouse
                            anchors.fill: parent; hoverEnabled: true; enabled: !popup.btScanning
                            onClicked: { popup._btBuf=""; popup.btScanning=true; btScanner.running=true } 
                        }
                    }
                    
                    // BT Toggle Switch
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: sysInfo.bluetooth ? Theme.primary : "transparent"; border.color: Theme.primary; border.width: 2
                        Behavior on color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            x: sysInfo.bluetooth ? parent.width - width - 3 : 3; y: 3; width: 18; height: 18; radius: 9
                            color: sysInfo.bluetooth ? Theme.background : Theme.primary
                            Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { localExec.run(["bash","-c",sysInfo.bluetooth?"bluetoothctl power off":"bluetoothctl power on"]); repollTimer.restart() } }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 360; radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.04); clip: true
                    Text {
                        anchors.centerIn: parent
                        text: popup.btScanning ? "Scanning…" : (!sysInfo.bluetooth ? "Bluetooth is off" : popup.btDevices.length===0 ? "No paired devices" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.btScanning || !sysInfo.bluetooth || popup.btDevices.length===0
                    }
                    ListView {
                        anchors.fill: parent; anchors.margins: 6; model: popup.btDevices; spacing: 4; clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            width: ListView.view.width; height: 56; radius: 10
                            color: modelData.connected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                Text { text: "󰂯"; color: Theme.primary; font.pixelSize: 20; opacity: modelData.connected ? 1.0 : 0.4 }
                                Column {
                                    spacing: 2; Layout.fillWidth: true
                                    Text { text: modelData.name||modelData.mac; color: Theme.primary; font.pixelSize: 12; font.weight: modelData.connected?Font.Bold:Font.Normal; elide: Text.ElideRight; width: parent.width }
                                    Text { text: modelData.connected?"Connected":(modelData.paired?"Paired":""); color: Theme.primary; opacity: 0.45; font.pixelSize: 10 }
                                }
                                
                                // BT Connect/Disconnect
                                Rectangle {
                                    width: 76; height: 26; radius: 8
                                    color: modelData.connected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Theme.primary
                                    scale: btActMouse.pressed ? 0.92 : (btActMouse.containsMouse ? 1.05 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                    Text { anchors.centerIn: parent; text: modelData.connected?"Disconnect":"Connect"; color: modelData.connected?Theme.primary:Theme.background; font.pixelSize: 9; font.weight: Font.Bold }
                                    MouseArea { 
                                        id: btActMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: { btAction.command=["bash","-c",(modelData.connected?"bluetoothctl disconnect ":"bluetoothctl connect ")+modelData.mac]; btAction.running=true } 
                                    }
                                }
                                
                                // BT Forget
                                Rectangle {
                                    width: 26; height: 26; radius: 8; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    scale: btForgetMouse.pressed ? 0.9 : (btForgetMouse.containsMouse ? 1.1 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                    Text { anchors.centerIn: parent; text: "󰆴"; color: Theme.primary; font.pixelSize: 12; opacity: 0.6 }
                                    MouseArea { 
                                        id: btForgetMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: { btAction.command=["bash","-c","bluetoothctl remove "+modelData.mac]; btAction.running=true } 
                                    }
                                }
                            }
                        }
                    }
                }

                // BT Manager Button
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3); border.width: 1; color: "transparent"
                    
                    scale: btManMouse.pressed ? 0.98 : (btManMouse.containsMouse ? 1.02 : 1.0)
                    opacity: btManMouse.containsMouse ? 1.0 : 0.7
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text { anchors.centerIn: parent; text: "󰂱  Bluetooth Manager"; color: Theme.primary; font.pixelSize: 11 }
                    MouseArea { 
                        id: btManMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { localExec.run(["blueman-manager"]); popup.active=false } 
                    }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  PERFORMANCE TAB — masonry layout with charts
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Performance"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // ── Header strip with circle gauges (CPU/Mem/Disk) ────────
                RowLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 12

                    component CircleGauge: Item {
                        id: gauge
                        property real value: 0.0
                        property string label: ""
                        property string icon: ""
                        property color trackColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        property color fillColor: value > 0.85 ? "#e06c75" : Theme.primary
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        Layout.preferredWidth: 100

                        Canvas {
                            id: gaugeCanvas
                            renderTarget: Canvas.FramebufferObject
                            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                            width: 80; height: 80
                            property real animValue: 0.0
                            Behavior on animValue { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }
                            onAnimValueChanged: requestPaint()
                            Component.onCompleted: animValue = gauge.value
                            Connections { target: gauge; function onValueChanged() { gaugeCanvas.animValue = gauge.value } }
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset()
                                var cx=width/2, cy=height/2, r=(width-12)/2
                                var s=Math.PI*0.75, sw=Math.PI*1.5
                                ctx.beginPath(); ctx.arc(cx,cy,r,s,s+sw,false); ctx.strokeStyle=gauge.trackColor; ctx.lineWidth=7; ctx.lineCap="round"; ctx.stroke()
                                if (animValue>0) { ctx.beginPath(); ctx.arc(cx,cy,r,s,s+sw*animValue,false); ctx.strokeStyle=gauge.fillColor; ctx.lineWidth=7; ctx.lineCap="round"; ctx.stroke() }
                                if (animValue>0.02) { var ta=s+sw*animValue; ctx.beginPath(); ctx.arc(cx+r*Math.cos(ta),cy+r*Math.sin(ta),3.5,0,Math.PI*2); ctx.fillStyle=gauge.fillColor; ctx.fill() }
                            }
                            Column {
                                anchors.centerIn: parent; spacing: 0
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: gauge.icon; color: Theme.primary; font.pixelSize: 14; opacity: 0.7 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(gauge.value*100)+"%"; color: gauge.fillColor; font.pixelSize: 13; font.weight: Font.Black }
                            }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; text: gauge.label; color: Theme.primary; opacity: 0.55; font.pixelSize: 10; font.weight: Font.Medium }
                    }

                    CircleGauge { label: "CPU";    icon: "󰻠"; value: sysInfo.cpuUsage }
                    CircleGauge { label: "Memory"; icon: "󰍛"; value: sysInfo.ramUsage }
                    CircleGauge { label: "Disk";   icon: "󰋊"; value: sysInfo.diskUsage }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                // ── REUSABLE COMPONENTS ───────────────────────────────────

                // Sparkline chart card (line + area fill)
                component SparkCard: Rectangle {
                    id: sparkCardRoot
                    property string cardIcon: ""
                    property string cardLabel: ""
                    property string cardValue: ""
                    property string cardSub: ""
                    property color  cardColor: Theme.primary
                    property var    history: []
                    property real   yMin: 0
                    property real   yMax: 100
                    property bool   filled: true

                    onHistoryChanged: spark.requestPaint()
                    onYMaxChanged:    spark.requestPaint()

                    width: parent ? parent.width : 0
                    height: 110
                    radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    border.width: 1

                    RowLayout {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.topMargin: 10
                        spacing: 8

                        Rectangle {
                            width: 28; height: 28; radius: 8
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                            Text { anchors.centerIn: parent; text: cardIcon; color: cardColor; font.pixelSize: 14 }
                        }
                        ColumnLayout {
                            spacing: -1; Layout.fillWidth: true
                            Text { text: cardLabel; color: Theme.primary; opacity: 0.5; font.pixelSize: 9; font.bold: true }
                            Text { text: cardValue; color: cardColor; font.pixelSize: 16; font.weight: Font.Black }
                        }
                        Text { text: cardSub; color: Theme.primary; opacity: 0.4; font.pixelSize: 9 }
                    }

                    Canvas {
                        id: spark
                        renderTarget: Canvas.FramebufferObject
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.bottomMargin: 8
                        height: 42
                        antialiasing: true

                        onWidthChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            var hist = parent.history
                            if (!hist || hist.length < 2) return
                            var w = width, h = height
                            var range = parent.yMax - parent.yMin
                            if (range <= 0) range = 1

                            var step = w / Math.max(1, hist.length - 1)
                            ctx.beginPath()
                            for (var i = 0; i < hist.length; i++) {
                                var x = i * step
                                var nv = (hist[i] - parent.yMin) / range
                                if (nv < 0) nv = 0; if (nv > 1) nv = 1
                                var y = h - nv * (h - 4) - 2
                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                            }

                            if (parent.filled) {
                                ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
                                var grad = ctx.createLinearGradient(0, 0, 0, h)
                                grad.addColorStop(0, Qt.rgba(parent.cardColor.r, parent.cardColor.g, parent.cardColor.b, 0.35))
                                grad.addColorStop(1, Qt.rgba(parent.cardColor.r, parent.cardColor.g, parent.cardColor.b, 0.02))
                                ctx.fillStyle = grad
                                ctx.fill()
                            }

                            ctx.beginPath()
                            for (var j = 0; j < hist.length; j++) {
                                var x2 = j * step
                                var nv2 = (hist[j] - parent.yMin) / range
                                if (nv2 < 0) nv2 = 0; if (nv2 > 1) nv2 = 1
                                var y2 = h - nv2 * (h - 4) - 2
                                if (j === 0) ctx.moveTo(x2, y2); else ctx.lineTo(x2, y2)
                            }
                            ctx.strokeStyle = parent.cardColor
                            ctx.lineWidth = 1.8
                            ctx.lineJoin = "round"; ctx.lineCap = "round"
                            ctx.stroke()

                            if (hist.length > 0) {
                                var lx = (hist.length - 1) * step
                                var lv = (hist[hist.length - 1] - parent.yMin) / range
                                if (lv < 0) lv = 0; if (lv > 1) lv = 1
                                var ly = h - lv * (h - 4) - 2
                                ctx.beginPath(); ctx.arc(lx, ly, 2.5, 0, Math.PI * 2)
                                ctx.fillStyle = parent.cardColor; ctx.fill()
                            }
                        }
                    }
                }

                // Compact value-only card (no chart)
                component CompactCard: Rectangle {
                    property string cardIcon: ""
                    property string cardLabel: ""
                    property string cardValue: ""
                    property string cardSub: ""
                    property color  cardColor: Theme.primary

                    width: parent ? parent.width : 0
                    height: 56
                    radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                        Rectangle {
                            width: 32; height: 32; radius: 9
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                            Text { anchors.centerIn: parent; text: cardIcon; color: cardColor; font.pixelSize: 16 }
                        }
                        ColumnLayout {
                            spacing: -1; Layout.fillWidth: true
                            Text { text: cardLabel; color: Theme.primary; opacity: 0.5; font.pixelSize: 9; font.bold: true }
                            Text { text: cardValue; color: cardColor; font.pixelSize: 14; font.weight: Font.Black }
                        }
                        Text { text: cardSub; color: Theme.primary; opacity: 0.45; font.pixelSize: 9 }
                    }
                }

                // Dual-line chart card (rx + tx)
                component DualSparkCard: Rectangle {
                    id: dualCardRoot
                    property string cardIcon: ""
                    property string cardLabel: ""
                    property var    historyA: []
                    property var    historyB: []
                    property string labelA: "RX"
                    property string labelB: "TX"
                    property color  colorA: Theme.primary
                    property color  colorB: Theme.accent
                    property string valueA: ""
                    property string valueB: ""
                    property real   yMax: 100

                    onHistoryAChanged: dualSpark.requestPaint()
                    onHistoryBChanged: dualSpark.requestPaint()
                    onYMaxChanged:     dualSpark.requestPaint()

                    width: parent ? parent.width : 0
                    height: 130
                    radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    border.width: 1

                    ColumnLayout {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.topMargin: 10
                        spacing: 4

                        // Header
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Rectangle {
                                width: 28; height: 28; radius: 8
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                Text { anchors.centerIn: parent; text: cardIcon; color: Theme.primary; font.pixelSize: 14 }
                            }
                            Text { text: cardLabel; color: Theme.primary; opacity: 0.6; font.pixelSize: 10; font.bold: true; Layout.alignment: Qt.AlignVCenter }
                            Item { Layout.fillWidth: true }
                        }

                        // Two-row legend with values
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            RowLayout {
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 4; color: colorA }
                                Text { text: labelA + " " + valueA; color: Theme.primary; font.pixelSize: 11; font.bold: true }
                            }
                            RowLayout {
                                spacing: 5
                                Rectangle { width: 8; height: 8; radius: 4; color: colorB }
                                Text { text: labelB + " " + valueB; color: Theme.primary; font.pixelSize: 11; font.bold: true; opacity: 0.85 }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    Canvas {
                        id: dualSpark
                        renderTarget: Canvas.FramebufferObject
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.bottomMargin: 8
                        height: 50
                        antialiasing: true

                        onWidthChanged: requestPaint()

                        function drawSeries(ctx, hist, w, h, color, fill) {
                            if (!hist || hist.length < 2) return
                            var range = parent.yMax > 0 ? parent.yMax : 1
                            var step = w / Math.max(1, hist.length - 1)
                            ctx.beginPath()
                            for (var i = 0; i < hist.length; i++) {
                                var x = i * step
                                var nv = hist[i] / range
                                if (nv < 0) nv = 0; if (nv > 1) nv = 1
                                var y = h - nv * (h - 4) - 2
                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                            }
                            if (fill) {
                                ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
                                var grad = ctx.createLinearGradient(0, 0, 0, h)
                                grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, 0.30))
                                grad.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0.02))
                                ctx.fillStyle = grad; ctx.fill()
                            }
                            ctx.beginPath()
                            for (var j = 0; j < hist.length; j++) {
                                var x2 = j * step
                                var nv2 = hist[j] / range
                                if (nv2 < 0) nv2 = 0; if (nv2 > 1) nv2 = 1
                                var y2 = h - nv2 * (h - 4) - 2
                                if (j === 0) ctx.moveTo(x2, y2); else ctx.lineTo(x2, y2)
                            }
                            ctx.strokeStyle = color
                            ctx.lineWidth = 1.6; ctx.lineJoin = "round"; ctx.lineCap = "round"
                            ctx.stroke()
                        }

                        onPaint: {
                            var ctx = getContext("2d"); ctx.reset()
                            drawSeries(ctx, parent.historyA, width, height, parent.colorA, true)
                            drawSeries(ctx, parent.historyB, width, height, parent.colorB, false)
                        }
                    }
                }

                // ── MASONRY (3 columns) ──────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Row {
                        anchors.fill: parent
                        spacing: 10

                        // ─ Column 1 — CPU stats (chart + compact) ─
                        Column {
                            width: (parent.width - 20) / 3
                            spacing: 10

                            // CPU temp chart
                            SparkCard {
                                cardIcon:  "󰈐"
                                cardLabel: "CPU TEMP"
                                cardValue: popup.cpuTemp > 0 ? popup.cpuTemp.toFixed(0) + "°C" : "—"
                                cardColor: popup.tempColor(popup.cpuTemp)
                                history:   popup.cpuTempHistory
                                yMin: 30; yMax: 95
                            }
                            // CPU clock (compact)
                            CompactCard {
                                cardIcon:  "󰓅"
                                cardLabel: "CPU CLOCK"
                                cardValue: popup.cpuFreq > 0 ? popup.cpuFreq.toFixed(2) + " GHz" : "—"
                            }
                            // CPU usage chart
                            SparkCard {
                                cardIcon:  "󰻠"
                                cardLabel: "CPU LOAD"
                                cardValue: Math.round(sysInfo.cpuUsage * 100) + "%"
                                cardColor: sysInfo.cpuUsage > 0.85 ? "#e06c75" : Theme.primary
                                history:   popup.cpuUsageHistory
                                yMin: 0; yMax: 1
                            }
                        }

                        // ─ Column 2 — GPU stats ─
                        Column {
                            width: (parent.width - 20) / 3
                            spacing: 10

                            SparkCard {
                                cardIcon:  "󰍹"
                                cardLabel: popup.gpuVendor !== "" ? "GPU TEMP · " + popup.gpuVendor.toUpperCase() : "GPU TEMP"
                                cardValue: popup.gpuTemp > 0 ? popup.gpuTemp.toFixed(0) + "°C" : "—"
                                cardColor: popup.tempColor(popup.gpuTemp)
                                history:   popup.gpuTempHistory
                                yMin: 30; yMax: 95
                            }
                            CompactCard {
                                cardIcon:  "󰢮"
                                cardLabel: "GPU USAGE"
                                cardValue: popup.gpuVendor === "nvidia" || popup.gpuVendor === "amd"
                                    ? Math.round(popup.gpuUsage * 100) + "%"
                                    : (popup.gpuVendor === "intel" ? "n/a" : "—")
                            }
                            CompactCard {
                                cardIcon:  "󰍛"
                                cardLabel: "MEMORY"
                                cardValue: popup.memUsedGB > 0 ? popup.memUsedGB.toFixed(1) + " GB" : "—"
                                cardSub:   popup.memTotalGB > 0 ? "of " + popup.memTotalGB.toFixed(1) : ""
                            }
                        }

                        // ─ Column 3 — Network + system ─
                        Column {
                            width: (parent.width - 20) / 3
                            spacing: 10

                            // Network combined chart
                            DualSparkCard {
                                cardIcon:  "󰛳"
                                cardLabel: "NETWORK"
                                historyA:  popup.netRxHistory
                                historyB:  popup.netTxHistory
                                labelA:    "↓"
                                labelB:    "↑"
                                colorA:    Theme.primary
                                colorB:    "#e5c07b"
                                valueA:    popup.fmtSpeed(popup.netRxKBs)
                                valueB:    popup.fmtSpeed(popup.netTxKBs)
                                yMax:      popup.netMaxSeen
                            }
                            CompactCard {
                                cardIcon:  "󱎫"
                                cardLabel: "UPTIME"
                                cardValue: popup.uptimeStr || "—"
                            }
                            CompactCard {
                                cardIcon:  popup.batteryCharging ? "󰂄" : "󰁹"
                                cardLabel: "BATTERY"
                                cardValue: popup.batteryPct >= 0 ? popup.batteryPct + "%" : "—"
                                cardSub:   popup.batteryCharging ? "Charging" : ""
                                cardColor: popup.batteryPct >= 0 && popup.batteryPct <= 20 ? "#e06c75" : Theme.primary
                                visible:   popup.batteryPct >= 0
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                // ── Game Mode + Power profile row ─────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 10

                    // Game Mode
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        height: 56; radius: 14
                        color: popup.gamemodeActive
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                            : Theme.background
                        border.color: popup.gamemodeActive ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        border.width: popup.gamemodeActive ? 1.5 : 1

                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                            Text { text: "󰊴"; color: Theme.primary; font.pixelSize: 20; opacity: popup.gamemodeActive ? 1.0 : 0.5; Layout.alignment: Qt.AlignVCenter }
                            ColumnLayout {
                                spacing: 1; Layout.fillWidth: true
                                Text { text: "Game Mode"; color: Theme.primary; font.pixelSize: 13; font.bold: true }
                                Text {
                                    text: popup.gamemodeActive ? "Visual effects off" : "Visual effects on"
                                    color: Theme.primary; opacity: 0.45; font.pixelSize: 10
                                }
                            }
                            
                            // Game Mode Toggle Switch
                            Rectangle {
                                width: 44; height: 24; radius: 12
                                color: popup.gamemodeActive ? Theme.primary : "transparent"
                                border.color: Theme.primary; border.width: 2
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 200 } }

                                Rectangle {
                                    x: popup.gamemodeActive ? parent.width - width - 3 : 3; y: 3
                                    width: 18; height: 18; radius: 9
                                    color: popup.gamemodeActive ? Theme.background : Theme.primary
                                    Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        popup.gamemodeActive = !popup.gamemodeActive
                                        gamemodeExec.apply(popup.gamemodeActive)
                                    }
                                }
                            }
                        }
                    }

                    // Power profile pills (or tuxedo button)
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        height: 56; radius: 14
                        color: Theme.background
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 6
                            visible: popup.tuxedoInstalled
                            Text { text: "󱐋"; color: Theme.primary; font.pixelSize: 18; opacity: 0.7; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 6 }
                            ColumnLayout {
                                spacing: 0; Layout.fillWidth: true
                                Text { text: "Power Profile"; color: Theme.primary; font.pixelSize: 13; font.bold: true }
                                Text { text: "Tuxedo CC"; color: Theme.primary; opacity: 0.5; font.pixelSize: 10 }
                            }
                            
                            // Tuxedo Button
                            Rectangle {
                                width: 74; height: 28; radius: 8
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                border.color: Theme.primary; border.width: 1
                                Layout.alignment: Qt.AlignVCenter; Layout.rightMargin: 4
                                
                                scale: tuxMouse.pressed ? 0.95 : (tuxMouse.containsMouse ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                Text { anchors.centerIn: parent; text: "Open"; color: Theme.primary; font.pixelSize: 10; font.bold: true }
                                MouseArea { 
                                    id: tuxMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: { localExec.run(["hyprctl","dispatch","exec","tuxedo-control-center"]); popup.active=false } 
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent; anchors.margins: 6; spacing: 4
                            visible: !popup.tuxedoInstalled
                            Repeater {
                                model: [
                                    { id: "power-saver",  icon: "󰁾", label: "Saver" },
                                    { id: "balanced",     icon: "󰁿", label: "Balanced" },
                                    { id: "performance",  icon: "󱐋", label: "Perf" }
                                ]
                                Rectangle {
                                    property bool sel: popup.powerProfile === modelData.id
                                    width: (parent.width - 8) / 3; height: parent.height
                                    radius: 10
                                    color: sel ? Theme.primary : "transparent"
                                    border.color: Theme.primary; border.width: sel ? 0 : 1
                                    
                                    scale: ppMouse.pressed ? 0.95 : (ppMouse.containsMouse && !sel ? 1.05 : 1.0)
                                    opacity: (ppMouse.containsMouse || sel) ? 1.0 : 0.8
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Column {
                                        anchors.centerIn: parent; spacing: 1
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon; color: sel ? Theme.background : Theme.primary; font.pixelSize: 14 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: sel ? Theme.background : Theme.primary; font.pixelSize: 9; font.bold: sel }
                                    }
                                    MouseArea { 
                                        id: ppMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        onClicked: { popup.powerProfile = modelData.id; powerProfileSetter.set(modelData.id) } 
                                    }
                                }
                            }
                        }
                    }
                }

                // ── System monitor button ─────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 38; radius: 12; color: Theme.primary
                    
                    scale: sysMonMouse.pressed ? 0.98 : (sysMonMouse.containsMouse ? 1.02 : 1.0)
                    opacity: sysMonMouse.containsMouse ? 0.9 : 1.0
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text { anchors.centerIn: parent; text: "󰓅  Open System Monitor"; color: Theme.background; font.bold: true; font.pixelSize: 11 }
                    MouseArea { 
                        id: sysMonMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { localExec.run(["bash","-c","~/.config/ml4w/settings/system-monitor.sh"]); popup.active=false } 
                    }
                }
            }
        }
    }
}