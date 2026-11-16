#!/usr/bin/env python3
"""Animated character for the assistant's special personas.

A transparent layer-shell window (GTK 3 + WebKitGTK + gtk-layer-shell) that
plays a Spine skeleton with the official Spine web player, next to the
assistant panel. Quickshell can't host a web view, so this runs as its own
process, only while the panel is open in special mode.

Assets are not shipped: put a Spine export (a .skel or .json skeleton, its
.atlas and the textures) in the folder given with --assets. The matching Spine
web player (3.8, 4.0, 4.1 or 4.2, read from the skeleton) is downloaded once to
~/.cache/ml4w-assistant/spine/. An optional character.json in the assets folder
overrides the persona's settings (see the README).

Protocol, one JSON object per line:
  stdin   {"cmd": "say", "text": "..."}       speech bubble
          {"cmd": "react", "kind": "..."}     idle | talk | tapHead | tapBody | pat | error
          {"cmd": "place", "right": 460, "bottom": 10,   move (margins from the
           "screenX": 0, "screenY": 0}                 screen's right and bottom;
                                                       the monitor whose top-left
                                                       is at screenX, screenY)
          {"cmd": "quit"}
  stdout  {"event": "ready", "animations": [...], "version": "4.1"}
          {"event": "tap", "region": "head" | "body"}
          {"event": "pat"}
          {"event": "error", "message": "..."}
"""
import argparse
import http.server
import json
import os
import re
import sys
import threading
import urllib.request
from urllib.parse import quote, unquote
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell, WebKit2  # noqa: E402

HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "ml4w-assistant" / "spine"

# Spine web player builds, by skeleton version (major.minor)
PLAYERS = {
    "3.8": "https://cdn.jsdelivr.net/gh/EsotericSoftware/spine-runtimes@3.8/spine-ts/build/spine-player.js",
    "4.0": "https://cdn.jsdelivr.net/npm/@esotericsoftware/spine-player@4.0.31/dist/iife/spine-player.js",
    "4.1": "https://cdn.jsdelivr.net/npm/@esotericsoftware/spine-player@4.1.56/dist/iife/spine-player.js",
    "4.2": "https://cdn.jsdelivr.net/npm/@esotericsoftware/spine-player@4.2.97/dist/iife/spine-player.js",
}


def emit(**event):
    print(json.dumps(event), flush=True)


def find_assets(folder: Path, cfg: dict):
    """The skeleton and atlas in the assets folder (character.json may name them)."""
    skel = folder / cfg["skeleton"] if cfg.get("skeleton") else None
    atlas = folder / cfg["atlas"] if cfg.get("atlas") else None
    if skel is None:
        cands = sorted(folder.glob("*.skel")) + sorted(
            p for p in folder.glob("*.json") if p.name != "character.json")
        skel = cands[0] if cands else None
    if atlas is None:
        cands = sorted(folder.glob("*.atlas"))
        if skel is not None:
            same = [a for a in cands if a.stem == skel.stem]
            cands = same or cands
        atlas = cands[0] if cands else None
    return skel, atlas


def spine_version(skel: Path) -> str:
    head = skel.read_bytes()[:512]
    m = re.search(rb'"spine"\s*:\s*"(\d+\.\d+)' if skel.suffix == ".json" else rb"(\d\.\d+)\.\d+", head)
    return m.group(1).decode() if m else "4.1"


def atlas_pma(atlas: Path):
    m = re.search(r"^\s*pma\s*:\s*(true|false)", atlas.read_text(errors="replace"), re.M)
    return None if not m else m.group(1) == "true"


def first_texture(atlas: Path):
    for line in atlas.read_text(errors="replace").splitlines():
        if re.search(r"\.(png|webp|jpg)$", line.strip(), re.I):
            return "/assets/" + quote(line.strip())
    return None


def player_js(version: str) -> Path:
    url = PLAYERS.get(version) or PLAYERS["4.1"]
    dest = CACHE / version / "spine-player.js"
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=30) as r, open(tmp, "wb") as f:
            f.write(r.read())
        tmp.rename(dest)
    return dest


def serve(page: bytes, js: Path, folder: Path) -> int:
    """Serve the stage on 127.0.0.1 (a free port) and return the port.

    The Spine players load files with XMLHttpRequest and only accept HTTP 200;
    file:// requests report status 0, which the 3.8 player turns into an
    "InvalidStateError". So the page, the player and the assets folder (only
    that folder, read-only) are served over a local HTTP server instead.
    """
    root = folder.resolve()
    types = {".png": "image/png", ".atlas": "text/plain", ".json": "application/json",
             ".skel": "application/octet-stream", ".js": "text/javascript"}

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            path = unquote(self.path.split("?", 1)[0])
            if path == "/":
                body, ctype = page, "text/html; charset=utf-8"
            elif path == "/player.js":
                body, ctype = js.read_bytes(), "text/javascript"
            elif path.startswith("/assets/"):
                f = (root / path[len("/assets/"):]).resolve()
                if root not in f.parents or not f.is_file():
                    return self.send_error(404)
                body, ctype = f.read_bytes(), types.get(f.suffix.lower(), "application/octet-stream")
            else:
                return self.send_error(404)
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server.server_address[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--config", default="{}", help="the persona's character settings (JSON)")
    ap.add_argument("--right", type=int, default=460, help="distance from the screen's right edge")
    ap.add_argument("--bottom", type=int, default=10)
    ap.add_argument("--screen-x", type=int, default=None, help="the monitor's top-left, in the layout")
    ap.add_argument("--screen-y", type=int, default=None)
    ap.add_argument("--width", type=int, default=0)
    ap.add_argument("--height", type=int, default=0)
    args = ap.parse_args()

    folder = Path(args.assets).expanduser()
    cfg = json.loads(args.config or "{}")
    local = folder / "character.json"
    if local.exists():
        try:
            over = json.loads(local.read_text())
            anims = {**cfg.get("animations", {}), **over.get("animations", {})}
            cfg = {**cfg, **over, "animations": anims}
        except ValueError as e:
            emit(event="error", message=f"character.json: {e}")

    skel, atlas = find_assets(folder, cfg)
    if not skel or not atlas:
        emit(event="error", message=f"no skeleton/atlas in {folder}")
        return 1
    version = str(cfg.get("spineVersion") or spine_version(skel))
    try:
        js = player_js(version[:3])
    except OSError as e:
        emit(event="error", message=f"could not download the Spine {version} player: {e}")
        return 1

    # Size: a portrait strip, scaled to the screen
    display = Gdk.Display.get_default()

    def monitor_at(x, y):
        """The monitor whose top-left is (x, y) in the layout, else the closest one."""
        if not display or x is None or y is None:
            return None
        mons = [display.get_monitor(i) for i in range(display.get_n_monitors())]
        mons = [m for m in mons if m]
        if not mons:
            return None

        def dist(m):
            g = m.get_geometry()
            return abs(g.x - x) + abs(g.y - y)
        return min(mons, key=dist)

    mon = monitor_at(args.screen_x, args.screen_y) \
        or (display.get_monitor_at_window(Gdk.get_default_root_window()) if display else None)
    geo = mon.get_geometry() if mon else None
    screen_h = geo.height if geo else 1080
    height = args.height or int(cfg.get("height") or min(720, screen_h * 0.62))
    width = args.width or int(cfg.get("width") or height * 0.62)

    win = Gtk.Window()
    win.set_app_paintable(True)
    visual = win.get_screen().get_rgba_visual()
    if visual:
        win.set_visual(visual)
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_namespace(win, "ml4w-assistant-character")
    if mon and args.screen_x is not None:
        GtkLayerShell.set_monitor(win, mon)
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE)
    GtkLayerShell.set_exclusive_zone(win, -1)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.RIGHT, args.right)
    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, args.bottom)
    win.set_size_request(width, height)

    manager = WebKit2.UserContentManager()
    manager.register_script_message_handler("bridge")
    view = WebKit2.WebView.new_with_user_content_manager(manager)
    view.set_background_color(Gdk.RGBA(0, 0, 0, 0))
    s = view.get_settings()
    s.set_enable_webgl(True)
    s.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.ALWAYS)
    s.set_enable_developer_extras(bool(os.environ.get("ASSISTANT_CHARACTER_DEBUG")))

    def on_message(_mgr, result):
        try:
            value = result.get_js_value().to_string()
        except AttributeError:  # newer WebKit hands the JSCValue directly
            value = result.to_string()
        try:
            print(json.dumps(json.loads(value)), flush=True)
        except ValueError:
            pass

    manager.connect("script-message-received::bridge", on_message)

    def run_js(code):
        view.evaluate_javascript(code, -1, None, None, None, None, None) \
            if hasattr(view, "evaluate_javascript") else view.run_javascript(code, None, None, None)

    # Read straight from the fd: several commands often arrive at once, and a
    # buffered readline() would leave all but the first waiting for more input
    pending = b""

    def on_stdin(fd, _cond):
        nonlocal pending
        chunk = os.read(fd, 65536)
        if not chunk:  # the panel went away
            Gtk.main_quit()
            return False
        pending += chunk
        *lines, pending = pending.split(b"\n")
        for line in lines:
            try:
                cmd = json.loads(line)
            except ValueError:
                continue
            if cmd.get("cmd") == "quit":
                Gtk.main_quit()
                return False
            if cmd.get("cmd") == "place":  # follow the panel (it can float)
                try:
                    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.RIGHT, max(0, int(cmd.get("right", args.right))))
                    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, max(0, int(cmd.get("bottom", args.bottom))))
                    if "screenX" in cmd and "screenY" in cmd:
                        m = monitor_at(int(cmd["screenX"]), int(cmd["screenY"]))
                        if m and m != GtkLayerShell.get_monitor(win):
                            GtkLayerShell.set_monitor(win, m)
                except (TypeError, ValueError):
                    pass
                continue
            run_js(f"window.stage && window.stage.command({json.dumps(cmd)})")
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_stdin)

    params = {
        "skeleton": "/assets/" + quote(skel.name),
        "binary": skel.suffix != ".json",
        "atlas": "/assets/" + quote(atlas.name),
        # Premultiplied alpha, when the atlas says (4.x atlases have "pma: true")
        "atlasPma": atlas_pma(atlas),
        "texture": first_texture(atlas),
        "debug": bool(os.environ.get("ASSISTANT_CHARACTER_DEBUG")),
        "version": version,
        "config": cfg,
    }
    html = (HERE / "stage.html").read_text()
    html = html.replace("/*PLAYER_JS*/", "/player.js").replace("/*PARAMS*/{}", json.dumps(params))
    port = serve(html.encode(), js, folder)
    view.load_uri(f"http://127.0.0.1:{port}/")

    win.add(view)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
