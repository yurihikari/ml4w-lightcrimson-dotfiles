# dotswitch

Switch between complete dotfiles themes (different bars, drawers, Hyprland
config, scripts) while your data (notes, wallpapers, monitor layout, …) follows
you, and snapshot or restore any theme.

## How it works

Every theme is a folder in `~/.mydotfiles/<id>` laid out like your home folder.
This is the layout the ML4W Dotfiles Installer uses, and LightCrimson is
`~/.mydotfiles/com.ml4w.dotfiles`. The active theme's top-level dotfiles are
linked into `~`, and each entry of its `.config` is linked into `~/.config`.

`dotswitch use <theme>` runs these steps in order:

1. **Stop the current theme.** It runs that theme's `.dotswitch/deactivate`
   script, which stops its bar and daemons.
2. **Carry your data.** It copies every path in `~/.config/dotswitch/keep` into
   the new theme. Whatever a copy replaces is saved first.
3. **Swap the links.**
   - Links into the old theme are removed.
   - The new theme's links are created.
   - A real file in the way is moved to the backups, never deleted.
4. **Start the new theme.** It reloads Hyprland, then runs the new theme's
   `.dotswitch/activate` script, which starts its bar and daemons.

If a theme has no `activate` script, log out and back in to start it.

Everything that is replaced is kept in `~/.mydotfiles/backups/dotswitch/`.

## In the shell (LightCrimson)

- **Settings › Themes** shows:
  - the current theme with its preview, and buttons to update the preview,
    take a snapshot and open its folder
  - the other themes: switch, snapshot, open folder, remove
  - a form to create a new theme from the current one
  - the snapshots, each with a restore button
  - the keep list, with a button to edit it
- **Quick settings**, the bottom-left corner, has a *Theme* row. Pick a
  theme, confirm, and everything switches.
- From a keybinding or a script:
  - `qs ipc call themes switchTo <theme>`
  - `qs ipc call themes list`
  - `qs ipc call themes preview`

Switching and restoring the active theme run fully detached, because they
restart the shell itself. Their output goes to
`~/.local/state/dotswitch/ui.log`.

To build a switcher into another theme, read `dotswitch json`. It returns the
themes, the snapshots and the keep list in one object, and the switcher runs
the commands below. LightCrimson's switcher is in
`BarApp/services/Themes.qml`.

`dotswitch preview` saves a screenshot of the focused monitor as the active
theme's thumbnail, in `.dotswitch/preview.png`. Mind what is on screen if you
commit a theme to git.

## Commands

```
dotswitch                      pick a theme (gum menu)
dotswitch list                 installed themes, * = active
dotswitch status               active theme, its links, hooks, keep list
dotswitch use <theme>          switch (-n to only show what would happen)
dotswitch new <id> --from <theme> --name "My theme"
                               start a new theme as a copy of another
dotswitch install <folder>     copy a theme folder (e.g. from this repo) into ~/.mydotfiles
dotswitch save [<theme>]       snapshot a theme (.tar.zst)
dotswitch snapshots            list snapshots
dotswitch restore <theme> [<snapshot>]
                               roll a theme back to a snapshot (keeps your current data)
dotswitch remove <theme>       move a theme out of the store (into backups)
dotswitch keep                 show which of your data is carried
```

A theme is named by its id (the folder name) or by its `name`. Case doesn't
matter.

## Making a new theme

```sh
dotswitch save                                   # snapshot LightCrimson first
dotswitch new com.lightcrimson.popups --from lightcrimson --name "Popups"
# edit ~/.mydotfiles/com.lightcrimson.popups/… (your bar, drawers as popups, …)
dotswitch use popups                             # try it
dotswitch use lightcrimson                       # and back
```

A theme can be completely different: its own `.config/quickshell`, waybar
instead of Quickshell, no ML4W at all. To keep a new theme in this repo, put it
in `.mydotfiles/<id>/`. `install.sh` installs it next to LightCrimson without
activating it.

### The `.dotswitch/` folder of a theme

This folder is never linked into `~`. It can hold three files:

| File         | What it is                                                                                    |
| ------------ | --------------------------------------------------------------------------------------------- |
| `info`       | `name=` and `description=` lines, shown by `dotswitch list`                                    |
| `deactivate` | Runs before switching away, while `~/.config` still points to this theme. Stop what it started. |
| `activate`   | Runs after switching to it, once Hyprland has reloaded. Start its bar and daemons.            |

Both scripts get `DOTSWITCH_FROM`, `DOTSWITCH_TO` and `DOTSWITCH_THEME`, the
theme's folder. See LightCrimson's in
`.mydotfiles/com.ml4w.dotfiles/.dotswitch/`.

Hyprland only runs its `hyprland.start` autostart at login. A live switch
therefore relies on `activate` to start the theme. Put the same commands in
both places.

## Your data: the keep list

`~/.config/dotswitch/keep` lists one path per line, relative to `~`.
`install.sh` seeds it from `dotswitch/keep` and never overwrites it. The
default list covers:

- monitors, keyboard and touchpad
- dock notes and todos
- wallpapers and per-workspace wallpapers
- GTK bookmarks and fish variables
- ML4W default-app and screenshot settings

A path is only carried into a theme that uses that app, meaning the theme has
`~/.config/<app>`. A theme without Quickshell doesn't get `quickshell/`
created. Its notes simply wait in the theme you left, and come back when you
switch back.

Data outside the themes (`~/.cache`, `~/.local/share`, your documents, browser
profiles) is never touched by a switch.
