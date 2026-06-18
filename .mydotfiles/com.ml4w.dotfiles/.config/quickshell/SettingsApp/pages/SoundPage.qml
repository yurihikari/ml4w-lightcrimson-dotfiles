import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.CustomTheme
import qs.SettingsApp.components

StPage {
    id: page
    heading: "Sound"
    subheading: "Volume and audio devices"
    icon: "󰕾"

    property bool active: false

    property int outVol: 0
    property bool outMute: false
    property int inVol: 0
    property bool inMute: false
    property var sinks: []      // { name, desc, def }
    property var sources: []

    onActiveChanged: if (active) refresh()

    function refresh() {
        levelReader.running = true
        sinkReader._buf = ""; sinkReader.running = true
        sourceReader._buf = ""; sourceReader.running = true
    }

    Timer { interval: 1500; repeat: true; running: page.active; onTriggered: levelReader.running = true }

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

    Process { id: audioAction; function run(c) { command = ["bash", "-c", c]; running = true } }
    Process { id: defAction; function run(c) { command = ["bash", "-c", c]; running = true } onRunningChanged: if (!running) page.refresh() }

    function parseDevices(buf) {
        let out = []
        for (let l of buf.trim().split("\n")) {
            let p = l.split("\x1f")
            if (p.length < 3) continue
            out.push({ name: p[0].trim(), desc: p[1].trim(), def: p[2].trim() === "1" })
        }
        return out
    }

    function volIcon(v, muted) {
        if (muted || v === 0) return "󰝟"
        if (v < 34) return "󰕿"
        if (v < 67) return "󰖀"
        return "󰕾"
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
    }
}
