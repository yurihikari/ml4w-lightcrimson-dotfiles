pragma Singleton
import QtQuick

// Which of the frame's inner corners are currently taken over by a FrameDrawer
// (a drawer flush against a side frame draws that corner itself). The frame
// hides its own corner piece while the count is above zero, so the two never
// stack. Counts rather than flags, in case two drawers share a corner.
QtObject {
    property int topLeft: 0
    property int topRight: 0
    property int bottomLeft: 0
    property int bottomRight: 0
}
