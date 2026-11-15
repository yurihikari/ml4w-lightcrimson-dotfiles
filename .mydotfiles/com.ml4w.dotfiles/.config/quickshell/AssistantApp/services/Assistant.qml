pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The assistant's brain: talks to the Claude CLI (`claude -p` with stream-json
// in and out, one long-running process per conversation), keeps the chat of
// each persona, and drives the optional character overlay (character/).
//
// Personas: the plain "assistant" ships with the app (personas/). Personal
// assistants are the user's own, made with the panel's form (or by hand) in
// ~/.local/share/ml4w-assistant/personas/<id>.json. Examples ship in
// examples/personas/ and only show up once fully set up: when their character
// files are in characters/<id>/ (and the user has no file of that id).
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
    readonly property string userPersonasDir: home + "/.local/share/ml4w-assistant/personas"
    readonly property string appDir: Quickshell.shellDir + "/AssistantApp"

    // ── Personas ───────────────────────────────────────────────────────────
    readonly property string examplesDir: appDir + "/examples/personas"
    readonly property var builtinIds: ["assistant"]
    property var userIds: []                    // the user's own files
    property var exampleIds: []                 // examples with their character set up
    readonly property var personaIds: builtinIds.concat(userIds, exampleIds)
    property var personas: ({})
    readonly property var personalPersonas: userIds.concat(exampleIds).filter(id => personas[id])
    function isExample(id) { return exampleIds.includes(id) }

    // "assistant" or "personal", and the personal assistant picked last
    // ("" while there is none yet)
    property string mode: "assistant"
    property string personalPersona: ""
    readonly property string personaId: mode === "personal" ? personalPersona : "assistant"
    readonly property var persona: personas[personaId] || ({ id: personaId, name: "", lines: {} })
    readonly property bool canChat: personaId !== "" && !!personas[personaId]

    // The system prompt: the persona's own, or one built from the form's fields
    function promptFor(p) {
        if (p.systemPrompt) return p.systemPrompt
        const call = (p.addressAs || "").trim()
        return "You are " + p.name + ", the user's personal assistant, living in their Linux desktop "
            + "(Hyprland, a Quickshell panel). Personality and way of speaking: " + (p.personality || "friendly and helpful") + ". "
            + (call ? "Address the user as \"" + call + "\". " : "")
            + "Stay fully in character, but your answers must stay correct, complete and genuinely useful: "
            + "give real code, commands and explanations, formatted in Markdown, with your personality around them. "
            + "Reply in the language the user writes in. You can search the web for recent or specific facts. "
            + "You cannot see the screen or run commands; when the user wants something done, give them the exact command. "
            + "If the user asks what you really are, answer honestly, still in character."
    }

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
        if (text === "" || busy || !canChat) return
        messagesModel.append({ role: "user", text: text, streaming: false })
        busy = true
        _turn++
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
        character.say(line("thinking"))     // until the first words arrive
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
            "--system-prompt", promptFor(persona),
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
        if (charProc.running && !speechTimer.running) speechTimer.start()
    }

    // ── The reply in the character's speech bubble ─────────────────────────
    // The whole reply as plain text (Markdown stripped, code left to the
    // panel), sent as it grows; the overlay types it out at its own pace.
    property int _turn: 0
    Timer { id: speechTimer; interval: 250; onTriggered: root._speak(false) }
    function _speak(final) {
        const n = messagesModel.count
        if (!n || messagesModel.get(n - 1).role !== "assistant") return
        const text = speechText(messagesModel.get(n - 1).text)
        if (text) character.send({ cmd: "speak", text: text, final: final, turn: _turn })
    }
    function speechText(md) {
        return md
            .replace(/```[\s\S]*?(```|$)/g, " (code in the panel) ")      // code blocks, even unfinished
            .replace(/`([^`]*)`/g, "$1")
            .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")                  // links and images
            .replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+[.)])\s+/gm, "")         // headings, quotes, list marks
            .replace(/^\s*\|?[-:| ]+\|[-:| ]*$/gm, "")                     // table rules
            .replace(/\|/g, " ")
            .replace(/(\*\*|__|\*|_|~~)(?=\S)([\s\S]*?\S)\1/g, "$2")       // bold, italics, strikethrough
            .replace(/\s+/g, " ")
            .trim()
    }

    function _finishTurn(errorText) {
        const i = _assistantIndex()
        if (i >= 0) messagesModel.setProperty(i, "streaming", false)
        if (errorText) messagesModel.append({ role: "note", text: errorText, streaming: false })
        busy = false; status = ""
        _save()
        idleTimer.restart()
        speechTimer.stop()
        if (!errorText) _speak(true)
        character.react(errorText ? "error" : "idle")
        if (errorText) character.say(line("error"))
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

    // An idle CLI holds a couple hundred MB: let it go after 10 minutes without
    // use. The next message starts it again and resumes the conversation.
    Timer {
        id: idleTimer
        interval: 10 * 60 * 1000
        onTriggered: if (!root.busy) root._kill()
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
        onStarted: { root._flush(); idleTimer.restart() }
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
        stateFile.setText(JSON.stringify({ mode: mode, personalPersona: personalPersona, sessions: sessions, model: model }, null, 2))
        historyFile.setText(JSON.stringify(_histories))
    }
    onModeChanged: _save()
    onPersonalPersonaChanged: _save()

    // Built-in personas ship next to this app; personal ones are the user's.
    // Files are watched, so editing one by hand applies on save.
    Instantiator {
        model: root.personaIds
        delegate: FileView {
            required property string modelData
            path: (root.builtinIds.includes(modelData) ? root.appDir + "/personas/"
                 : root.exampleIds.includes(modelData) ? root.examplesDir + "/"
                 : root.userPersonasDir + "/") + modelData + ".json"
            blockLoading: true
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    const d = JSON.parse(text())
                    d.id = modelData
                    const p = Object.assign({}, root.personas); p[modelData] = d; root.personas = p
                } catch (e) { console.warn("assistant: bad persona", modelData, e) }
            }
        }
    }

    // ── Personal assistants: list, save, delete, write their lines ─────────
    function refreshPersonas() { lister.running = true }
    Process {
        id: lister
        // "user:<id>" for the user's files, "example:<id>" for examples whose
        // character files are present and that the user has no file for
        command: ["sh", "-c", "mkdir -p \"$1\"; "
            + "for f in \"$1\"/*.json; do [ -e \"$f\" ] && echo \"user:$(basename \"$f\" .json)\"; done; "
            + "for f in \"$2\"/*.json; do [ -e \"$f\" ] || continue; id=$(basename \"$f\" .json); "
            + "[ -e \"$1/$id.json\" ] && continue; ls \"$3/$id\"/*.atlas >/dev/null 2>&1 && echo \"example:$id\"; done",
            "_", root.userPersonasDir, root.examplesDir, root.charactersDir]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.split("\n")
                const user = rows.filter(l => l.startsWith("user:")).map(l => l.slice(5)).filter(id => !root.builtinIds.includes(id))
                const examples = rows.filter(l => l.startsWith("example:")).map(l => l.slice(8)).filter(id => !root.builtinIds.includes(id))
                const ids = user.concat(examples)
                const p = Object.assign({}, root.personas)
                for (const id of Object.keys(p)) if (!root.builtinIds.includes(id) && !ids.includes(id)) delete p[id]
                root.personas = p
                root.userIds = user
                root.exampleIds = examples
                if (root.personalPersona !== "" && !ids.includes(root.personalPersona)) root.personalPersona = ids[0] || ""
                if (root.personalPersona === "" && ids.length) root.personalPersona = ids[0]
                if (root._selectAfterList !== "" && ids.includes(root._selectAfterList)) {
                    root.personalPersona = root._selectAfterList; root.mode = "personal"
                }
                root._selectAfterList = ""
            }
        }
    }
    property string _selectAfterList: ""

    function slug(name) {
        let s = (name || "").toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
            .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
        return s || "assistant"
    }

    // Save a personal assistant from the form. `id` empty: a new one.
    // Fields: name, icon, tagline, addressAs, personality. Everything else in
    // an existing file (lines, character settings, a hand-written
    // systemPrompt) is kept. New ones get their lines written by Claude.
    function savePersona(id, fields) {
        const isNew = !id
        if (isNew) {
            id = slug(fields.name)
            let n = 2
            while (builtinIds.includes(id) || userIds.includes(id) || exampleIds.includes(id)) id = slug(fields.name) + "-" + n++
        }
        const old = personas[id] || {}
        const d = Object.assign({}, old, {
            name: fields.name.trim(),
            icon: (fields.icon || "").trim() || fields.name.trim().charAt(0).toUpperCase(),
            tagline: (fields.tagline || "").trim(),
            addressAs: (fields.addressAs || "").trim(),
            personality: (fields.personality || "").trim()
        })
        delete d.id
        if (!d.lines) d.lines = {}
        if (!d.character) d.character = { animations: {} }
        _writePersona(id, d)
        _selectAfterList = id
        if (isNew || !Object.keys(d.lines).length) draftLines(id, d)
        // The running CLI has the old prompt
        if (claude.running && _runningPersona === id) _kill()
        return id
    }
    function _writePersona(id, d) {
        writer.command = ["sh", "-c", "mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/$3.json.tmp\" && mv \"$1/$3.json.tmp\" \"$1/$3.json\"",
            "_", userPersonasDir, JSON.stringify(d, null, 4), id]
        writer.running = true
    }
    Process { id: writer; onExited: root.refreshPersonas() }

    function deletePersona(id) {
        if (!userIds.includes(id)) return
        if (claude.running && _runningPersona === id) _kill()
        const h = Object.assign({}, _histories); delete h[id]; _histories = h
        const s = Object.assign({}, sessions); delete s[id]; sessions = s
        if (_shownPersona === id) _shownPersona = ""
        remover.command = ["rm", "-f", "--", userPersonasDir + "/" + id + ".json"]
        remover.running = true
    }
    Process { id: remover; onExited: { root.refreshPersonas(); root._save() } }

    function personaFile(id) { return (isExample(id) ? examplesDir : userPersonasDir) + "/" + id + ".json" }

    // Claude writes the assistant's short in-character lines (greetings, what
    // they say when clicked or patted…) from its name and personality.
    property string drafting: ""        // id whose lines are being written
    function draftLines(id, d) {
        if (drafter.running) return
        drafting = id
        drafter.targetId = id
        drafter.persona = d
        const ask = "Write short in-character lines for a desktop assistant character.\n"
            + "Name: " + d.name + "\nPersonality and way of speaking: " + (d.personality || "friendly") + "\n"
            + (d.addressAs ? "They call the user: " + d.addressAs + "\n" : "")
            + "Return ONLY a JSON object, no prose, no code fence, with these keys, each an array of 3 or 4 lines "
            + "of at most 90 characters, written in the language of the personality description:\n"
            + "greet (when the user opens the panel), tapHead (clicked on the head), tapBody (clicked on the body), "
            + "pat (getting head pats), dizzy (clicked too many times), thinking (while preparing an answer, 2 lines), "
            + "error (something went wrong, 2 lines)."
        drafter.command = ["claude", "-p", ask, "--output-format", "json", "--tools", "",
            "--setting-sources", "", "--strict-mcp-config"]
        drafter.running = true
    }
    Process {
        id: drafter
        property string targetId: ""
        property var persona: ({})
        workingDirectory: root.stateDir
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = null
                try {
                    const r = JSON.parse(this.text).result || ""
                    const m = r.match(/\{[\s\S]*\}/)
                    lines = m ? JSON.parse(m[0]) : null
                } catch (e) { console.warn("assistant: could not read drafted lines", e) }
                const id = drafter.targetId
                if (lines && (root.userIds.includes(id) || root.exampleIds.includes(id))) {
                    const d = Object.assign({}, root.personas[id] || drafter.persona)
                    delete d.id
                    d.lines = Object.assign({}, d.lines || {}, lines)
                    root._writePersona(id, d)
                }
                root.drafting = ""
            }
        }
        onExited: (code) => { if (code !== 0) root.drafting = "" }
    }

    Component.onCompleted: {
        try { _histories = JSON.parse(historyFile.text() || "{}") } catch (e) { _histories = {} }
        try {
            const s = JSON.parse(stateFile.text() || "{}")
            if (s.mode) mode = s.mode === "special" ? "personal" : s.mode       // the old name
            if (s.personalPersona || s.specialPersona) personalPersona = s.personalPersona || s.specialPersona
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
            const want = wanted && root.mode === "personal" && root.personaId !== ""
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
