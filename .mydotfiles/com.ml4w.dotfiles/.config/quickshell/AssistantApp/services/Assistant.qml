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

    // ── Second brain (~/brain) ─────────────────────────────────────────────
    // A notes folder shared by every assistant: its context (protocol, profile,
    // tasks, recent digests and conversations) is added to the prompt when the
    // CLI starts, and every exchange is logged to
    // ~/brain/conversations/<persona>/<date>.md. All of it lives in
    // ~/brain/tools/brain.py; without that file nothing changes.
    readonly property string brainDir: home + "/brain"
    readonly property string brainTool: brainDir + "/tools/brain.py"
    property string brainContext: ""

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
            + "Reply in the language the user writes in. You can search the web for recent or specific facts, "
            + "and look into and act on their computer as described below. "
            + "If the user asks what you really are, answer honestly, still in character."
    }

    // ── What the assistants can do on the computer ─────────────────────────
    // Tools: the web, reading files, running commands, editing files. The
    // read-only commands below (and file reads) run right away; anything else
    // stops and asks in the panel (approvals). Private places are off limits,
    // for commands too (Claude Code applies Read rules to them as well).
    readonly property string toolsDir: appDir + "/tools"
    readonly property var _hyprQueries: ["monitors", "clients", "workspaces", "activewindow", "activeworkspace",
        "devices", "layers", "version", "getoption", "binds", "systeminfo", "cursorpos", "globalshortcuts",
        "rollinglog", "layouts", "decorations", "animations", "instances"]
    readonly property var safeCommands: [
        // logs and services
        "journalctl:*", "coredumpctl list:*", "coredumpctl info:*", "systemd-analyze:*",
        "systemctl status:*", "systemctl show:*", "systemctl cat:*", "systemctl list-units:*",
        "systemctl list-unit-files:*", "systemctl list-timers:*", "systemctl is-active:*",
        "systemctl is-enabled:*", "systemctl is-failed:*", "systemctl --failed:*",
        "systemctl --user status:*", "systemctl --user show:*", "systemctl --user cat:*",
        "systemctl --user list-units:*", "systemctl --user list-unit-files:*", "systemctl --user list-timers:*",
        "systemctl --user is-active:*", "systemctl --user is-enabled:*", "systemctl --user is-failed:*",
        "systemctl --user --failed:*", "loginctl list-sessions:*", "loginctl show-session:*",
        // hardware and resources
        "ps:*", "pgrep:*", "top -b:*", "free:*", "df:*", "du:*", "lsblk:*", "findmnt:*", "lspci:*",
        "lsusb:*", "lsmod:*", "lscpu:*", "lsof:*", "uname:*", "uptime:*", "sensors:*", "upower:*",
        "hostnamectl", "hostnamectl status:*", "timedatectl", "timedatectl status:*", "localectl", "localectl status:*",
        "powerprofilesctl get:*", "powerprofilesctl list:*", "brightnessctl info:*", "brightnessctl get:*",
        "glxinfo -B:*", "vulkaninfo --summary:*", "vainfo:*", "fastfetch:*",
        // network, sound, bluetooth, media
        "ip addr:*", "ip a:*", "ip route:*", "ip r:*", "ip link show:*", "ip -br addr:*", "ip -br a:*",
        "nmcli general status:*", "nmcli device status:*", "nmcli device show:*", "nmcli connection show:*",
        "resolvectl status:*", "resolvectl query:*", "ss:*", "ping -c:*",
        "pactl info:*", "pactl list:*", "pactl get-default-sink:*", "pactl get-default-source:*",
        "pactl get-sink-volume:*", "pactl get-sink-mute:*", "wpctl status:*", "wpctl inspect:*", "wpctl get-volume:*",
        "bluetoothctl show:*", "bluetoothctl devices:*", "bluetoothctl info:*",
        "playerctl status:*", "playerctl metadata:*", "playerctl -l:*",
        // packages
        "pacman -Q:*", "pacman -Qi:*", "pacman -Ql:*", "pacman -Qo:*", "pacman -Qs:*", "pacman -Qe:*",
        "pacman -Qm:*", "pacman -Qdt:*", "pacman -Si:*", "pacman -Ss:*", "checkupdates:*",
        // looking at files and text
        "ls:*", "cat:*", "head:*", "tail:*", "wc:*", "file:*", "stat:*", "which:*", "whereis:*", "type:*",
        "grep:*", "rg:*", "sort:*", "uniq:*", "cut:*", "tr:*", "jq:*", "column:*", "date:*", "id:*",
        "whoami:*", "groups:*", "locale:*", "fc-list:*", "fc-match:*", "xdg-mime query:*",
        "gsettings get:*", "gsettings list-recursively:*", "git status:*", "git log:*", "git diff:*", "git show:*",
        // the desktop: Quickshell's popups and panels, Hyprland's state, the screen
        "qs ipc show:*", "qs ipc call:*", "qs log:*", toolsDir + "/screenshot:*"
    ].concat(_hyprQueries.map(q => "hyprctl " + q + ":*"), _hyprQueries.map(q => "hyprctl -j " + q + ":*"))
    readonly property var privatePaths: ["~/.ssh/**", "~/.gnupg/**", "~/.password-store/**",
        "~/.local/share/keyrings/**", "~/.local/share/kwalletd/**", "~/.config/BraveSoftware/**",
        "~/.mozilla/**", "~/.config/chromium/**", "~/.config/google-chrome/**", "~/.config/vesktop/**",
        "~/.config/discord/**", "~/.claude/**", "~/.claude.json", "~/.config/gh/**", "~/.git-credentials",
        "~/.netrc", "~/.aws/**", "~/.kube/**", "~/.docker/**", "~/.config/rclone/**",
        // (absolute paths take a double slash in permission rules; a single
        // one is relative to the project)
        "//etc/shadow", "//etc/NetworkManager/system-connections/**"]
    // Trusted: commands and file edits run without asking, except the
    // sensitive ones in askCommands (and anything outside home). false: only
    // read-only commands and writes in ~/brain run without asking.
    readonly property bool trusted: true
    readonly property var askCommands: [
        // deleting, wiping, permissions
        "rm:*", "rmdir:*", "shred:*", "dd:*", "mkfs:*", "wipefs:*", "fdisk:*", "parted:*", "truncate:*",
        "chmod:*", "chown:*", "find * -delete*", "find * -exec rm*",
        // privileges, packages
        "su:*", "pkexec:*", "doas:*", "run0:*",
        "pacman -S:*", "pacman -R:*", "pacman -U:*", "pacman -D:*", "yay:*", "paru:*",
        "flatpak install:*", "flatpak uninstall:*", "flatpak remove:*", "pip install:*", "pipx install:*",
        "npm install -g:*", "npm i -g:*",
        // services, power, processes
        "reboot:*", "poweroff:*", "shutdown:*", "halt:*", "loginctl terminate-session:*", "hyprctl dispatch exit:*",
        "kill:*", "pkill:*", "killall:*", "crontab:*",
        // git history, network out, mail
        "git push:*", "git reset --hard:*", "git clean:*", "git checkout --:*", "git restore:*", "git rebase:*",
        "git branch -D:*", "git stash drop:*", "git filter-branch:*",
        "ssh:*", "scp:*", "sftp:*", "rsync:*", "curl:*", "wget:*", "nc:*",
        "mail:*", "sendmail:*", "msmtp:*", "neomutt:*", "mutt:*", "mail-apply:*",
        "nmcli connection delete:*", "nmcli connection modify:*", "nmcli connection down:*",
        "nmcli radio:*", "nmcli device disconnect:*", "bluetoothctl remove:*"
    ].concat(["start", "stop", "restart", "reload", "enable", "disable", "mask", "unmask", "kill", "isolate"]
        .map(v => "systemctl " + v + ":*"),
        ["start", "stop", "restart", "reload", "enable", "disable", "mask", "unmask", "kill", "isolate"]
        .map(v => "systemctl --user " + v + ":*"))
    function _allowRules() {
        const brain = ["Edit(~/brain/**)", "Write(~/brain/**)", "Bash(python3 " + brainTool + ":*)",
            "Bash(python3 -I " + brainTool + ":*)", "Bash(git -C " + brainDir + ":*)"]
        return ["WebSearch", "WebFetch", "Read", "Grep", "Glob"].concat(safeCommands.map(c => "Bash(" + c + ")"), brain,
            trusted ? ["Bash", "Edit(~/**)", "Write(~/**)"] : [], _mcpPerms("allow"))
    }
    function _denyRules() {
        return privatePaths.map(p => "Read(" + p + ")")
            // Edit rules cover the Write tool too (Write(...) rules never match)
            .concat(privatePaths.map(p => "Edit(" + p + ")"))
            .concat(["Bash(sudo:*)", "Bash(qs ipc call assistant:*)"])   // no terminal for a password; not itself
    }
    // "ask" rules beat "allow" ones: passed as flag settings (there is no CLI flag for them)
    function _settings() {
        return JSON.stringify({ permissions: { ask: (trusted ? askCommands.map(c => "Bash(" + c + ")") : []).concat(_mcpPerms("ask")) } })
    }

    // Optional MCP servers for the panel: ~/.config/ml4w-assistant/mcp.json (Claude Code format), and
    // their permission rules in mcp-permissions.json: {"allow": [read tools], "ask": [write tools]}
    readonly property string mcpConfig: home + "/.config/ml4w-assistant/mcp.json"
    FileView { id: mcpFile; path: root.mcpConfig; blockLoading: true; printErrors: false }
    FileView { id: mcpPermFile; path: root.home + "/.config/ml4w-assistant/mcp-permissions.json"; blockLoading: true; printErrors: false }
    function _mcpPerms(kind) {
        try { return JSON.parse(mcpPermFile.text() || "{}")[kind] || [] } catch (e) { return [] }
    }

    // Quickshell's IPC targets (popups, panels…), for the prompt
    property string ipcTargets: ""
    Process {
        id: ipcLister
        command: ["qs", "ipc", "show"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                let cur = null
                for (const l of this.text.split("\n")) {
                    const t = l.match(/^target (\S+)/)
                    if (t) { cur = { name: t[1], fns: [] }; out.push(cur); continue }
                    const f = l.match(/^\s+function (\w+)\(([^)]*)\)/)
                    if (f && cur) cur.fns.push(f[1] + "(" + f[2].replace(/:\s*\w+/g, "") + ")")
                }
                root.ipcTargets = out.filter(t => t.name !== "assistant")
                    .map(t => "- " + t.name + ": " + t.fns.join(", ")).join("\n")
            }
        }
    }

    function capabilities() {
        return "\n\n## Your access to this computer\n"
            + "You can look into the user's system yourself: Read, Grep and Glob for files (images too), Bash for commands, "
            + "Edit and Write to change files, WebSearch and WebFetch for the web. "
            + (trusted
                ? "The user trusts you to act on your own: file reads, file edits in their home and most commands run right "
                  + "away, without asking. Sensitive actions (deleting files, installing or removing packages, starting or "
                  + "stopping services, killing processes, git push/reset, network transfers like curl/ssh, sending mail, "
                  + "power actions) are shown to the user in the panel with Allow / Deny buttons: just call the tool and they "
                  + "decide. Don't dodge that with an equivalent command (a script, find -delete, python…): when an action is "
                  + "destructive or irreversible, use the command that asks. Before overwriting important configs outside "
                  + "~/brain, make a .bak copy. "
                : "File reads, read-only commands (journalctl, systemctl status, ps, lsblk, pacman -Q, hyprctl queries…) "
                  + "and writes in ~/brain run right away. Anything else (changing a file, a command that changes something) "
                  + "is shown to the user in the panel with Allow / Deny buttons: just call the tool and they decide. ")
            + "If they deny it, accept that and don't try another way to do the same thing. Private places (SSH and GPG keys, password stores, browser profiles, credentials) are off "
            + "limits; don't try to get around that. sudo can't work here (there's no terminal for a password): when "
            + "something needs root, give the user the exact command to run in a terminal.\n"
            + "When the user has a problem, investigate first (logs, status, configs), then explain what you found and "
            + "what you'd do. Keep tool use focused, and tell the user what you're checking.\n\n"
            + "## The desktop\n"
            + "Hyprland, with a Quickshell shell (bar, popups, sidebar, settings, this assistant). Open, close or toggle its "
            + "popups and panels with `qs ipc call <target> <function> [args]`; that runs without asking, so do it when the "
            + "user asks you to show or open something. Opening another popup doesn't close you: your panel floats next to it. "
            + "Never call the `assistant` target (that's you). Targets:\n" + ipcTargets + "\n"
            + "To see the screen (only when the user asks you to look at or identify something on it), run `"
            + toolsDir + "/screenshot` (the focused monitor) or `" + toolsDir + "/screenshot window` (the focused window): "
            + "it prints the path of a PNG, which you then Read.\n\n"
            + "## Formatting\n"
            + "The panel shows each fenced code block in a box with a Copy button, and long lines wrap. Put every "
            + "command, path or snippet the user may run or paste in its own fenced block with its language "
            + "(```bash), one command per block unless they must run together, never in plain prose. "
            + "The user can attach images (you see them) and files (you get their paths: Read them).\n"
            + _brainSection()
    }

    function _brainSection() {
        if (brainContext.trim() === "") return ""
        return "\n## The user's second brain (~/brain)\n"
            + "The user's second brain, shared with every other assistant. This conversation is logged automatically "
            + "to ~/brain/conversations/" + personaId + "/. Follow the protocol below, and use the context to remember "
            + "what the user said before (to you or to another assistant). Writing in ~/brain never needs approval.\n\n"
            + brainContext + "\n"
    }

    function line(kind) {
        const l = (persona.lines || {})[kind] || []
        return l.length ? l[Math.floor(Math.random() * l.length)] : ""
    }

    // ── Conversation ───────────────────────────────────────────────────────
    // role: "user" | "assistant" | "note" (errors, "stopped") | "tool:<name>"
    // (a tool it used; "tool:<name>:err" when it failed or was denied), with
    // the command or file as the text. `files`: the paths attached to a user
    // message (a JSON list; "" for none)
    ListModel { id: messagesModel }

    // ── Attachments for the next message ───────────────────────────────────
    // Images go to Claude as images (tools/encode-images scales big ones
    // down); other files as their paths, which it reads with Read. Pasted
    // images are saved in attachDir.
    readonly property string attachDir: stateDir + "/attachments"
    ListModel { id: attachModel }           // path
    readonly property alias attachments: attachModel
    function isImage(path) { return /\.(png|jpe?g|gif|webp|bmp)$/i.test(path) }
    function attach(path) {
        path = (path || "").replace(/^file:\/\//, "")
        if (path === "") return
        for (let i = 0; i < attachModel.count; i++) if (attachModel.get(i).path === path) return
        attachModel.append({ path: path })
    }
    function detachFile(index) { if (index >= 0 && index < attachModel.count) attachModel.remove(index) }

    // ── Approvals: what it wants to do that isn't read-only ────────────────
    // One entry per can_use_tool request from the CLI, answered from the panel.
    // requestId, tool, summary (the command or file), detail (Claude's own
    // description, or what an edit changes), rule (the "always allow" rule the
    // CLI suggests, as JSON; "" when there is none)
    ListModel { id: approvalsModel }
    readonly property alias approvals: approvalsModel
    signal approvalRequested()

    function answer(requestId, allow, always) {
        for (let i = 0; i < approvalsModel.count; i++) {
            const a = approvalsModel.get(i)
            if (a.requestId !== requestId) continue
            let response
            if (allow) {
                response = { behavior: "allow", updatedInput: JSON.parse(a.input) }
                // "Always": the CLI's own suggestion, kept for this chat only
                if (always && a.rule !== "")
                    response.updatedPermissions = JSON.parse(a.rule).map(s => Object.assign({}, s, { destination: "session" }))
            } else {
                response = { behavior: "deny", message: "The user declined this in the panel." }
            }
            claude.write(JSON.stringify({ type: "control_response",
                response: { subtype: "success", request_id: requestId, response: response } }) + "\n")
            approvalsModel.remove(i)
            status = approvalsModel.count ? "Waiting for your OK…" : (allow ? "Working…" : "")
            return
        }
    }

    // How a tool use reads in the panel: the command, the file, the search
    function toolSummary(name, input) {
        const t = p => (p || "").replace(home, "~")
        input = input || {}
        switch (name) {
        case "Bash": return input.command || ""
        case "Read": return t(input.file_path)
        case "Grep": return "\"" + (input.pattern || "") + "\" in " + (t(input.path) || "~")
        case "Glob": return (input.pattern || "") + (input.path ? " in " + t(input.path) : "")
        case "Edit": case "Write": case "MultiEdit": return t(input.file_path)
        case "WebSearch": return input.query || ""
        case "WebFetch": return input.url || ""
        default: return JSON.stringify(input).slice(0, 200)
        }
    }
    function _toolDetail(name, input) {
        const cut = (s, n) => (s || "").length > n ? s.slice(0, n) + "…" : (s || "")
        if (name === "Edit") return "− " + cut(input.old_string, 300) + "\n+ " + cut(input.new_string, 300)
        if (name === "Write") return cut(input.content, 500)
        return ""
    }
    property var _toolRows: ({})     // tool_use id -> row in messagesModel
    readonly property alias messages: messagesModel
    property bool busy: false        // a reply is being generated
    property string status: ""       // "Searching the web…" and such
    property var sessions: ({})      // persona id -> Claude session id
    property string model: ""        // empty: the CLI's default
    property string effort: "high"   // reasoning effort: low, medium, high, xhigh, max ("" = CLI default)
    // The panel's sizes (dockWidth, floatWidth, floatHeight), kept in state.json
    property var ui: ({})
    function setUi(values) { ui = Object.assign({}, ui, values); _save() }

    function send(text) {
        text = text.trim()
        if (/^\/\S/.test(text) && attachModel.count === 0 && _panelCommand(text)) return
        const files = []
        for (let i = 0; i < attachModel.count; i++) files.push(attachModel.get(i).path)
        if ((text === "" && !files.length) || busy || !canChat) return
        if (remoteHere) { _sendRemote(text, files); return }
        messagesModel.append({ role: "user", text: text, streaming: false, files: files.length ? JSON.stringify(files) : "" })
        attachModel.clear()
        busy = true
        _turn++
        status = line("thinking") || "Thinking…"
        _turnStarted = false
        // Attachments: images as images, other files as paths to Read
        const images = files.filter(f => isImage(f)), others = files.filter(f => !isImage(f))
        let body = text || "(See the attachments.)"
        if (others.length) body += "\n\n[Attached files, read them with the Read tool: " + others.join(", ") + "]"
        if (images.length) body += "\n\n[Attached image" + (images.length > 1 ? "s" : "") + " (shown above): " + images.join(", ") + "]"
        if (images.length) {
            _encoded = []
            encoder.text = body
            encoder.command = [toolsDir + "/encode-images"].concat(images)
            encoder.running = true
        } else {
            _queueUser([{ type: "text", text: body }])
        }
        _save()
        character.react("talk")
        character.say(line("thinking"))     // until the first words arrive
    }

    // A user message for the CLI (started if needed)
    function _queueUser(content) {
        _pending.push(JSON.stringify({ type: "user", message: { role: "user", content: content } }) + "\n")
        if (!claude.running) _start()
        else if (!_killing) _flush()
        // else: the old CLI is exiting (persona switch); onExited starts the new one
    }
    property var _encoded: []
    property bool _encodeCancelled: false
    Process {
        id: encoder
        property string text: ""
        stdout: SplitParser {
            onRead: (l) => {
                let d; try { d = JSON.parse(l) } catch (e) { return }
                if (d.data) root._encoded = root._encoded.concat([{ type: "image",
                    source: { type: "base64", media_type: d.media_type, data: d.data } }])
                else console.warn("assistant: could not attach", d.path, d.error)
            }
        }
        onExited: {
            if (root._encodeCancelled) { root._encodeCancelled = false; return }
            root._queueUser(root._encoded.concat([{ type: "text", text: encoder.text }]))
            root._encoded = []
        }
    }

    function stop() {
        if (remoteHere) { _remoteKeys(["Escape"]); return }   // interrupt it there
        if (!busy) return
        if (encoder.running) {              // still preparing the images: nothing sent yet
            _encodeCancelled = true
            encoder.running = false
            _finishTurn("Stopped.")
            return
        }
        _stopped = true
        _kill()
    }

    function newChat() {
        if (remoteHere) { _info("This conversation is on Remote Control: /rc brings it back here first."); return }
        _pending = []
        attachModel.clear()
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
        approvalsModel.clear()
        if (claude.running) { _killing = true; claude.running = false }
    }

    function _flush() {
        if (!claude.running) return
        for (const l of _pending) claude.write(l)
        _pending = []
    }

    // Fetch the brain's context first (brain.py context), then start the CLI
    function _start() {
        if (brainLoader.running) return            // _launch follows when it's done
        brainLoader.command = ["sh", "-c", "[ -f \"$1\" ] && python3 -I \"$1\" context \"$2\" 2>/dev/null; true",
            "_", brainTool, personaId]
        brainLoader.running = true
    }
    Process {
        id: brainLoader
        stdout: StdioCollector {
            onStreamFinished: {
                root.brainContext = this.text
                if (!claude.running || root._launchRemote) root._launch()
            }
        }
    }

    // What both the panel's CLI and the Remote Control session get: the
    // persona's prompt, the tools and their permission rules, the settings
    function _sharedArgs() {
        const args = [
            "--system-prompt", promptFor(persona),
            "--append-system-prompt", capabilities(),
            // The web, files and commands: read-only things run right away,
            // anything else is asked in the panel (the CLI sends a
            // can_use_tool request, see _handle)
            "--tools", "WebSearch,WebFetch,Bash,Read,Grep,Glob,Edit,Write",
            "--add-dir", home]
            .concat(["--allowedTools"], _allowRules(), ["--disallowedTools"], _denyRules(), [
            // Skip the user's hooks, plugins and MCP servers (faster, isolated)
            "--setting-sources", "", "--strict-mcp-config",
            "--settings", _settings(),
            // The prompt carries the brain's context, rebuilt at each start:
            // don't let a resumed conversation reuse the old one
            "--system-prompt-snapshot", "off"])
        if ((mcpFile.text() || "").trim() !== "") args.push("--mcp-config", mcpConfig)
        if (model !== "") args.push("--model", model)
        if (effort !== "") args.push("--effort", effort)
        return args
    }

    function _launch() {
        if (_launchRemote) { _launchRemote = false; _remoteLaunch(); return }
        const args = ["claude", "-p",
            "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--permission-prompt-tool", "stdio"].concat(_sharedArgs())
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
        if (i < 0) { messagesModel.append({ role: "assistant", text: "", streaming: true, files: "" }); i = messagesModel.count - 1 }
        messagesModel.setProperty(i, "text", messagesModel.get(i).text + t)
        if (charProc.running && !speechTimer.running) speechTimer.start()
    }

    // ── Slash commands ─────────────────────────────────────────────────────
    // The panel's own (/rc, /new, /help) run here; the others (/compact,
    // /context, /model <name>, /usage…) go to Claude Code like a message, and
    // their output shows as a reply. cliCommands is what the CLI reported.
    property var cliCommands: ["compact", "context", "model", "usage", "cost", "init", "review"]
    readonly property var panelCommands: [
        { name: "rc", hint: "Remote Control: continue on claude.ai or the Claude app (again: bring it back)" },
        { name: "remote-control", hint: "Same as /rc" },
        { name: "new", hint: "New chat" },
        { name: "help", hint: "What you can type here" }]
    property var _streamed: ({})            // message id -> its text streamed
    property string _streamingMsg: ""
    function commandSuggestions(prefix) {
        prefix = (prefix || "").toLowerCase()
        const out = panelCommands.filter(c => c.name.startsWith(prefix))
        for (const c of cliCommands)
            if (c.startsWith(prefix) && !out.some(o => o.name === c)) out.push({ name: c, hint: "Claude Code" })
        return out.slice(0, 8)
    }
    function _info(text) {
        messagesModel.append({ role: "info", text: text, streaming: false, files: "" })
        _save()
    }
    // true when the panel handled it
    function _panelCommand(text) {
        const m = text.match(/^\/(\S+)\s*(.*)$/)
        const cmd = m[1].toLowerCase(), arg = m[2].trim()
        if (cmd === "rc" || cmd === "remote-control") {
            if (remote && remotePersona === personaId) stopRemote()
            else startRemote(arg)
            return true
        }
        if (cmd === "new" || cmd === "clear") { newChat(); return true }
        if (cmd === "help") {
            _info("**/rc** Remote Control: continue this conversation on claude.ai/code or in the Claude app; "
                + "/rc again (or the button) brings it back here, with what was said there.  \n"
                + "**/new** a new chat.  \n"
                + "Claude Code's own: " + cliCommands.map(c => "/" + c).join(", ") + ".")
            return true
        }
        // Claude Code's own commands go to the Remote Control session then
        if (remoteHere) { _sendRemote(text, []); return true }
        return false
    }

    // ── Remote Control (/rc) ───────────────────────────────────────────────
    // Claude Code only offers Remote Control in its interactive interface, so
    // /rc hands the conversation over to one, run in a tmux session nobody
    // sees (tools/remote-control) with the same prompt, tools and permission
    // rules as here, resuming the same session. The panel's own CLI stops
    // meanwhile (one process per conversation). Coming back (/rc or the
    // button, or ending it remotely) brings it back here.
    // Meanwhile the panel stays a window onto it: what's said on either side
    // shows up here as it happens (tools/session-turns --follow reads the
    // conversation's file), messages typed here are typed into the session,
    // and its approval prompts can be answered here (Enter / Esc) as well as
    // remotely; its screen is read every second for that and for "working".
    property bool remote: false             // a Remote Control session runs
    property bool remoteStarting: false
    property string remoteUrl: ""
    property string remotePersona: ""
    property real remoteSince: 0            // when it started (ms), for the import
    readonly property bool remoteHere: (remote || remoteStarting) && remotePersona === personaId
    property bool _launchRemote: false
    property bool remoteWorking: false
    property string remoteAsk: ""           // an approval prompt waiting there ("" none)
    readonly property string remoteStatus: !remoteHere ? "" : remoteAsk !== "" ? "Waiting for your OK"
        : remoteWorking ? "Working (Remote Control)…" : ""
    property real remoteSeen: 0             // the newest message shown (ms), to catch up from
    property var _echoes: []                // messages sent from here, shown already

    // A message typed here: into the session (pasted, so line breaks stay)
    function _sendRemote(text, files) {
        let body = text
        if (files.length) body += "\n\n[Attached files, read them with the Read tool: " + files.join(", ") + "]"
        if (body.trim() === "") return
        messagesModel.append({ role: "user", text: text, streaming: false, files: files.length ? JSON.stringify(files) : "" })
        attachModel.clear()
        _echoes = _echoes.concat([body.trim()])
        _turn++
        _save()
        remoteSend.command = [toolsDir + "/remote-control", "send", body]
        remoteSend.running = true
    }
    Process {
        id: remoteSend
        onExited: (code) => { if (code !== 0) root._info("Couldn't send that to the Remote Control session.") }
    }
    function _remoteKeys(keys) {
        remoteKeyProc.command = [toolsDir + "/remote-control", "keys"].concat(keys)
        remoteKeyProc.running = true
    }
    Process { id: remoteKeyProc }
    // Answer its approval prompt from here: Enter picks "Yes", Esc cancels
    function remoteAnswer(allow) {
        if (remoteAsk === "") return
        remoteAsk = ""
        _remoteKeys([allow ? "Enter" : "Escape"])
    }

    // Live: each message as it's written to the conversation's file
    function _follow() {
        const sid = sessions[remotePersona]
        if (!sid) return
        remoteFollow.command = [toolsDir + "/session-turns", "--follow", sid, String(Math.floor(remoteSeen > 0 ? remoteSeen + 1 : remoteSince))]
        remoteFollow.running = true
    }
    Process {
        id: remoteFollow
        stdout: SplitParser { onRead: (l) => { let d; try { d = JSON.parse(l) } catch (e) { return }; root._mirror(d) } }
    }
    function _mirror(d) {
        if (d.ts) remoteSeen = Math.max(remoteSeen, d.ts)
        let row
        if (d.role === "user") {
            const i = _echoes.indexOf(d.text.trim())
            if (i >= 0) { const e = _echoes.slice(); e.splice(i, 1); _echoes = e; return }   // sent from here
            row = { role: "user", text: d.text, streaming: false, files: "" }
            if (remotePersona === personaId) _turn++
        } else if (d.role === "assistant") {
            row = { role: "assistant", text: d.text, streaming: false, files: "" }
        } else {
            row = { role: d.role, text: toolSummary(d.role.slice(5), d.input), streaming: false, files: "" }
        }
        if (remotePersona === personaId) {
            messagesModel.append(row)
            if (row.role === "assistant") _speak(true)
        } else {
            const h = Object.assign({}, _histories)
            h[remotePersona] = (h[remotePersona] || []).concat([{ role: row.role, text: row.text }])
            _histories = h
        }
        _save()
    }

    // Its screen: working, or waiting for an approval
    Timer {
        interval: 1000; repeat: true
        running: root.remote
        onTriggered: if (!remoteScreen.running) remoteScreen.running = true
    }
    Process {
        id: remoteScreen
        command: [root.toolsDir + "/remote-control", "screen"]
        stdout: StdioCollector { onStreamFinished: root._readScreen(this.text) }
    }
    function _readScreen(t) {
        const lines = t.split("\n")
        remoteWorking = /esc to interrupt/i.test(t)
        const q = lines.findIndex(l => /Do you want to /.test(l))
        if (q < 0) { remoteAsk = ""; return }
        // What it asks about: from the last full-width rule down to the question
        let a = q - 1
        while (a > 0 && !/^\s*─{8,}/.test(lines[a])) a--
        const body = lines.slice(a + 1, q)
            .filter(l => !/^\s*Tip:/.test(l) && !/^\s*╌/.test(l))
            .map(l => l.replace(/^\s*│\s?/, "").trim()).filter(l => l !== "")
        remoteAsk = body.concat([lines[q].trim()]).join("\n")
    }

    function startRemote(name) {
        if (remote || remoteStarting) {
            _info("Remote Control already runs for " + ((personas[remotePersona] || {}).name || remotePersona) + ": /rc there ends it.")
            return
        }
        if (busy) { _info("Wait for the reply to finish, then /rc again."); return }
        if (!canChat) return
        remoteStarting = true
        remotePersona = personaId
        remoteName = name || persona.name || "Assistant"
        status = "Starting Remote Control…"
        _pending = []
        if (claude.running) { _kill(); return }  // onExited carries on
        _launchRemote = true
        _start()                                // fresh brain context, then _remoteLaunch
    }
    property string remoteName: ""
    function _uuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 3 | 8)).toString(16)
        })
    }
    function _remoteLaunch() {
        const args = ["claude"].concat(_sharedArgs(), ["--permission-mode", "default", "--remote-control", remoteName])
        let sid = sessions[personaId]
        if (sid) args.push("--resume", sid)
        else {
            sid = _uuid()
            args.push("--session-id", sid)
            const s = Object.assign({}, sessions); s[personaId] = sid; sessions = s
        }
        remoteSince = Date.now()
        remoteArgsFile.setText(JSON.stringify(args))
    }
    FileView {
        id: remoteArgsFile
        path: root.stateDir + "/remote-args.json"
        printErrors: false
        onSaved: {
            remoteProc.output = []
            remoteProc.command = [root.toolsDir + "/remote-control", "start", root.stateDir, path]
            remoteProc.running = true
        }
    }
    Process {
        id: remoteProc
        property var output: []
        stdout: SplitParser { onRead: (l) => remoteProc.output = remoteProc.output.concat([l]) }
        onExited: (code) => {
            const url = remoteProc.output.find(l => l.startsWith("url "))
            root.remoteStarting = false
            root.status = ""
            if (code === 0 && url) {
                root.remote = true
                root.remoteUrl = url.slice(4).trim()
                root.remoteSeen = 0
                root._echoes = []
                root._info("Remote Control is on: continue at [" + root.remoteUrl + "](" + root.remoteUrl
                    + ") or in the Claude app (\"" + root.remoteName + "\"), or here: everything shows on both sides. "
                    + "/rc brings it back to the panel only.")
                root._follow()
            } else {
                root.remotePersona = ""
                root._info("Remote Control didn't start. " + remoteProc.output.map(l => l.replace(/^(error|url) /, "")).join(" "))
            }
            root._save()
        }
    }
    function stopRemote() {
        if (!remote) return
        remoteStop.running = true
    }
    Process { id: remoteStop; command: [root.toolsDir + "/remote-control", "stop"]; onExited: root._remoteEnded() }
    // Ended remotely (/exit there, or the session was closed): notice it
    Timer {
        interval: 5000; repeat: true
        running: root.remote
        onTriggered: if (!remoteCheck.running) remoteCheck.running = true
    }
    Process {
        id: remoteCheck
        command: [root.toolsDir + "/remote-control", "status"]
        onExited: (code) => { if (code !== 0 && root.remote) root._remoteEnded() }
    }
    function _remoteEnded() {
        if (!remote) return
        const pid = remotePersona, sid = sessions[pid]
        remote = false
        remoteUrl = ""
        remoteWorking = false
        remoteAsk = ""
        remoteFollow.running = false
        if (sid) {
            // Anything the live view hadn't shown yet
            remoteImport.persona = pid
            remoteImport.rows = []
            remoteImport.command = [toolsDir + "/session-turns", sid, String(Math.floor(remoteSeen > 0 ? remoteSeen + 1 : remoteSince))]
            remoteImport.running = true
        } else {
            remotePersona = ""
            _save()
        }
    }
    // What was said remotely, into the transcript of the persona it was with
    Process {
        id: remoteImport
        property string persona: ""
        property var rows: []
        stdout: SplitParser {
            onRead: (l) => {
                let d; try { d = JSON.parse(l) } catch (e) { return }
                if (d.role === "user" && root._echoes.includes(d.text.trim())) return
                const text = d.role.startsWith("tool:") ? root.toolSummary(d.role.slice(5), d.input) : d.text
                remoteImport.rows = remoteImport.rows.concat([{ role: d.role, text: text, streaming: false, files: "" }])
            }
        }
        onExited: {
            const rows = remoteImport.rows.concat([{ role: "info", streaming: false, files: "",
                text: "Remote Control ended: the conversation is back in the panel only." }])
            if (root.personaId === remoteImport.persona) {
                for (const r of rows) messagesModel.append(r)
            } else {
                const h = Object.assign({}, root._histories)
                h[remoteImport.persona] = (h[remoteImport.persona] || []).concat(rows.map(r => ({ role: r.role, text: r.text })))
                root._histories = h
            }
            root.remotePersona = ""
            root._echoes = []
            root.remoteSeen = 0
            root._save()
        }
    }
    // After a restart of the shell: is the Remote Control session still there?
    Process {
        id: remoteResume
        command: [root.toolsDir + "/remote-control", "status"]
        onExited: (code) => {
            if (code === 0) { root.remote = true; root._follow() }
            else if (root.remotePersona !== "") { root.remote = true; root._remoteEnded() }
        }
    }

    // ── Code blocks ────────────────────────────────────────────────────────
    // A reply split into Markdown text and fenced code blocks, so the panel
    // can show each block in a box with a Copy button. A block still being
    // streamed (no closing fence yet) counts as code too. Fences indented in
    // a list are recognised, and their indentation taken off the code.
    function segments(md) {
        const out = []
        let buf = [], code = null
        const flush = () => {
            const t = buf.join("\n")
            if (t.trim() !== "") out.push({ kind: "text", text: t, lang: "" })
            buf = []
        }
        for (const l of (md || "").split("\n")) {
            if (code) {
                const end = l.match(/^\s*(`{3,}|~{3,})\s*$/)
                if (end && end[1][0] === code.fence[0] && end[1].length >= code.fence.length) {
                    out.push({ kind: "code", text: code.lines.join("\n"), lang: code.lang })
                    code = null
                } else {
                    code.lines.push(l.replace(code.indent, ""))
                }
                continue
            }
            const start = l.match(/^(\s*)(`{3,}|~{3,})\s*([\w+#.-]*)/)
            if (start) {
                flush()
                code = { fence: start[2], lang: start[3] || "", lines: [],
                         indent: new RegExp("^ {0," + start[1].length + "}") }
                continue
            }
            buf.push(l)
        }
        if (code) out.push({ kind: "code", text: code.lines.join("\n"), lang: code.lang })
        flush()
        return out
    }

    // ── The reply in the character's speech bubble ─────────────────────────
    // The whole reply as plain text (Markdown stripped, code left to the
    // panel), sent as it grows; the overlay types it out at its own pace.
    property int _turn: 0
    Timer { id: speechTimer; interval: 250; onTriggered: root._speak(false) }
    function _speak(final) {
        const text = speechText(_turnText())
        if (text) character.send({ cmd: "speak", text: text, final: final, turn: _turn })
    }
    // Everything it has said since the last message (the text around tool
    // uses comes in several bubbles), so the speech only ever grows
    function _turnText() {
        const parts = []
        for (let i = messagesModel.count - 1; i >= 0; i--) {
            const m = messagesModel.get(i)
            if (m.role === "user") break
            if (m.role === "assistant") parts.unshift(m.text)
        }
        return parts.join("\n\n")
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

    // ── Logging each exchange to the brain ─────────────────────────────────
    property var _logQueue: []
    function _logTurn() {
        let user = ""
        const parts = [], tools = []
        for (let i = messagesModel.count - 1; i >= 0; i--) {
            const m = messagesModel.get(i)
            if (m.role === "user") {
                user = m.text
                if (m.files) user += "\n[attached: " + JSON.parse(m.files).join(", ") + "]"
                break
            }
            if (m.role === "assistant") parts.unshift(m.text)
            else if (m.role.startsWith("tool:")) tools.unshift(m.role.slice(5).replace(/:err$/, " (failed)") + ": " + m.text)
        }
        if (user === "") return
        const id = _runningPersona || personaId
        const p = personas[id] || {}
        const cut = (s, n) => s.length > n ? s.slice(0, n) + "\n…(cut)" : s
        _logQueue.push([id, JSON.stringify({ name: p.name || id, user: cut(user, 30000),
            assistant: cut(parts.join("\n\n"), 60000), tools: tools.slice(0, 40) })])
        _logNext()
    }
    function _logNext() {
        if (brainLogger.running || !_logQueue.length) return
        const [id, payload] = _logQueue.shift()
        brainLogger.command = ["sh", "-c", "[ -f \"$1\" ] && python3 -I \"$1\" log \"$2\" \"$3\"; true",
            "_", brainTool, id, payload]
        brainLogger.running = true
    }
    Process {
        id: brainLogger
        stderr: SplitParser { onRead: (l) => console.warn("assistant brain log:", l) }
        onExited: root._logNext()
    }

    function _finishTurn(errorText) {
        _logTurn()
        const i = _assistantIndex()
        if (i >= 0) messagesModel.setProperty(i, "streaming", false)
        approvalsModel.clear()
        _toolRows = {}
        if (errorText) messagesModel.append({ role: "note", text: errorText, streaming: false, files: "" })
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
            if (o.subtype === "init" && o.slash_commands)
                cliCommands = o.slash_commands.filter(c => !c.startsWith("_") && !(o.terminal_slash_commands || []).includes(c))
            break
        case "stream_event": {
            const e = o.event || {}
            // Another message in the same turn, in the same bubble (after a
            // server-side search; tool uses start a new bubble below their row)
            if (e.type === "message_start") _streamingMsg = (e.message || {}).id || ""
            if (e.type === "message_start" && _turnStarted && _assistantIndex() >= 0) _appendText("\n\n")
            else if (e.type === "content_block_start") {
                const b = e.content_block || {}
                if (b.type === "server_tool_use" || b.type === "tool_use")
                    status = ({ WebFetch: "Reading a page…", web_fetch: "Reading a page…", Bash: "Running a command…",
                                Read: "Reading a file…", Grep: "Searching files…", Glob: "Looking for files…",
                                Edit: "Editing a file…", Write: "Writing a file…" })[b.name] || "Searching the web…"
                else if (b.type === "text") status = ""
            } else if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") {
                _turnStarted = true
                if (_streamingMsg) { const st = Object.assign({}, _streamed); st[_streamingMsg] = true; _streamed = st }
                _appendText(e.delta.text)
            }
            break
        }
        // The whole message once it's done: a row for each tool it used
        case "assistant": {
            const mid = (o.message || {}).id || ""
            for (const c of ((o.message || {}).content || [])) {
                // Text that didn't stream (a slash command's output): show it whole
                if (c.type === "text" && !_streamed[mid] && (c.text || "").trim() !== "") {
                    _turnStarted = true
                    _appendText((_assistantIndex() >= 0 ? "\n\n" : "") + c.text)
                    continue
                }
                if (c.type !== "tool_use") continue
                const i = _assistantIndex()
                if (i >= 0) messagesModel.setProperty(i, "streaming", false)
                messagesModel.append({ role: "tool:" + c.name, text: toolSummary(c.name, c.input), streaming: false, files: "" })
                const r = Object.assign({}, _toolRows); r[c.id] = messagesModel.count - 1; _toolRows = r
            }
            break
        }
        // Tool results: mark the ones that failed or were denied
        case "user": {
            const content = (o.message || {}).content
            if (!Array.isArray(content)) break
            for (const c of content) {
                const row = c.type === "tool_result" ? _toolRows[c.tool_use_id] : undefined
                if (row === undefined || !c.is_error || row >= messagesModel.count) continue
                const role = messagesModel.get(row).role
                if (role.startsWith("tool:") && !role.endsWith(":err")) messagesModel.setProperty(row, "role", role + ":err")
            }
            break
        }
        // The CLI asks before anything that isn't read-only
        case "control_request": {
            const q = o.request || {}
            if (q.subtype !== "can_use_tool") {
                claude.write(JSON.stringify({ type: "control_response",
                    response: { subtype: "error", request_id: o.request_id, error: "Not supported by the panel" } }) + "\n")
                break
            }
            const sug = (q.permission_suggestions || []).filter(s => s.type === "addRules" || s.type === "setMode")
            approvalsModel.append({
                requestId: o.request_id,
                tool: q.tool_name || "",
                summary: toolSummary(q.tool_name, q.input),
                detail: (q.input || {}).description || q.description || _toolDetail(q.tool_name, q.input || {}),
                preview: _toolDetail(q.tool_name, q.input || {}),
                input: JSON.stringify(q.input || {}),
                rule: sug.length ? JSON.stringify(sug) : "",
                ruleText: sug.map(s => s.type === "setMode" ? "every file edit"
                    : (s.rules || []).map(r => r.ruleContent ? (r.toolName === "Bash" ? r.ruleContent : r.toolName + " " + r.ruleContent) : r.toolName).join(", ")).join(" and ")
            })
            status = "Waiting for your OK…"
            character.say(line("ask") || "")
            approvalRequested()
            break
        }
        case "result":
            // A command that answered nothing but its result (/compact…)
            if (!o.is_error && _turnText() === "" && typeof o.result === "string" && o.result.trim() !== "")
                _appendText(o.result)
            _streamed = ({})
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
            // /rc: the panel's CLI is gone, the conversation goes remote
            if (root.remoteStarting && !root.remote) { root._launchRemote = true; root._start(); return }
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
            if (!m.streaming) list.push(m.files ? { role: m.role, text: m.text, files: m.files } : { role: m.role, text: m.text })
        }
        const h = Object.assign({}, _histories); h[_shownPersona] = list; _histories = h
    }
    function _loadHistory() {
        _stash()
        messagesModel.clear()
        for (const m of (_histories[personaId] || [])) messagesModel.append({ role: m.role, text: m.text, streaming: false, files: m.files || "" })
        _shownPersona = personaId
    }
    function _save() {
        if (!_loaded) return
        _stash()
        stateFile.setText(JSON.stringify({ mode: mode, personalPersona: personalPersona, sessions: sessions, model: model, ui: ui,
            remote: remote ? { persona: remotePersona, url: remoteUrl, name: remoteName, since: remoteSince, seen: remoteSeen } : null }, null, 2))
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
            + "error (something went wrong, 2 lines), "
            + "ask (asking the user's OK before doing something on their computer, 2 lines)."
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
            if (s.ui) ui = s.ui
            if (s.remote && s.remote.persona) {
                remotePersona = s.remote.persona; remoteUrl = s.remote.url || ""
                remoteName = s.remote.name || ""; remoteSince = s.remote.since || Date.now()
                remoteSeen = s.remote.seen || 0
                remoteResume.running = true
            }
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
        property real panelRight: 460      // distance from the screen's right edge
        property real bottom: 10           // and from its bottom
        property point screenPos: Qt.point(0, 0)   // the panel's monitor (its top-left)
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
                "--right", String(Math.round(panelRight)), "--bottom", String(Math.round(bottom)),
                "--screen-x", String(Math.round(screenPos.x)), "--screen-y", String(Math.round(screenPos.y))]
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
    // Where the character stands: its right edge `right` px from the screen's
    // right edge, its feet `bottom` px above the bottom (it follows the panel
    // when that floats), on the monitor whose top-left is `screen` (the
    // panel's, so it follows it across monitors)
    function placeCharacter(right, bottom, screen) {
        right = Math.max(0, Math.round(right)); bottom = Math.max(0, Math.round(bottom))
        const sp = screen ? Qt.point(Math.round(screen.x), Math.round(screen.y)) : character.screenPos
        if (right === character.panelRight && bottom === character.bottom
            && sp.x === character.screenPos.x && sp.y === character.screenPos.y) return
        character.panelRight = right; character.bottom = bottom; character.screenPos = sp
        character.send({ cmd: "place", right: right, bottom: bottom, screenX: sp.x, screenY: sp.y })
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
