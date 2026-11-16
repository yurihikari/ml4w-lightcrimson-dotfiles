# AI assistant

A chat drawer on the right side of the screen, in every theme. Open it with
**META+SHIFT+SPACE** (or `qs ipc call assistant toggle`).

It runs the [Claude Code](https://claude.com/claude-code) CLI behind the scenes,
so `claude` must be installed and logged in. Each conversation is resumed after
a restart; **+** starts a new one.

## What it can do

Every assistant (the plain one and your own) can search the web, and look into
and act on your computer:

- **Look around:** read files and configs, read logs (`journalctl`), check
  services, processes, disks, network, sound, Bluetooth and packages, and query
  Hyprland. These run right away, and each one shows up in the chat as a small
  row with the command or the file.
- **Drive the desktop:** open, close or toggle the shell's popups and panels
  (`qs ipc call …`, also right away). Ask "show me the quick settings" or "open
  the wallpapers".
- **See the screen:** when you ask it to look at or identify something, it takes
  a screenshot of the focused monitor or window (`tools/screenshot`, saved to
  `~/.local/state/ml4w-assistant/screen.png`) and looks at it.
- **Change things:** file edits in your home and most commands run on their
  own. Sensitive ones stop and ask first: deleting, installing or removing
  packages, starting or stopping services, killing processes, `git push` /
  `reset`, network transfers (`curl`, `ssh`, `rsync`…), sending mail, power
  actions. The panel shows what it wants to do (the command, or the file and
  the change) with **Allow**, **Deny** and, when Claude Code suggests a rule,
  **Always**, which allows that kind of command for the rest of the chat. The
  panel opens itself if it was closed. `qs ipc call assistant allow` / `deny`
  answer from a key binding. Set `trusted` to `false` in
  `services/Assistant.qml` to have it ask before every change instead.
- **Never:** SSH and GPG keys, password stores, browser profiles and other
  credentials are off limits, for file reads and commands alike. `sudo` is
  blocked (there's no terminal for the password): it gives you the command to
  run instead.

The read-only list is `safeCommands`, the sensitive commands `askCommands` and
the off-limits paths `privatePaths`, all in `services/Assistant.qml`.

## Second brain

When `~/brain/tools/brain.py` exists, the assistants share a notes folder,
`~/brain`, as their memory:

- **Context:** each time the CLI starts, `brain.py context <persona>` is added to
  the prompt: the brain's protocol, a profile of you, today's tasks, digests of
  the last days, and today's conversations with every assistant. So what you
  told Arona in the morning, Plana knows in the afternoon.
- **Logs:** every exchange is appended to
  `~/brain/conversations/<persona>/<date>.md` (`brain.py log`), even after **+**
  clears the panel.
- Writing in `~/brain` never asks.

Without `~/brain/tools/brain.py`, none of this runs and the assistants work as
before.

### Starting your own

`examples/brain/` is an empty starter brain, with no personal data:

```sh
~/.config/quickshell/AssistantApp/examples/brain/install.sh   # --no-timer to skip the nightly digest
```

It creates `~/brain` (never over an existing one) as a local git repo, and
enables `brain-digest.timer`. Every night at 23:30, that timer runs
`brain.py digest`, which asks Claude (Sonnet) to summarize the day's
conversations into `memory/daily/`. The digests are what lets the assistants
remember earlier days. Then write how the assistants should call you after
`- Called:` in `~/brain/memory/profile.md`, and press **+**.

What's inside:

| Path | Content |
|---|---|
| `BRAIN.md` | the protocol every assistant follows: capture, tasks, recall, privacy |
| `tasks.md`, `inbox.md` | tasks (Obsidian Tasks format) and quick captures |
| `memory/profile.md` | lasting facts about you, filled in as the assistants learn |
| `blueprints/` | ready-made procedures: `plan-day`, `weekly-review`, `forge` (makes new blueprints), and three for IT support work: `support-ticket`, `troubleshoot`, `client-mail` (FR/EN). Delete the ones you don't need, or ask an assistant to forge your own. |
| `templates/` | client and project files |
| `tools/brain.py` | `context`, `log`, `brief`, `index`, `digest`, `commit` |
| `CLAUDE.md`, `.claude/` | the same memory for `claude` run in a terminal inside `~/brain` |

`~/brain` is plain Markdown, so you can also open it as an Obsidian vault.

## Floating

The float button (next to **+**) pops the panel out of the screen's edge into a
card you drag by its header; the character follows it. It stays open while
other popups come and go. Opening another popup while the panel is docked
(yourself, or the assistant doing it for you) floats it instead of closing it.
The dock button puts it back; closing it docks it again for next time.
`qs ipc call assistant detach` / `dock` do the same.

It opens on the focused monitor. Drag the floating card onto another monitor
and it jumps there as the pointer crosses over (or when you drop it), at the
same size, character included. Resize it from its sides and bottom corners, or
the docked drawer from its inner edge. The sizes are kept in
`~/.local/state/ml4w-assistant/state.json`.

## Commands and Remote Control

Type `/` in the input for the commands (Tab completes the first one):

- **/rc** (or /remote-control): **Remote Control**. Continue the current
  conversation on [claude.ai/code](https://claude.ai/code) or in the Claude
  app, named after the assistant. Claude Code only offers Remote Control in its
  interactive interface, so the conversation moves to one running in a hidden
  tmux session (`tools/remote-control`), with the same prompt, tools and
  permission rules, while the panel's own CLI stops. You can keep working on
  both sides: what's said remotely shows up in the panel as it happens
  (`tools/session-turns --follow`), what you type in the panel goes into the
  session, its approval prompts can be answered in the panel (or with
  `qs ipc call assistant allow` / `deny`) as well as remotely, and the stop
  button interrupts it. The panel shows the link and a **Bring it back**
  button; **/rc** again does the same, and the conversation carries on in the
  panel only. The first time, Claude Code's "trust this folder?" is answered
  for the assistant's state folder. One assistant at a time.
- **/new**: a new chat. **/help**: the list.
- Claude Code's own commands go through as they are: `/compact`, `/context`,
  `/model <name>`, `/usage`… Their output shows as a reply.

## Replies and attachments

- Long words, paths and URLs wrap, so nothing is cut off at any size. Only a
  table wider than the message scrolls sideways.
- Each code block in a reply is a box with its language and a **Copy** button.
  The assistants are told to put every command in its own block.
- A long command waiting for approval scrolls, and a click on a tool line shows
  all of it.
- **Attach** files and images with the paperclip (a file chooser), **Ctrl+V**
  (a copied image or screenshot, or files copied in a file manager; text pastes
  as usual), or by dropping them on the panel. `qs ipc call assistant attach
  <path>` does it from a script. Images are sent as images (big ones scaled
  down by `tools/encode-images`); other files are passed as paths, which the
  assistant reads. Pasted images are saved in
  `~/.local/state/ml4w-assistant/attachments/`. Attachments show in the
  message, and a click opens them.

## Modes

- **Assistant**: a regular assistant.
- **Personal**: your own assistants. None come with the app: the first time,
  **Create an assistant** opens a short form:
  - **name** and an **icon** (a letter, an emoji or a Nerd Font glyph)
  - **what they call you** (optional)
  - **personality**: how they behave and talk, in your own words
  - a **tagline** shown under their name (optional)

  Save, and Claude writes their lines: greetings, and what they say when
  clicked, patted or clicked too much. Each assistant has its own conversation.
  **+ New** adds another; the pencil reopens the form for the current one, with
  buttons to open its file, rewrite its lines, or delete it.

  If you added a character for one, it stands next to the panel:
  - **click** it: it says something (a different line for the head and the body)
  - **pat its head** (hold the mouse button and move it left and right over the head): it reacts
  - **click it too much**: it gets dizzy for a bit

## Personal assistant files

Each one is a JSON file in `~/.local/share/ml4w-assistant/personas/<id>.json`
(the id comes from the name). The form edits the first fields; the rest you can
change by hand, and the panel picks up the change when you save the file:

```json
{
    "name": "Nova",
    "icon": "N",
    "tagline": "Station AI",
    "addressAs": "Captain",
    "personality": "Upbeat, loves stars, talks in nautical metaphors",
    "lines": {
        "greet":   ["Ahoy, Captain!"],
        "tapHead": ["..."], "tapBody": ["..."], "pat": ["..."],
        "dizzy":   ["..."], "thinking": ["..."], "error": ["..."],
        "ask":     ["..."]
    },
    "character": { "animations": {} }
}
```

The system prompt is built from `name`, `personality` and `addressAs`. Add a
`"systemPrompt"` to write your own instead.

### Examples

`examples/personas/` holds ready-made example assistants with their lines and
a full character setup (animations, pat phases and stages, talking). An
example stays hidden until it's fully set up: put its character files in
`~/.local/share/ml4w-assistant/characters/<id>/` and it appears under
Personal. No character art ships with them; use only files you have the right
to use. Editing an example in the form saves your own copy in
`~/.local/share/ml4w-assistant/personas/`, which then replaces the example.

From a terminal or a script:

```
qs ipc call assistant make "Nova" "Captain" "Upbeat, loves stars, talks in nautical metaphors"
qs ipc call assistant persona nova      # switch to it
qs ipc call assistant create            # open the form
qs ipc call assistant remove nova       # delete it (its character files stay)
```

## Adding a character

No character art is shipped: you add it yourself. Put a **Spine** export of the
character in:

```
~/.local/share/ml4w-assistant/characters/<persona id>/
    something.skel   (or something.json: the skeleton)
    something.atlas
    something.png    (the textures the atlas names)
```

`<persona id>` is the personal assistant's id, the name of its file in
`personas/` without `.json`. Spine 3.8, 4.0, 4.1 and 4.2 skeletons work.
The version is read from the skeleton, and the matching Spine web player is
downloaded once to `~/.cache/ml4w-assistant/spine/`.

Animations are guessed from their names: `idle` for the loop, `talk` while a
reply streams in, `pat`/`touch`/`head` for pats, `talk`/`touch`/`tap` for clicks.
Animations in pairs like `Talk_01_A` + `Talk_01_M` (body + mouth) play together.
If the guesses don't fit, add a `character.json` next to the files:

```json
{
    "animations": {
        "idle":    ["Idle_01"],
        "talk":    ["Talk_01_A", "Talk_01_M"],
        "tapHead": ["Talk_02_A", "Talk_02_M"],
        "tapBody": ["Talk_03_A", "Talk_03_M"],
        "pat":     ["Pat_01_A", "Pat_01_M"],
        "error":   ["Talk_04_A"]
    },
    "headBone": "Head",
    "headRadius": 0.08,
    "premultipliedAlpha": true,
    "skin": "default",
    "height": 720
}
```

Every key is optional. Names listed for one reaction play together. A list of
lists gives alternatives, one picked at random each time, e.g. her look pose
plus one of several expressions:

```json
"tapBody": [["Look_01_A", "Look_01_M", "28"], ["Look_01_A", "Look_01_M", "29"]]
```

`talkFlip` makes her talk by alternating still poses (say a closed and an
open mouth) at an uneven, speech-like pace while a reply streams in, with now
and then a short pause; `talkFlipMs` is the time per pose, `[min, max]` in
milliseconds:

```json
"talkFlip": ["00", "02"], "talkFlipMs": [90, 170]
```

Replies also appear in the character's speech bubble, typed out at a
speaking pace a page (a sentence or two) at a time, each left up long enough
to read, with the mouth moving while it types. Long replies stop after a few
pages ("…the rest is in the panel"). `speechCps` sets the pace (characters per
second, 30) and `speechPages` how many pages (4).

`patBone` makes her head follow your hand while you pat: that bone (rigs
often have a `Touch_Point`; the `ready` line lists candidates under
`controlBones`) moves up and down with each stroke, up to `patBoneRange`
units (30), and eases back afterwards.

`patStages` are timed steps during a long pat. Each one can `play`
animations (on tracks of their own, `loop` optional), `stop` animations that
are playing, and `shake` her a little:

```json
"patStages": [
    { "after": 6, "play": ["Dev_Halo_love"], "loop": true },
    { "after": 10, "play": ["14"], "stop": ["Pat_01_A"], "shake": true }
]
```

`patPhases` changes her expression the longer you keep patting: one entry
every `patPhaseSeconds` (3 by default), shown on top of the pat animation.
Pat again within 3 seconds and it carries on from the current phase:

```json
"patPhases": [["03"], ["11"], ["12"]], "patPhaseSeconds": 3, "patPhaseShake": true
```

`patPhaseShake` gives her a little jolt when she reaches the last phase.

Click her too often too fast (`dizzyClicks`, 6, within `dizzyWindow`
seconds, 3) and she gets dizzy: the `dizzy` animations loop for
`dizzySeconds` (5), clicks are ignored meanwhile, and a pat calms her down
early. The persona's `dizzy` lines go in the bubble.

When a reaction has an `…End` animation (`Look_01_A` and `LookEnd_01_A`), the
pose is held while she speaks, then the `…End` plays. `patEnd` names the
animations played when a pat stops (by default, the pat's own `…End` ones).
`headBone` is the bone the pat area is centred on, and `headRadius` is the size
of that area as a fraction of the character's height.
`premultipliedAlpha` is normally detected (from the atlas's `pma:` line, or by
looking at the texture); set it only if the edges still look pale or dark.

To see the animation and bone names, run the overlay on its own:

```
python3 ~/.config/quickshell/AssistantApp/character/character.py \
    --assets ~/.local/share/ml4w-assistant/characters/<id>
```

It prints `{"event": "ready", "animations": [...], "headBone": "..."}`. Type
`{"cmd": "react", "kind": "pat"}` and press Enter to try a reaction.

To see what each animation does, step through them with their names in the
speech bubble (here only the numbered ones, 4 seconds each):

```
~/.config/quickshell/AssistantApp/character/preview.sh <id> 4 '^[0-9]+$'
```

`qs ipc call assistant poke head|body|pat` fakes a click or a pat on the
character shown with the panel.

Only use character files you have the right to use.

## How it works

- `services/Assistant.qml` starts `claude -p` with stream-json input and
  output once you send the first message. The process stays up for the next
  messages, and is restarted when the persona changes. The user's hooks,
  plugins and MCP servers are not loaded.
- Its tools are `WebSearch`, `WebFetch`, `Bash`, `Read`, `Grep`, `Glob`, `Edit`
  and `Write`. The read-only commands are passed as `--allowedTools` rules and
  the private paths as `--disallowedTools`. With `--permission-prompt-tool
  stdio`, anything else makes the CLI send a `can_use_tool` request on stdout,
  which the panel answers on stdin after you click.
- State lives in `~/.local/state/ml4w-assistant/`: `state.json` holds the mode
  and session ids, and `history.json` holds the transcripts.
- Quickshell can't host a web view, so the character is a separate process,
  `character/character.py`: a transparent layer-shell window (GTK 3, WebKitGTK,
  gtk-layer-shell) running the Spine web player. It only runs while the panel
  is open in Personal mode and character files are present. It serves the page
  and the character folder on a 127.0.0.1-only port, because the Spine players
  reject files loaded from `file://`. It talks to the
  panel with JSON lines on stdin and stdout.
- The Spine web player is under the
  [Spine Runtimes License](https://esotericsoftware.com/spine-runtimes-license).
  It is downloaded on first use, not shipped here.
