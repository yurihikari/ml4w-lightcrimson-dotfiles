import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

BarPopup {
    id: popup
    ipcTarget: "bar-system"
    property string currentTab: "Network"

    // Keyboard focus handler for ESC
    FocusScope {
        anchors.fill: parent
        focus: popup.active
        Keys.onEscapePressed: {
            if (popup.showPasswordFor) popup.showPasswordFor = false
            else popup.active = false
        }
    }

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
    // Every GPU in the machine, dedicated first, as
    // { pci, vendor, kind: "dedicated"|"integrated", asleep, temp, usage }.
    // temp is 0 and usage -1 when the driver does not report them (Intel has
    // no load counter; a runtime-suspended GPU is left asleep, not polled).
    property var gpus: []
    // The GPU the cards show (its PCI address). Until the user picks one, it
    // follows the dedicated GPU while that is awake, so a hybrid laptop shows
    // the dGPU whenever it is actually in use.
    property string gpuSelected: ""
    property bool gpuPinned: false
    property var gpuTempHistories: ({})   // pci -> last 30 temperatures
    readonly property var gpu: {
        for (const g of gpus) if (g.pci === gpuSelected) return g
        return gpus.length > 0 ? gpus[0] : null
    }
    readonly property real gpuTemp: gpu && !gpu.asleep ? gpu.temp : 0
    readonly property real gpuUsage: gpu && gpu.usage >= 0 ? gpu.usage / 100 : 0
    readonly property string gpuVendor: gpu ? gpu.vendor : ""

    // "dGPU" / "iGPU", numbered when two GPUs share a kind.
    function gpuLabel(g) {
        const same = gpus.filter(o => o.kind === g.kind)
        const base = g.kind === "integrated" ? "iGPU" : "dGPU"
        if (same.length < 2) return base
        return base + " " + (same.findIndex(o => o.pci === g.pci) + 1)
    }
    function gpuUsageText(g) {
        if (!g) return "—"
        if (g.asleep) return "Asleep"
        if (g.usage >= 0) return Math.round(g.usage) + "%"
        return g.vendor === "intel" ? "n/a" : "—"
    }
    property real memUsedGB: 0
    property real memTotalGB: 0
    property real netRxKBs: 0
    property real netTxKBs: 0
    property string uptimeStr: ""
    property int batteryPct: -1
    property bool batteryCharging: false

    // ─── Sparkline history (last 30 samples) ───────────────────────────────
    property var cpuTempHistory: []
    readonly property var gpuTempHistory: gpu ? (gpuTempHistories[gpu.pci] || []) : []
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
        id: gamemodeExec
        function apply(enable) {
            // The active theme's copy, like the keybind and quick panel use
            command = ["bash", "-c", "$HOME/.config/hypr/scripts/gamemode.sh"]
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
        id: gamemodeReader
        command: ["bash", "-c", "test -f ~/.config/ml4w/settings/gamemode-enabled && echo 1 || echo 0"]
        stdout: SplitParser {
            onRead: { popup.gamemodeActive = (data.trim() === "1") }
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

    // One "gpu=pci|vendor|kind|asleep|temp|usage" line per GPU (DRM card).
    // Dedicated vs integrated: amdgpu only exposes mem_info_vram_vendor on
    // cards with their own VRAM, Intel's iGPU always sits at 00:02.0, and
    // NVIDIA GPUs are dedicated. A runtime-suspended GPU (a hybrid laptop's
    // idle dGPU) is reported asleep without reading it: nvidia-smi or the
    // amdgpu counters would wake it up every poll and drain the battery.
    readonly property string _gpuProbe: `
nv_seen=0
for c in /sys/class/drm/card*; do
  case "$(basename "$c")" in *-*) continue ;; esac
  d=$(readlink -f "$c/device") || continue
  pci=$(basename "$d")
  drv=$(basename "$(readlink "$d/driver" 2>/dev/null)")
  case "$drv" in
    amdgpu|radeon) vendor=amd ;;
    nvidia|nouveau) vendor=nvidia ;;
    i915|xe) vendor=intel ;;
    *) continue ;;
  esac
  if [ "$vendor" = amd ]; then
    [ -e "$d/mem_info_vram_vendor" ] && kind=dedicated || kind=integrated
  elif [ "$vendor" = intel ]; then
    [ "$pci" = 0000:00:02.0 ] && kind=integrated || kind=dedicated
  else
    kind=dedicated
  fi
  [ "$drv" = nvidia ] && nv_seen=1
  if [ "$(cat "$d/power/runtime_status" 2>/dev/null)" = suspended ]; then
    echo "gpu=$pci|$vendor|$kind|1||"
    continue
  fi
  temp=; usage=
  if [ "$drv" = nvidia ]; then
    out=$(nvidia-smi --query-gpu=pci.bus_id,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null |
      awk -F', *' -v p="$pci" 'tolower(substr($1, length($1) - 6)) == substr(p, length(p) - 6) { print $2 "|" $3; exit }')
    temp=$(echo "$out" | cut -d'|' -f1); usage=$(echo "$out" | cut -d'|' -f2)
  else
    [ -r "$d/gpu_busy_percent" ] && usage=$(cat "$d/gpu_busy_percent" 2>/dev/null)
    for h in "$d"/hwmon/hwmon*; do
      t=$(cat "$h/temp1_input" 2>/dev/null)
      [ -n "$t" ] && temp=$((t / 1000)) && break
    done
  fi
  echo "gpu=$pci|$vendor|$kind|0|$temp|$usage"
done
# The NVIDIA driver without modesetting has no DRM card: ask nvidia-smi.
if [ "$nv_seen" = 0 ] && command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=pci.bus_id,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null |
    awk -F', *' '{ print "gpu=" tolower(substr($1, length($1) - 11)) "|nvidia|dedicated|0|" $2 "|" $3 }'
fi
`

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
            popup._gpuProbe +
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
                let gpus = []
                for (let l of lines) {
                    let i = l.indexOf("=")
                    if (i < 1) continue
                    let k = l.substring(0, i)
                    let v = l.substring(i + 1).trim()
                    switch (k) {
                        case "cpuusage":    popup.localCpuUsage = (parseFloat(v) || 0) / 100; break
                        case "cputemp":     popup.cpuTemp     = parseFloat(v) || 0; break
                        case "cpufreq":     popup.cpuFreq     = parseFloat(v) || 0; break
                        case "gpu": {
                            const f = v.split("|")
                            if (f.length < 6) break
                            const usage = parseFloat(f[5])
                            gpus.push({
                                pci: f[0], vendor: f[1], kind: f[2], asleep: f[3] === "1",
                                temp: parseFloat(f[4]) || 0,
                                usage: isNaN(usage) ? -1 : usage
                            })
                            break
                        }
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
                gpus.sort((a, b) => (a.kind === b.kind ? 0 : (a.kind === "dedicated" ? -1 : 1))
                                    || a.pci.localeCompare(b.pci))
                let hists = {}
                for (const g of gpus) {
                    const h = popup.gpuTempHistories[g.pci] || []
                    hists[g.pci] = g.temp > 0 && !g.asleep ? popup.pushHist(h, g.temp, 30) : h
                }
                popup.gpuTempHistories = hists
                popup.gpus = gpus
                // Follow the busiest-capable GPU until the user picks one: an
                // awake dedicated GPU, else an integrated one, else whatever
                // is there. A picked GPU that disappears is let go.
                if (popup.gpuPinned && !gpus.some(g => g.pci === popup.gpuSelected))
                    popup.gpuPinned = false
                if (!popup.gpuPinned) {
                    const pick = gpus.find(g => g.kind === "dedicated" && !g.asleep)
                              || gpus.find(g => !g.asleep) || gpus[0]
                    popup.gpuSelected = pick ? pick.pci : ""
                }
                let cpuForHistory = popup.localCpuUsage > 0 ? popup.localCpuUsage : Sys.cpuUsage
                popup.cpuUsageHistory = popup.pushHist(popup.cpuUsageHistory, cpuForHistory, 30)
                if (popup.localCpuUsage > 0) Sys.cpuUsage = popup.localCpuUsage
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

    Timer { id: gamemodeRepoll; interval: 100; repeat: true; onTriggered: gamemodeReader.running=true }
    Timer { id: repollTimer; interval: 800; repeat: false; onTriggered: { wifiScanner.running=true; btScanner.running=true } }

    onOpened: {
        if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
        if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
        if (currentTab === "Performance") { powerProfileReader.running=true; gamemodeReader.running=true }
    }
    onCurrentTabChanged: {
        if (!active) return
        if (currentTab === "Network")     { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
        if (currentTab === "Bluetooth")   { popup._btBuf="";   popup.btScanning=true;   btScanner.running=true }
        if (currentTab === "Performance") { powerProfileReader.running=true; gamemodeReader.running=true }
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
    // Flush against the right frame, it takes over the frame's top-right corner
    // (the frame hides its own corner while this is out, via FrameCorners).
    PopoutContent {
        id: drawer
        open: popup.active
        onClosed: popup.isAnimating = false
        hAlign: "right"
        hMargin: PanelStyle.rightMargin
        panelWidth: container.width
        panelHeight: container.height

    Rectangle {
        id: container
        // Same size as the other right-hand sections, except the wider
        // Performance view with its charts.
        width:  popup.currentTab === "Performance" ? 700 : PanelStyle.narrowWidth
        height: popup.currentTab === "Performance" ? 720 : PanelStyle.rightHeight
        Behavior on width  { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
        radius: 30; color: "transparent"

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: PanelStyle.pad; spacing: PanelStyle.gap

            PanelHeader {
                icon: popup.currentTab === "Network" ? "󰤨"
                    : popup.currentTab === "Bluetooth" ? "󰂯" : "󰻠"
                title: popup.currentTab === "Performance" ? "System" : popup.currentTab
                subtitle: popup.currentTab === "Network"
                    ? (Sys.connType === "ethernet" ? "Ethernet connected"
                       : (Sys.wifi !== "" ? Sys.wifi : (Sys.wifiRadio ? "Not connected" : "Wi-Fi off")))
                    : popup.currentTab === "Bluetooth"
                    ? (!Sys.bluetooth ? "Off"
                       : (popup.btDevices.filter(d => d.connected).length > 0
                          ? popup.btDevices.filter(d => d.connected).length + " connected"
                          : popup.btDevices.length + " paired"))
                    : (popup.uptimeStr !== "" ? "Up " + popup.uptimeStr : "Performance")
                SectionNav { host: popup.host; current: popup.ipcTarget }
            }

            // ── Tab bar (segmented) ───────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 36; radius: PanelStyle.radiusControl; color: PanelStyle.cardFill
                Row {
                    anchors.fill: parent; anchors.margins: 3; spacing: 3
                    Repeater {
                        model: ["Network", "Bluetooth", "Performance"]
                        Rectangle {
                            readonly property bool isCurrent: popup.currentTab === modelData
                            width: (parent.width - 6) / 3; height: parent.height; radius: PanelStyle.radiusControl - 3
                            color: isCurrent ? Theme.withAlpha(Theme.primary, 0.20)
                                 : (tabMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.08) : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData === "Network"   ? "󰤨  Network"
                                    : modelData === "Bluetooth" ? "󰂯  Bluetooth"
                                    : "󰻠  System"
                                color: Theme.primary
                                font.bold: true; font.pixelSize: 13
                                opacity: parent.isCurrent ? 1.0 : (tabMouse.containsMouse ? 0.85 : 0.55)
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
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
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10

                Rectangle {
                    Layout.fillWidth: true; height: 48; radius: PanelStyle.radiusCard; color: PanelStyle.cardFill
                    visible: Sys.connType === "ethernet"
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
                    IconButton {
                        icon: "󰑓"
                        busy: popup.wifiScanning
                        enabled: !popup.wifiScanning
                        onClicked: { popup._wifiBuf=""; popup.wifiScanning=true; wifiScanner.running=true }
                    }

                    // Wi-Fi Toggle Switch
                    BarToggle {
                        checked: Sys.wifiRadio
                        onClicked: { Sys.run(["bash", "-c", Sys.wifiRadio ? "nmcli radio wifi off" : "nmcli radio wifi on"]); repollTimer.restart() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: PanelStyle.radiusCard
                    color: PanelStyle.cardFill; clip: true

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
                                    border.color: "transparent" /* was primary @ 0.3; surfaces use tone, not outlines */; border.width: 1
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
                PanelButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    icon: "󰖟"
                    text: "Advanced Network Settings"
                    onClicked: { Sys.run(["qs", "ipc", "call", "settings", "openPage", "network"]); popup.active=false }
                }
            }

            // ══════════════════════════════════════════════════════════════
            //  BLUETOOTH TAB
            // ══════════════════════════════════════════════════════════════
            ColumnLayout {
                visible: popup.currentTab === "Bluetooth"
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰂯  Bluetooth"; color: Theme.primary; font.bold: true; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }
                    
                    // BT Refresh Button
                    IconButton {
                        icon: "󰑓"
                        busy: popup.btScanning
                        enabled: !popup.btScanning
                        onClicked: { popup._btBuf=""; popup.btScanning=true; btScanner.running=true }
                    }

                    // BT Toggle Switch
                    BarToggle {
                        checked: Sys.bluetooth
                        onClicked: { Sys.run(["bash","-c",Sys.bluetooth?"bluetoothctl power off":"bluetoothctl power on"]); repollTimer.restart() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: PanelStyle.radiusCard
                    color: PanelStyle.cardFill; clip: true
                    Text {
                        anchors.centerIn: parent
                        text: popup.btScanning ? "Scanning…" : (!Sys.bluetooth ? "Bluetooth is off" : popup.btDevices.length===0 ? "No paired devices" : "")
                        color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                        visible: popup.btScanning || !Sys.bluetooth || popup.btDevices.length===0
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

                PanelButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    icon: "󰂱"
                    text: "Bluetooth Manager"
                    onClicked: { Sys.run(["blueman-manager"]); popup.active=false }
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

                    CircleGauge { label: "CPU";    icon: "󰻠"; value: Sys.cpuUsage }
                    CircleGauge { label: "Memory"; icon: "󰍛"; value: Sys.ramUsage }
                    CircleGauge { label: "Disk";   icon: "󰋊"; value: Sys.diskUsage }
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
                    // Controls at the right end of the header (a switcher),
                    // laid out with the label so they never overlap it.
                    property alias  trailing: trailingSlot.data

                    onHistoryChanged: spark.requestPaint()
                    onYMaxChanged:    spark.requestPaint()

                    width: parent ? parent.width : 0
                    height: 110
                    radius: 14
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                    border.color: "transparent" /* was primary @ 0.12; surfaces use tone, not outlines */
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
                            Text { text: cardLabel; color: Theme.primary; opacity: 0.5; font.pixelSize: 9; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: cardValue; color: cardColor; font.pixelSize: 16; font.weight: Font.Black; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        Text { text: cardSub; color: Theme.primary; opacity: 0.4; font.pixelSize: 9 }
                        Row {
                            id: trailingSlot
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter
                            visible: children.length > 0
                        }
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
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                    border.color: "transparent" /* was primary @ 0.12; surfaces use tone, not outlines */
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
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                    border.color: "transparent" /* was primary @ 0.12; surfaces use tone, not outlines */
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
                                cardValue: Math.round(Sys.cpuUsage * 100) + "%"
                                cardColor: Sys.cpuUsage > 0.85 ? "#e06c75" : Theme.primary
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
                                // With several GPUs the switcher names them
                                // and leaves the label no room for a vendor.
                                cardLabel: popup.gpus.length < 2 && popup.gpuVendor !== ""
                                    ? "GPU TEMP · " + popup.gpuVendor.toUpperCase() : "GPU TEMP"
                                cardValue: popup.gpu && popup.gpu.asleep ? "Asleep"
                                    : (popup.gpuTemp > 0 ? popup.gpuTemp.toFixed(0) + "°C" : "—")
                                cardColor: popup.tempColor(popup.gpuTemp)
                                history:   popup.gpuTempHistory
                                yMin: 30; yMax: 95

                                // GPU switcher (only with more than one GPU)
                                trailing: Repeater {
                                    model: popup.gpus.length > 1 ? popup.gpus : []
                                    delegate: Rectangle {
                                        id: gpuChip
                                        required property var modelData
                                        readonly property bool selected: popup.gpu !== null && popup.gpu.pci === modelData.pci
                                        width: gpuChipText.implicitWidth + 12; height: 18; radius: 6
                                        color: selected ? Theme.primary
                                            : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, gpuChipMouse.containsMouse ? 0.18 : 0.10)
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            id: gpuChipText
                                            anchors.centerIn: parent
                                            text: popup.gpuLabel(gpuChip.modelData)
                                            color: gpuChip.selected ? Theme.background : Theme.primary
                                            opacity: gpuChip.modelData.asleep && !gpuChip.selected ? 0.5 : 1
                                            font.pixelSize: 9; font.bold: true
                                        }
                                        MouseArea {
                                            id: gpuChipMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                popup.gpuSelected = gpuChip.modelData.pci
                                                popup.gpuPinned = true
                                            }
                                        }
                                    }
                                }
                            }
                            CompactCard {
                                cardIcon:  "󰢮"
                                cardLabel: "GPU USAGE"
                                cardValue: popup.gpuUsageText(popup.gpu)
                                // The other GPUs at a glance, e.g. "iGPU 0%"
                                cardSub: popup.gpus
                                    .filter(g => !popup.gpu || g.pci !== popup.gpu.pci)
                                    .map(g => popup.gpuLabel(g) + " " + popup.gpuUsageText(g))
                                    .join("  ")
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
                            BarToggle {
                                checked: popup.gamemodeActive
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: {
                                    gamemodeExec.apply(!popup.gamemodeActive)
                                    gamemodeRepoll.restart()
                                }
                            }
                        }
                    }

                    // Power profile pills (or tuxedo button)
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        height: 56; radius: 14
                        color: Theme.background
                        border.color: "transparent" /* was primary @ 0.2; surfaces use tone, not outlines */
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
                                    onClicked: {
                                        Sys.run([
                                            "hyprctl",
                                            "dispatch",
                                            "hl.dsp.exec_cmd(\"tuxedo-control-center\")"
                                        ])
                                        popup.active = false
                                    }
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

                PanelButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    icon: "󰓅"
                    text: "Open System Monitor"
                    onClicked: { Sys.run(["bash","-c","~/.config/ml4w/settings/system-monitor.sh"]); popup.active=false }
                }
            }
        }
    }
    } // PopoutContent
}
