import QtQuick

// A grip to resize the assistant's panel: a thin strip (or corner) along
// its edges. edges: 1 left, 2 right, 4 bottom (combined for corners).
// Floating, it resizes the card; docked, the drawer's width.
Item {
    id: grip
    property int edges: 0
    // The assistant's window (AssistantWindow)
    required property var win
    property rect start
    z: 10
    HoverHandler {
        cursorShape: grip.edges === 5 ? Qt.SizeBDiagCursor : grip.edges === 6 ? Qt.SizeFDiagCursor
            : grip.edges === 4 ? Qt.SizeVerCursor : Qt.SizeHorCursor
    }
    // Scene positions, not translation: the grip itself moves as the
    // panel grows, and the handle would chase it
    DragHandler {
        target: null
        onActiveChanged: {
            if (active) grip.start = grip.win.floating ? Qt.rect(grip.win.floatX, grip.win.floatY, grip.win.floatW, grip.win.floatH)
                                                   : Qt.rect(0, 0, grip.win.dockWidth, 0)
            else grip.win.saveSizes()
        }
        onCentroidChanged: {
            if (!active) return
            const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
            const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
            if (grip.win.floating) grip.win.resizeFloat(grip.edges, grip.start, dx, dy)
            else grip.win.dockWidth = Math.round(Math.max(grip.win.minWidth, Math.min(grip.win.width * 0.75, grip.start.width - dx)))
        }
    }
}
