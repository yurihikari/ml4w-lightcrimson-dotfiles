pragma Singleton
import QtQuick

// Every FrameDrawer registers here, so the frame (ScreenFrame) can treat the
// frame and all open drawers as one surface: one shared shadow around the lot.
QtObject {
    property var drawers: []

    function add(d) {
        if (drawers.indexOf(d) < 0) drawers = drawers.concat([d])
    }
    function remove(d) {
        drawers = drawers.filter(x => x !== d)
    }
}
