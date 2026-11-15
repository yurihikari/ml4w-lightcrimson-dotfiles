# AI assistant

A chat drawer on the right side of the screen, in every theme. Open it with
**META+SHIFT+SPACE** (or `qs ipc call assistant toggle`).

It runs the [Claude Code](https://claude.com/claude-code) CLI behind the scenes,
so `claude` must be installed and logged in. It's a chat, not an agent: the only
tools it gets are web search and web fetch. It can't read your files or run
commands. Each conversation is resumed after a restart; **+** starts a new one.

## Modes

- **Assistant**: a regular assistant.
- **Special**: talks as one of the special personas (Arona, Plana). Each
  persona has its own conversation. If you added that persona's character
  files, the character stands next to the panel:
  - **click** her: she says something (a different line for the head and the body)
  - **pat her head** (hold the mouse button and move it left and right over her head): she reacts
  - **click her too much**: she gets dizzy for a bit

Personas live in `personas/*.json`: the system prompt, the lines for greetings,
taps and pats, and optionally which animation to play for each reaction.

## Adding a character

No character art is shipped: you add it yourself. Put a **Spine** export of the
character in:

```
~/.local/share/ml4w-assistant/characters/<persona id>/
    something.skel   (or something.json: the skeleton)
    something.atlas
    something.png    (the textures the atlas names)
```

`<persona id>` is `arona` or `plana`. Spine 3.8, 4.0, 4.1 and 4.2 skeletons work.
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
    --assets ~/.local/share/ml4w-assistant/characters/arona
```

It prints `{"event": "ready", "animations": [...], "headBone": "..."}`. Type
`{"cmd": "react", "kind": "pat"}` and press Enter to try a reaction.

To see what each animation does, step through them with their names in the
speech bubble (here only the numbered ones, 4 seconds each):

```
~/.config/quickshell/AssistantApp/character/preview.sh arona 4 '^[0-9]+$'
```

`qs ipc call assistant poke head|body|pat` fakes a click or a pat on the
character shown with the panel.

Only use character files you have the right to use.

## How it works

- `services/Assistant.qml` starts `claude -p` with stream-json input and
  output once you send the first message. The process stays up for the next
  messages, and is restarted when the persona changes. The user's hooks,
  plugins and MCP servers are not loaded.
- State lives in `~/.local/state/ml4w-assistant/`: `state.json` holds the mode
  and session ids, and `history.json` holds the transcripts.
- Quickshell can't host a web view, so the character is a separate process,
  `character/character.py`: a transparent layer-shell window (GTK 3, WebKitGTK,
  gtk-layer-shell) running the Spine web player. It only runs while the panel
  is open in Special mode and character files are present. It serves the page
  and the character folder on a 127.0.0.1-only port, because the Spine players
  reject files loaded from `file://`. It talks to the
  panel with JSON lines on stdin and stdout.
- The Spine web player is under the
  [Spine Runtimes License](https://esotericsoftware.com/spine-runtimes-license).
  It is downloaded on first use, not shipped here.
