pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The assistant's brain: talks to the Claude CLI (`claude -p` with stream-json
// in and out, one long-running process per conversation), keeps the chat of
// each persona, and drives the optional character overlay (character/).
//
// Nothing runs until the first message: the CLI starts then and stays up for
// the next ones; switching persona or starting a new chat restarts it. Each
// persona has its own conversation (resumed with --resume after a restart) and
// its own saved transcript in ~/.local/state/ml4w-assistant/.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: home + "/.local/state/ml4w-assistant"
    // Characters the user adds themselves: <dir>/<persona id>/ with a Spine
    // skeleton (.skel or .json), its .atlas and textures. Not shipped.
    readonly property string charactersDir: home + "/.local/share/ml4w-assistant/characters"
    readonly property string appDir: Quickshell.shellDir + "/AssistantApp"

    // ── Personas ───────────────────────────────────────────────────────────
    readonly property var personaIds: ["assistant", "arona", "plana"]
    property var personas: ({})
    readonly property var specialPersonas: personaIds.filter(id => personas[id] && personas[id].special)

    // "assistant" or "special", and the special persona picked last
    property string mode: "assistant"
    property string specialPersona: "arona"
    readonly property string personaId: mode === "special" ? specialPersona : "assistant"
    readonly property var persona: personas[personaId] || ({ id: personaId, name: personaId, lines: {} })

    function line(kind) {
        const l = (persona.lines || {})[kind] || []
        return l.length ? l[Math.floor(Math.random() * l.length)] : ""
    }

    // ── Conversation ───────────────────────────────────────────────────────
    // role: "user" | "assistant" | "note" (errors, "stopped")
    ListModel { id: messagesModel }
    readonly property alias messages: messagesModel
    property bool busy: false        // a reply is being generated
    property string status: ""       // "Searching the web…" and such
    property var sessions: ({})      // persona id -> Claude session id
    property string model: ""        // empty: the CLI's default

    function send(text) {
        text = text.trim()
        if (text === "" || busy) return
        messagesModel.append({ role: "user", text: text, streaming: false })
        busy = true
        status = line("thinking") || "Thinking…"
        _turnStarted = false
        _pending.push(JSON.stringify({
            type: "user",
            message: { role: "user", content: [{ type: "text", text: text }] }
        }) + "\n")
        if (!claude.running) _start()
        else if (!_killing) _flush()
        // else: the old CLI is exiting (persona switch); onExited starts the new one
        _save()
        character.react("talk")
    }

    function stop() {
        if (!busy) return
        _stopped = true
        _kill()
    }

    function newChat() {
        _pending = []
        _kill()
        busy = false; status = ""
        messagesModel.clear()
        const s = Object.assign({}, sessions); delete s[personaId]; sessions = s
        _save()
    }

    // ── Claude CLI ─────────────────────────────────────────────────────────
    property string _runningPersona: ""
    property bool _turnStarted: false
    property bool _stopped: false
    property string _stderr: ""
    property var _pending: []        // lines written once the CLI has started

    property bool _killing: false
    function _kill() {
        if (claude.running) { _killing = true; claude.running = false }
    }

    function _flush() {
        if (!claude.running) return
        for (const l of _pending) claude.write(l)
        _pending = []
    }

    function _start() {
        const args = ["claude", "-p",
            "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--system-prompt", persona.systemPrompt || "",
            // A chat, not an agent: web lookups only, no files or commands
            "--tools", "WebSearch,WebFetch", "--allowedTools", "WebSearch,WebFetch",
            // Skip the user's hooks, plugins and MCP servers (faster, isolated)
            "--setting-sources", "", "--strict-mcp-config"]
        if (model !== "") args.push("--model", model)
        if (sessions[personaId]) args.push("--resume", sessions[personaId])
        _runningPersona = personaId
        _stderr = ""
        _stopped = false
        claude.command = args
        claude.running = true
    }

    // The persona changed: the running CLI has the old system prompt
    onPersonaIdChanged: {
        if (claude.running && _runningPersona !== personaId) _kill()
        busy = false; status = ""
        _loadHistory()
        _save()
        character.sync()
    }

    function _assistantIndex() {
        const n = messagesModel.count
        return n && messagesModel.get(n - 1).role === "assistant" && messagesModel.get(n - 1).streaming ? n - 1 : -1
    }

    function _appendText(t) {
        let i = _assistantIndex()
        if (i < 0) { messagesModel.append({ role: "assistant", text: "", streaming: true }); i = messagesModel.count - 1 }
        messagesModel.setProperty(i, "text", messagesModel.get(i).text + t)
    }

    function _finishTurn(errorText) {
        const i = _assistantIndex()
        if (i >= 0) messagesModel.setProperty(i, "streaming", false)
        if (errorText) messagesModel.append({ role: "note", text: errorText, streaming: false })
        busy = false; status = ""
        _save()
        character.react(errorText ? "error" : "idle")
    }

    function _handle(o) {
        switch (o.type) {
        case "system":
            if (o.subtype === "init" && o.session_id) {
                const s = Object.assign({}, sessions); s[_runningPersona] = o.session_id; sessions = s
            }
            break
        case "stream_event": {
            const e = o.event || {}
            if (e.type === "message_start" && _turnStarted) _appendText("\n\n")   // another message in the same turn (after a search)
            else if (e.type === "content_block_start") {
                const b = e.content_block || {}
                if (b.type === "server_tool_use" || b.type === "tool_use")
                    status = b.name === "web_fetch" || b.name === "WebFetch" ? "Reading a page…" : "Searching the web…"
                else if (b.type === "text") status = ""
            } else if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") {
                _turnStarted = true
                _appendText(e.delta.text)
            }
            break
        }
        case "result":
            _finishTurn(o.is_error ? (o.result || "The assistant returned an error.") : "")
            break
        }
    }

    Process {
        id: claude
        workingDirectory: root.stateDir
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (l) => {
                if (l === "") return
                try { root._handle(JSON.parse(l)) } catch (e) { console.warn("assistant: bad line", l.slice(0, 120)) }
            }
        }
        stderr: SplitParser { onRead: (l) => root._stderr = (root._stderr + l + "\n").slice(-2000) }
        onStarted: root._flush()
        onExited: (code) => {
            root._killing = false
            // A message sent while the old CLI was exiting: start the new one
            if (root._pending.length && !root._stopped) { root._start(); return }
            root._pending = []
            if (!root.busy) return
            if (root._stopped) root._finishTurn("Stopped.")
            else root._finishTurn("The Claude CLI exited (" + code + "). " + root._stderr.trim().split("\n").slice(-3).join(" "))
        }
    }

    // ── Persistence ────────────────────────────────────────────────────────
    Process { id: mkState; command: ["mkdir", "-p", root.stateDir]; running: true }

    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        blockLoading: true
        printErrors: false
    }
    // Every persona's transcript in one file. (One fixed path on purpose:
    // Quickshell hands a FileView's contents over to the reloaded config, so a
    // FileView that changed path could show the previous file's text.)
    FileView {
        id: historyFile
        path: root.stateDir + "/history.json"
        blockLoading: true
        printErrors: false
    }

    property bool _loaded: false
    property var _histories: ({})     // persona id -> [{role, text}]
    property string _shownPersona: "" // whose messages are in the model

    // Keep the shown conversation in _histories (last 200 messages)
    function _stash() {
        if (_shownPersona === "") return
        const list = []
        for (let i = Math.max(0, messagesModel.count - 200); i < messagesModel.count; i++) {
            const m = messagesModel.get(i)
            if (!m.streaming) list.push({ role: m.role, text: m.text })
        }
        const h = Object.assign({}, _histories); h[_shownPersona] = list; _histories = h
    }
    function _loadHistory() {
        _stash()
        messagesModel.clear()
        for (const m of (_histories[personaId] || [])) messagesModel.append({ role: m.role, text: m.text, streaming: false })
        _shownPersona = personaId
    }
    function _save() {
        if (!_loaded) return
        _stash()
        stateFile.setText(JSON.stringify({ mode: mode, specialPersona: specialPersona, sessions: sessions, model: model }, null, 2))
        historyFile.setText(JSON.stringify(_histories))
    }
    onModeChanged: _save()
    onSpecialPersonaChanged: _save()

    // Personas ship as JSON next to this app
    Instantiator {
        model: root.personaIds
        delegate: FileView {
            required property string modelData
            path: root.appDir + "/personas/" + modelData + ".json"
            blockLoading: true
            onLoaded: {
                try {
                    const p = Object.assign({}, root.personas); p[modelData] = JSON.parse(text()); root.personas = p
                } catch (e) { console.warn("assistant: bad persona", modelData, e) }
            }
        }
    }

    Component.onCompleted: {
        try { _histories = JSON.parse(historyFile.text() || "{}") } catch (e) { _histories = {} }
        try {
            const s = JSON.parse(stateFile.text() || "{}")
            if (s.mode) mode = s.mode
            if (s.specialPersona) specialPersona = s.specialPersona
            if (s.sessions) sessions = s.sessions
            if (s.model) model = s.model
        } catch (e) {}
        _loadHistory()
        _loaded = true
    }

    // ── Character overlay (special personas with user-provided assets) ─────
    // Shown next to the panel while it's open; `panelRight` is how far from
    // the screen's right edge the character should stand (the panel's width).
    QtObject {
        id: character
        property bool wanted: false
        property real panelRight: 460
        property bool available: false      // assets present for this persona
        property string shownFor: ""
        property var animations: []

        function sync() {
            const id = root.personaId
            const want = wanted && root.mode === "special"
            if (!want) { if (charProc.running) charProc.running = false; return }
            if (charProc.running && shownFor === id) return
            if (charProc.running) charProc.running = false
            assetCheck.target = id
            assetCheck.running = true
        }
        function launch(id) {
            shownFor = id
            charProc.command = ["python3", "-I", root.appDir + "/character/character.py",
                "--assets", root.charactersDir + "/" + id,
                "--config", JSON.stringify((root.personas[id] || {}).character || {}),
                "--right", String(Math.round(panelRight)), "--bottom", "10"]
            charProc.running = true
        }
        function send(o) { if (charProc.running) charProc.write(JSON.stringify(o) + "\n") }
        function say(text) { if (text) send({ cmd: "say", text: text }) }
        // kind: idle | talk | tapHead | tapBody | pat | error
        function react(kind) { send({ cmd: "react", kind: kind }) }
    }
    // Debug: fake a tap ("head", "body") or a pat on the character
    function pokeCharacter(kind) { character.send({ cmd: "selftest", kind: kind }) }
    readonly property alias characterAvailable: character.available
    readonly property alias characterShown: charProc.running
    function showCharacter(on, panelRight) {
        character.wanted = on
        if (panelRight !== undefined) character.panelRight = panelRight
        character.sync()
    }

    Process {
        id: assetCheck
        property string target: ""
        command: ["bash", "-c", "ls \"$1\"/*.atlas >/dev/null 2>&1", "_", root.charactersDir + "/" + target]
        onExited: (code) => {
            character.available = code === 0
            if (code === 0 && character.wanted && root.personaId === target) character.launch(target)
        }
    }

    Process {
        id: charProc
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (l) => {
                let o; try { o = JSON.parse(l) } catch (e) { return }
                if (o.event === "ready") {
                    character.animations = o.animations || []
                    character.say(root.line("greet"))
                } else if (o.event === "tap") {
                    const kind = o.region === "head" ? "tapHead" : "tapBody"
                    character.react(kind); character.say(root.line(kind))
                } else if (o.event === "dizzy") {
                    character.say(root.line("dizzy"))
                } else if (o.event === "pat") {
                    character.react("pat"); character.say(root.line("pat"))
                } else if (o.event === "error") {
                    console.warn("assistant character:", o.message)
                }
            }
        }
        stderr: SplitParser { onRead: (l) => console.log("assistant character:", l) }
    }
}
