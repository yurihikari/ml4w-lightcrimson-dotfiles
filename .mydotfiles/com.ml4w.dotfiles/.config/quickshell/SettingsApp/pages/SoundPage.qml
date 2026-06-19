import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Sound"
    subheading: "Volume, devices, per-app streams and profiles"
    icon: "󰕾"

    property bool active: false

    // Master levels
    property int outVol: 0
    property bool outMute: false
    property int inVol: 0
    property bool inMute: false

    // Devices: { name, desc, def }
    property var sinks: []
    property var sources: []

    // Ports of the *default* sink/source: { name, desc }
    property var sinkPorts: []
    property string activeSinkPort: ""
    property var sourcePorts: []
    property string activeSourcePort: ""

    // Per-app streams: { idx, name, vol, mute }
    property var streams: []      // playback (sink-inputs)
    property var recStreams: []   // recording (source-outputs)

    // Sound cards: { cardName, desc, active, profiles: [{ key, desc }] }
    property var cards: []

    // True while an app slider is held — pauses stream polling so dragging the
    // (Repeater-backed) sliders is never interrupted by a model refresh.
    property bool dragging: false

    onActiveChanged: if (active) refresh()

    function refresh() {
        levelReader.running = true
        sinkReader._buf = ""; sinkReader.running = true
        sourceReader._buf = ""; sourceReader.running = true
        portReader._buf = ""; portReader.running = true
        cardReader._buf = ""; cardReader.running = true
        streamReader._buf = ""; streamReader.running = true
    }

    // Levels poll fast; streams poll too (but not mid-drag).
    Timer {
        interval: 1500; repeat: true; running: page.active
        onTriggered: {
            levelReader.running = true
            if (!page.dragging) { streamReader._buf = ""; streamReader.running = true }
        }
    }

    // ── Readers ────────────────────────────────────────────────────────────
    Process {
        id: levelReader
        property string _buf: ""
        command: ["bash", "-c",
            "echo \"outvol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')\"\n" +
            "echo \"outmute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -oE 'yes|no')\"\n" +
            "echo \"invol=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')\"\n" +
            "echo \"inmute=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -oE 'yes|no')\""
        ]
        stdout: SplitParser { onRead: levelReader._buf += data + "\n" }
        onRunningChanged: {
            if (running) return
            for (let l of levelReader._buf.trim().split("\n")) {
                let i = l.indexOf("="); if (i < 1) continue
                let k = l.substring(0, i), v = l.substring(i + 1).trim()
                if (k === "outvol" && v !== "") page.outVol = parseInt(v)
                else if (k === "outmute") page.outMute = (v === "yes")
                else if (k === "invol" && v !== "") page.inVol = parseInt(v)
                else if (k === "inmute") page.inMute = (v === "yes")
            }
            levelReader._buf = ""
        }
    }

    Process {
        id: sinkReader
        property string _buf: ""
        command: ["bash", "-c",
            "DEF=$(pactl get-default-sink 2>/dev/null)\n" +
            "pactl list sinks 2>/dev/null | awk -v def=\"$DEF\" '\n" +
            "/^Sink #/ {name=\"\";desc=\"\"}\n" +
            "/^\\tName:/ {name=$2}\n" +
            "/^\\tDescription:/ {$1=\"\";sub(/^ /,\"\");desc=$0; printf \"%s\\x1f%s\\x1f%s\\n\", name, desc, (name==def?\"1\":\"0\")}'"
        ]
        stdout: SplitParser { onRead: sinkReader._buf += data + "\n" }
        onRunningChanged: { if (!running) { page.sinks = page.parseDevices(sinkReader._buf); sinkReader._buf = "" } }
    }

    Process {
        id: sourceReader
        property string _buf: ""
        command: ["bash", "-c",
            "DEF=$(pactl get-default-source 2>/dev/null)\n" +
            "pactl list sources 2>/dev/null | awk -v def=\"$DEF\" '\n" +
            "/^Source #/ {name=\"\";desc=\"\";mon=0}\n" +
            "/^\\tName:/ {name=$2; if (name ~ /\\.monitor$/) mon=1}\n" +
            "/^\\tDescription:/ {$1=\"\";sub(/^ /,\"\");desc=$0; if (!mon) printf \"%s\\x1f%s\\x1f%s\\n\", name, desc, (name==def?\"1\":\"0\")}'"
        ]
        stdout: SplitParser { onRead: sourceReader._buf += data + "\n" }
        onRunningChanged: { if (!running) { page.sources = page.parseDevices(sourceReader._buf); sourceReader._buf = "" } }
    }

    // Ports of the current default sink + source (e.g. Speakers / Headphones).
    Process {
        id: portReader
        property string _buf: ""
        command: ["bash", "-c",
            "DSINK=$(pactl get-default-sink 2>/dev/null); DSRC=$(pactl get-default-source 2>/dev/null)\n" +
            "pactl list sinks 2>/dev/null | awk -v def=\"$DSINK\" '\n" +
            "/^Sink #/{cur=0}\n" +
            "/^\\tName:/{cur=($2==def)}\n" +
            "cur && /^\\tActive Port:/{print \"sinkactive\\x1f\" $3}\n" +
            "cur && /^\\t\\t/ && /priority:/{line=$0;sub(/^[ \\t]+/,\"\",line);pos=index(line,\": \");key=substr(line,1,pos-1);rest=substr(line,pos+2);d=rest;sub(/ \\(.*/,\"\",d);print \"sinkport\\x1f\" key \"\\x1f\" d}'\n" +
            "pactl list sources 2>/dev/null | awk -v def=\"$DSRC\" '\n" +
            "/^Source #/{cur=0}\n" +
            "/^\\tName:/{cur=($2==def)}\n" +
            "cur && /^\\tActive Port:/{print \"srcactive\\x1f\" $3}\n" +
            "cur && /^\\t\\t/ && /priority:/{line=$0;sub(/^[ \\t]+/,\"\",line);pos=index(line,\": \");key=substr(line,1,pos-1);rest=substr(line,pos+2);d=rest;sub(/ \\(.*/,\"\",d);print \"srcport\\x1f\" key \"\\x1f\" d}'"
        ]
        stdout: SplitParser { onRead: portReader._buf += data + "\n" }
        onRunningChanged: { if (!running) { page.applyPorts(portReader._buf); portReader._buf = "" } }
    }

    // Sound cards and their profiles (the "Configuration" tab in pavucontrol).
    Process {
        id: cardReader
        property string _buf: ""
        command: ["bash", "-c",
            "pactl list cards 2>/dev/null | awk '\n" +
            "/^Card #/{name=\"\";inprof=0}\n" +
            "/^\\tName:/{name=$2}\n" +
            "/device.description = /{l=$0; if(match(l,/\"[^\"]*\"/)) print \"carddesc\\x1f\" name \"\\x1f\" substr(l,RSTART+1,RLENGTH-2)}\n" +
            "/^\\tProfiles:/{inprof=1; next}\n" +
            "/^\\tActive Profile:/{inprof=0; a=$0; sub(/^\\tActive Profile: /,\"\",a); print \"cardactive\\x1f\" name \"\\x1f\" a}\n" +
            "inprof && /available:/{line=$0;sub(/^[ \\t]+/,\"\",line);pos=index(line,\": \");key=substr(line,1,pos-1);rest=substr(line,pos+2);d=rest;sub(/ \\(.*/,\"\",d);avail=(line ~ /available: no/)?\"0\":\"1\";print \"profile\\x1f\" name \"\\x1f\" key \"\\x1f\" d \"\\x1f\" avail}'"
        ]
        stdout: SplitParser { onRead: cardReader._buf += data + "\n" }
        onRunningChanged: { if (!running) { page.applyCards(cardReader._buf); cardReader._buf = "" } }
    }

    // Per-application playback (sink-inputs) and recording (source-outputs).
    Process {
        id: streamReader
        property string _buf: ""
        command: ["bash", "-c",
            "AWK='function flush(){ if(idx!=\"\"){ printf \"%s\\x1f%s\\x1f%s\\x1f%s\\x1f%s\\n\", t, idx, (app!=\"\"?app:(med!=\"\"?med:\"Audio\")), vol, mute } }\n" +
            "/^(Sink Input|Source Output) #/{ flush(); idx=$3; sub(/#/,\"\",idx); app=\"\";med=\"\";vol=\"0\";mute=\"no\" }\n" +
            "/^\\tMute:/{mute=$2}\n" +
            "/^\\tVolume:/{ if(match($0,/[0-9]+%/)){vol=substr($0,RSTART,RLENGTH);sub(/%/,\"\",vol)} }\n" +
            "/application\\.name = /{l=$0;if(match(l,/\"[^\"]*\"/))app=substr(l,RSTART+1,RLENGTH-2)}\n" +
            "/media\\.name = /{l=$0;if(match(l,/\"[^\"]*\"/))med=substr(l,RSTART+1,RLENGTH-2)}\n" +
            "END{flush()}'\n" +
            "pactl list sink-inputs 2>/dev/null | awk -v t=play \"$AWK\"\n" +
            "pactl list source-outputs 2>/dev/null | awk -v t=rec \"$AWK\""
        ]
        stdout: SplitParser { onRead: streamReader._buf += data + "\n" }
        onRunningChanged: { if (!running) { page.applyStreams(streamReader._buf); streamReader._buf = "" } }
    }

    Process { id: audioAction; function run(c) { command = ["bash", "-c", c]; running = true } }
    Process { id: defAction; function run(c) { command = ["bash", "-c", c]; running = true } onRunningChanged: if (!running) page.refresh() }

    // ── Parse helpers ──────────────────────────────────────────────────────
    function parseDevices(buf) {
        let out = []
        for (let l of buf.trim().split("\n")) {
            let p = l.split("\x1f")
            if (p.length < 3) continue
            out.push({ name: p[0].trim(), desc: p[1].trim(), def: p[2].trim() === "1" })
        }
        return out
    }

    function applyPorts(buf) {
        let sp = [], srp = [], sa = "", sra = ""
        for (let l of buf.trim().split("\n")) {
            let p = l.split("\x1f")
            if (p[0] === "sinkport" && p.length >= 3) sp.push({ name: p[1].trim(), desc: p[2].trim() })
            else if (p[0] === "sinkactive") sa = p[1].trim()
            else if (p[0] === "srcport" && p.length >= 3) srp.push({ name: p[1].trim(), desc: p[2].trim() })
            else if (p[0] === "srcactive") sra = p[1].trim()
        }
        page.sinkPorts = sp; page.activeSinkPort = sa
        page.sourcePorts = srp; page.activeSourcePort = sra
    }

    function applyCards(buf) {
        let map = ({}), order = []
        for (let l of buf.trim().split("\n")) {
            let p = l.split("\x1f")
            if (p.length < 2) continue
            let name = p[1].trim()
            if (!map[name]) { map[name] = { cardName: name, desc: name, active: "", profiles: [] }; order.push(name) }
            if (p[0] === "carddesc") map[name].desc = p[2].trim()
            else if (p[0] === "cardactive") map[name].active = p[2].trim()
            else if (p[0] === "profile" && p.length >= 5 && p[4].trim() === "1")
                map[name].profiles.push({ key: p[2].trim(), desc: p[3].trim() })
        }
        let arr = []
        for (let n of order) if (map[n].profiles.length > 0) arr.push(map[n])
        page.cards = arr
    }

    function applyStreams(buf) {
        let play = [], rec = []
        for (let l of buf.trim().split("\n")) {
            let p = l.split("\x1f")
            if (p.length < 5) continue
            let item = { idx: p[1].trim(), name: p[2].trim(), vol: parseInt(p[3]) || 0, mute: p[4].trim() === "yes" }
            if (p[0] === "play") play.push(item)
            else if (p[0] === "rec") rec.push(item)
        }
        // Only reassign when something actually changed — keeps delegates (and
        // their sliders) alive and flicker-free between polls.
        if (JSON.stringify(play) !== JSON.stringify(page.streams)) page.streams = play
        if (JSON.stringify(rec) !== JSON.stringify(page.recStreams)) page.recStreams = rec
    }

    function volIcon(v, muted) {
        if (muted || v === 0) return "󰝟"
        if (v < 34) return "󰕿"
        if (v < 67) return "󰖀"
        return "󰕾"
    }

    // ── Reusable per-app stream row ─────────────────────────────────────────
    // kind is "sink-input" (playback) or "source-output" (recording).
    component StreamRow: StRow {
        required property var modelData
        property string kind: "sink-input"
        icon: kind === "sink-input" ? "󰓃" : "󰍬"
        title: modelData.name
        subtitle: modelData.mute ? "Muted" : (modelData.vol + "%")

        StSlider {
            id: s
            implicitWidth: 170
            from: 0; to: 100
            Binding on value { when: !s.pressed; value: modelData.vol }
            onPressedChanged: page.dragging = pressed
            onMovedTo: (v) => audioAction.run("pactl set-" + kind + "-volume " + modelData.idx + " " + Math.round(v) + "%")
        }
        StIconButton {
            icon: modelData.mute ? "󰝟" : (kind === "sink-input" ? "󰕾" : "󰍬")
            onClicked: audioAction.run("pactl set-" + kind + "-mute " + modelData.idx + " toggle")
        }
    }

    // ── Output ───────────────────────────────────────────────────────────
    StCard {
        title: "Output"

        StRow {
            icon: page.volIcon(page.outVol, page.outMute)
            title: "Volume"
            subtitle: page.outMute ? "Muted" : page.outVol + "%"
            StSlider {
                id: outSlider
                implicitWidth: 220
                from: 0; to: 100
                Binding on value { when: !outSlider.pressed; value: page.outVol }
                onMovedTo: (v) => { page.outVol = Math.round(v); audioAction.run("pactl set-sink-volume @DEFAULT_SINK@ " + Math.round(v) + "%") }
            }
            StIconButton {
                icon: page.outMute ? "󰝟" : "󰕾"
                onClicked: { page.outMute = !page.outMute; audioAction.run("pactl set-sink-mute @DEFAULT_SINK@ toggle") }
            }
        }

        StRow {
            icon: "󰓃"
            title: "Output device"
            StComboBox {
                implicitWidth: 260
                textRole: "desc"
                model: page.sinks
                currentIndex: { for (var i = 0; i < page.sinks.length; i++) if (page.sinks[i].def) return i; return -1 }
                onActivated: (i) => defAction.run("pactl set-default-sink " + page.sinks[i].name)
            }
        }

        StRow {
            visible: page.sinkPorts.length > 1
            icon: "󰋋"
            title: "Port"
            subtitle: "Speakers, headphones, HDMI…"
            StComboBox {
                implicitWidth: 260
                textRole: "desc"
                model: page.sinkPorts
                currentIndex: { for (var i = 0; i < page.sinkPorts.length; i++) if (page.sinkPorts[i].name === page.activeSinkPort) return i; return -1 }
                onActivated: (i) => defAction.run("pactl set-sink-port @DEFAULT_SINK@ " + page.sinkPorts[i].name)
            }
        }
    }

    // ── Input ────────────────────────────────────────────────────────────
    StCard {
        title: "Input"

        StRow {
            icon: page.inMute ? "󰍭" : "󰍬"
            title: "Microphone volume"
            subtitle: page.inMute ? "Muted" : page.inVol + "%"
            StSlider {
                id: inSlider
                implicitWidth: 220
                from: 0; to: 100
                Binding on value { when: !inSlider.pressed; value: page.inVol }
                onMovedTo: (v) => { page.inVol = Math.round(v); audioAction.run("pactl set-source-volume @DEFAULT_SOURCE@ " + Math.round(v) + "%") }
            }
            StIconButton {
                icon: page.inMute ? "󰍭" : "󰍬"
                onClicked: { page.inMute = !page.inMute; audioAction.run("pactl set-source-mute @DEFAULT_SOURCE@ toggle") }
            }
        }

        StRow {
            icon: "󰍬"
            title: "Input device"
            StComboBox {
                implicitWidth: 260
                textRole: "desc"
                model: page.sources
                currentIndex: { for (var i = 0; i < page.sources.length; i++) if (page.sources[i].def) return i; return -1 }
                onActivated: (i) => defAction.run("pactl set-default-source " + page.sources[i].name)
            }
        }

        StRow {
            visible: page.sourcePorts.length > 1
            icon: "󰍬"
            title: "Port"
            subtitle: "Internal mic, headset…"
            StComboBox {
                implicitWidth: 260
                textRole: "desc"
                model: page.sourcePorts
                currentIndex: { for (var i = 0; i < page.sourcePorts.length; i++) if (page.sourcePorts[i].name === page.activeSourcePort) return i; return -1 }
                onActivated: (i) => defAction.run("pactl set-source-port @DEFAULT_SOURCE@ " + page.sourcePorts[i].name)
            }
        }
    }

    // ── Applications (per-app playback) ────────────────────────────────────
    StCard {
        title: "Applications"
        visible: page.streams.length > 0

        Repeater {
            model: page.streams
            delegate: StreamRow { kind: "sink-input" }
        }
    }

    // ── Recording (per-app capture) ────────────────────────────────────────
    StCard {
        title: "Recording"
        visible: page.recStreams.length > 0

        Repeater {
            model: page.recStreams
            delegate: StreamRow { kind: "source-output" }
        }
    }

    // ── Configuration (sound card profiles) ────────────────────────────────
    StCard {
        title: "Configuration"
        visible: page.cards.length > 0

        Repeater {
            model: page.cards
            delegate: StRow {
                required property var modelData
                icon: "󰒓"
                title: modelData.desc
                subtitle: "Card profile"
                StComboBox {
                    implicitWidth: 300
                    textRole: "desc"
                    model: modelData.profiles
                    currentIndex: { for (var i = 0; i < modelData.profiles.length; i++) if (modelData.profiles[i].key === modelData.active) return i; return -1 }
                    onActivated: (i) => defAction.run("pactl set-card-profile " + modelData.cardName + " " + modelData.profiles[i].key)
                }
            }
        }
    }
}
