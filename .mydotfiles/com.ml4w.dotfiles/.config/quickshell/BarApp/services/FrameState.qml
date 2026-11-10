pragma Singleton
import QtQuick

// Shared state of the frame and the drawers that come out of it.
//
// Every FrameDrawer registers here, so the frame (ScreenFrame) can treat the
// frame and all open drawers as one surface: one shared shadow around the lot.
// Each frame only uses the drawers on its own screen (FrameDrawer.screenName).
//
// The drawers opened by a click (sidebar, wallpapers, dock, bar popout, corner
// drawers) are shown one at a time: each claims the frame as it opens, and the
// others close. Their windows leave the frame itself out of their input
// (FrameHoleMask), so a click on the frame while one is open goes straight to
// the frame: it opens the next drawer and the open one slides away, in one
// click.
QtObject {
    id: root

    property var drawers: []

    function add(d) {
        if (drawers.indexOf(d) < 0) drawers = drawers.concat([d])
    }
    function remove(d) {
        drawers = drawers.filter(x => x !== d)
    }

    // The frame windows (one per screen). Drawers holding a Hyprland focus
    // grab include them, so clicking the frame doesn't just drop the grab.
    property var frames: []
    function addFrame(w) {
        if (frames.indexOf(w) < 0) frames = frames.concat([w])
    }
    function removeFrame(w) {
        frames = frames.filter(x => x !== w)
    }

    // "sidebar", "wallpaper", "dock", "popout", "quick", "capture"
    signal claimed(string key)
    function claim(key) { root.claimed(key) }
}
