pragma Singleton
import QtQuick

// Which of the frame's inner corners are currently taken over by a FrameDrawer
// (a drawer flush against a side frame draws that corner itself), per screen.
// The frame hides its own corner piece while a count is above zero, so the two
// never stack. Counts rather than flags, in case two drawers share a corner;
// keyed by screen so a drawer on one monitor doesn't square off the others.
QtObject {
    // "<screen>:<corner>" → count; corner is topLeft/topRight/bottomLeft/bottomRight
    property var counts: ({})

    function add(screen, corner, delta) {
        const c = Object.assign({}, counts)
        const k = screen + ":" + corner
        c[k] = Math.max(0, (c[k] || 0) + delta)
        counts = c
    }

    function taken(screen, corner) {
        return (counts[screen + ":" + corner] || 0) > 0
    }
}
