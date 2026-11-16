import QtQuick
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services

// The Markdown between code blocks in a reply. Long words, paths and URLs
// wrap anywhere rather than being cut off. Only a table wider than the
// bubble still can't wrap: then it scrolls sideways (shift+wheel, or the bar).
Flickable {
    id: root
    property alias text: te.text

    readonly property bool overflows: te.contentWidth > width + 1
    implicitHeight: te.implicitHeight + (overflows ? 10 : 0)
    contentWidth: Math.max(width, te.contentWidth)
    contentHeight: te.implicitHeight
    clip: overflows
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    // Not interactive otherwise: the wheel keeps scrolling the chat
    interactive: overflows
    ScrollBar.horizontal: ScrollBar { policy: root.overflows ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

    TextEdit {
        id: te
        width: root.width
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.MarkdownText
        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
        color: Theme.primary
        selectionColor: Theme.withAlpha(Theme.primary, 0.3)
        selectedTextColor: Theme.primary
        font.family: Theme.fontFamily; font.pixelSize: PanelStyle.bodySize + 1
        onLinkActivated: (link) => Qt.openUrlExternally(link)
    }
}
